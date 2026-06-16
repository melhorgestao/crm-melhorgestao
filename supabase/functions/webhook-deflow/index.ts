// ============================================================================
// webhook-deflow — recebe POST do DeFlow quando depósito é
// pago/expirado/aprovado.
//
// Eventos esperados:
//   - deposit.completed → terminal de sucesso (DePix creditado)
//   - deposit.approved  → tratamos como completed (gravação atômica)
//   - deposit.expired   → marca pedido como expirado e libera contato
//
// Payload assumido (validar contra primeira chamada real):
//   {
//     event: "deposit.completed",
//     data: {
//       id: "67234abc...",        // deposit.id que linka ao pedido_em_aberto.pix_id
//       status: "depix_sent",
//       amountCents: 10000,
//       feeCents: 200,
//       netAmountCents: 9800,
//       ...
//     }
//   }
//
// Após processar:
//   - chama processar_webhook_deflow RPC (atomicidade)
//   - dispara webhook n8n pra notificar cliente via WhatsApp
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-df-signature',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const payload = await req.json()
    const event = payload.event || payload.type
    const data  = payload.data || payload
    const depositId = data.id || data.depositId || data.deposit_id

    if (!event || !depositId) {
      return j({ error: 'payload inválido — faltam event/data.id' }, 400)
    }

    // Tolerância de campo de status/valores (defensivo até validar payload real)
    const status     = data.status ?? null
    const amount     = Number(data.amountCents ?? data.amount_cents ?? data.amount ?? 0)
    const fee        = Number(data.feeCents ?? data.fee_cents ?? data.fee ?? 0)
    const net        = Number(data.netAmountCents ?? data.net_amount_cents ?? data.netAmount ?? (amount - fee))

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // (opcional) Verificar assinatura via X-DF-Signature — pendente até DeFlow
    // documentar exatamente o mecanismo (HMAC?). Por ora, confiamos no segredo
    // do path (o webhook URL é privado).

    // Log defensivo do payload inteiro (debug em primeira execução real)
    try {
      await supabase.from('eventos_contato').insert({
        contato_id: null,
        tipo: 'webhook_deflow',
        metadata: { event, depositId, status, amount, fee, net, raw: payload },
      })
    } catch { /* log opcional */ }

    // Processa via RPC atômica
    const { data: rpcRes, error: rpcErr } = await supabase.rpc('processar_webhook_deflow', {
      p_event:        event,
      p_deposit_id:   String(depositId),
      p_status:       status,
      p_amount_cents: amount,
      p_fee_cents:    fee,
      p_net_cents:    net,
    })
    if (rpcErr) return j({ ok: false, error: rpcErr.message }, 500)

    const result = rpcRes as any
    if (!result?.ok) return j(result, 200)  // 200 mesmo se não casou — evita retry infinito do DeFlow

    // Dispara webhook n8n pra notificar cliente via WhatsApp (fire-and-forget)
    try {
      const { data: cfg } = await supabase
        .from('configuracoes').select('valor')
        .eq('chave', 'deflow_webhook_n8n_url').maybeSingle()
      const n8nUrl = (cfg?.valor as string | undefined)?.trim()

      if (n8nUrl) {
        // Não aguarda — fire and forget
        fetch(n8nUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            event,
            pedido_em_aberto_id: result.pedido_em_aberto_id,
            fechamento: result.fechamento || null,
            acao: result.acao || null,
          }),
        }).catch(e => console.error('n8n notify failed:', e))
      }
    } catch { /* não falha o webhook por causa de notify */ }

    return j({ ok: true, processed: result })

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ ok: false, error: msg }, 500)
  }
})

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

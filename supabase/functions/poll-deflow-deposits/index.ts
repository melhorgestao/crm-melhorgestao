// ============================================================================
// poll-deflow-deposits — CINTO DE SEGURANÇA do reconhecimento de pagamento.
//
// O webhook da DeFlow é frágil (já se auto-desativou por falhas). Este edge é
// chamado por um cron (a cada ~2min) e faz o caminho INVERSO: pergunta pra
// DeFlow o status de cada PIX pendente e fecha o pedido se estiver pago —
// SEM depender do webhook. Usa a MESMA RPC idempotente (processar_webhook_
// deflow), então rodar junto com o webhook não duplica nada.
//
// Fluxo: pega pedido_em_aberto 'aguardando_pagamento' com pix_id →
//        GET /v1/deposit-status/:id → se pago: fecha + notifica n8n;
//        se expirado: marca expirado.
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const DEFLOW_BASE = 'https://api.deflow.exchange'

// Extração à prova de nome (mesma lógica do gerar-pix/webhook).
function pickCents(obj: any, keys: string[]): number | null {
  if (!obj || typeof obj !== 'object') return null
  const containers = [obj, obj.values, obj.valores, obj.amounts, obj.fees, obj.valor]
  for (const c of containers) {
    if (!c || typeof c !== 'object') continue
    for (const k of keys) {
      const v = (c as any)[k]
      if (v != null && Number.isFinite(Number(v))) return Number(v)
    }
  }
  return null
}
const AMOUNT_KEYS = ['amountInCents', 'amount_in_cents', 'amountCents', 'amount_cents', 'amount', 'valorCents', 'valor']
const FEE_KEYS    = ['feeCents', 'fee_cents', 'feeInCents', 'fee_in_cents', 'fee', 'taxaCents', 'taxa_cents', 'taxa']
const NET_KEYS    = ['netAmountCents', 'net_amount_cents', 'netInCents', 'net_in_cents', 'netCents', 'net_cents', 'netAmount', 'net', 'liquidoCents', 'liquido_cents', 'liquido']

const RE_PAGO     = /^(paid|completed|approved|confirmed|success|succeeded|pago|aprovado)$/i
const RE_EXPIRADO = /^(expired|canceled|cancelled|expirado|cancelado)$/i

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // credenciais DeFlow + url n8n
    const { data: cfgs } = await supabase.from('configuracoes').select('chave, valor')
      .in('chave', ['deflow_api_key', 'deflow_secret', 'deflow_passphrase', 'deflow_webhook_n8n_url'])
    const cfg: Record<string, string> = {}
    for (const c of (cfgs || []) as any[]) cfg[c.chave] = (c.valor as string || '').trim()
    if (!cfg['deflow_api_key'] || !cfg['deflow_secret'] || !cfg['deflow_passphrase']) {
      return j({ ok: false, error: 'credenciais DeFlow ausentes' })
    }

    // pedidos aguardando com PIX real gerado, dos últimos 3 dias (janela de expiração)
    const desde = new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString()
    const { data: pendentes } = await supabase.from('pedido_em_aberto')
      .select('id, pix_id')
      .eq('status', 'aguardando_pagamento')
      .not('pix_id', 'is', null)
      .gte('created_at', desde)
      .order('created_at', { ascending: true })
      .limit(40)

    const alvos = (pendentes || []).filter(p => p.pix_id && !String(p.pix_id).startsWith('STUB-'))
    const dfHeaders = {
      'Authorization':   `Bearer ${cfg['deflow_api_key']}`,
      'X-DF-Secret':     cfg['deflow_secret'],
      'X-DF-Passphrase': cfg['deflow_passphrase'],
      'Content-Type':    'application/json',
    }

    let fechados = 0, expirados = 0, verificados = 0
    for (const p of alvos) {
      verificados++
      let d: any
      try {
        const r = await fetch(`${DEFLOW_BASE}/v1/deposit-status/${encodeURIComponent(p.pix_id)}`, { headers: dfHeaders })
        if (!r.ok) continue
        const body = await r.json().catch(() => null)
        d = body?.data || body
      } catch { continue }
      if (!d) continue

      const status = String(d.status ?? '')
      if (RE_PAGO.test(status)) {
        const amount = pickCents(d, AMOUNT_KEYS) ?? 0
        const fee    = pickCents(d, FEE_KEYS) ?? 0
        const net    = pickCents(d, NET_KEYS) ?? (amount - fee)
        const { data: res, error } = await supabase.rpc('processar_webhook_deflow', {
          p_event: 'deposit.completed', p_deposit_id: String(p.pix_id), p_status: 'completed',
          p_amount_cents: amount, p_fee_cents: fee, p_net_cents: net,
        })
        if (!error && (res as any)?.ok) {
          fechados++
          const fresh = !(res as any)?.fechamento?.idempotente
          // notifica n8n (mesma forma do webhook → mensagem "aprovado" pro cliente)
          if (cfg['deflow_webhook_n8n_url'] && fresh) {
            fetch(cfg['deflow_webhook_n8n_url'], {
              method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                event: 'deposit.completed',
                pedido_em_aberto_id: (res as any)?.pedido_em_aberto_id ?? p.id,
                fechamento: (res as any)?.fechamento ?? null,
                acao: 'pago_via_polling',
              }),
            }).catch(() => {})
          }
          // SINAL "webhook fora": se o depósito foi pago há > 3 min e só o
          // polling fechou (o webhook teve tempo e não processou), marca um
          // evento pro sino do CRM avisar. paidAt ausente → não sinaliza
          // (evita falso alarme quando o polling roda logo após o pagamento).
          if (fresh) {
            const paidAt = d.paidAt || d.paid_at || d.pagoEm || d.pago_em || null
            const paidMs = paidAt ? Date.parse(String(paidAt)) : NaN
            if (Number.isFinite(paidMs) && (Date.now() - paidMs > 3 * 60 * 1000)) {
              try {
                await supabase.from('eventos_contato').insert({
                  contato_id: null, tipo: 'deflow_webhook_miss',
                  metadata: { depositId: p.pix_id, paidAt, pedido_em_aberto_id: p.id },
                })
              } catch { /* sinal é best-effort */ }
            }
          }
        }
      } else if (RE_EXPIRADO.test(status)) {
        await supabase.rpc('processar_webhook_deflow', {
          p_event: 'deposit.expired', p_deposit_id: String(p.pix_id), p_status: 'expired',
          p_amount_cents: 0, p_fee_cents: 0, p_net_cents: 0,
        })
        expirados++
      }
    }

    return j({ ok: true, verificados, fechados, expirados })
  } catch (err) {
    return j({ ok: false, error: err instanceof Error ? err.message : String(err) })
  }
})

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status,
  })
}

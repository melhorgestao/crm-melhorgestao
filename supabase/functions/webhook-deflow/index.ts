// ============================================================================
// webhook-deflow — recebe POST do DeFlow (deposit.completed/approved/expired)
//
// Segurança:
//   - Valida assinatura DF-Signature (HMAC-SHA256 timing-safe)
//   - Anti-replay: rejeita timestamp >5min de tolerância
//   - Deduplica por event.id (cache em eventos_contato)
//
// Eventos:
//   - deposit.completed → fecha pedido + lança VENDA na caixa (líquido)
//   - deposit.approved  → idem (DePix ainda em preparação mas Pix confirmado)
//   - deposit.expired   → marca rascunho expirado, mantém contato em_fechamento
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, df-signature, x-df-signature',
}

const TOLERANCE_SECONDS = 5 * 60   // 5 minutos pra anti-replay

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    // Lê raw body como TEXTO antes de fazer JSON.parse — necessário pra HMAC
    const rawBody = await req.text()
    if (!rawBody) return j({ error: 'body vazio' }, 400)

    let payload: any
    try { payload = JSON.parse(rawBody) }
    catch { return j({ error: 'body não é JSON' }, 400) }

    const event = payload.event || payload.type
    const data  = payload.data || payload
    const depositId = data.id || data.depositId || data.deposit_id
    const eventId   = payload.id || payload.event_id || `${event}:${depositId}:${data.status || ''}`

    if (!event || !depositId) {
      return j({ error: 'payload inválido — faltam event/data.id' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // -----------------------------------------------------------------------
    // 1) VALIDAÇÃO HMAC — só se secret configurado
    // -----------------------------------------------------------------------
    const { data: cfgSecret } = await supabase
      .from('configuracoes').select('valor')
      .eq('chave', 'deflow_webhook_secret').maybeSingle()
    const webhookSecret = (cfgSecret?.valor as string | undefined)?.trim()

    if (webhookSecret) {
      const sigHeader = req.headers.get('df-signature') || req.headers.get('DF-Signature')
                     || req.headers.get('x-df-signature')
      if (!sigHeader) return j({ error: 'DF-Signature ausente' }, 401)

      // Formato: "t=1700000000, v1=abc123..."
      const parts = Object.fromEntries(
        sigHeader.split(',').map(p => p.trim().split('=')).filter(p => p.length === 2)
      )
      const t  = parts['t']
      const v1 = parts['v1']
      if (!t || !v1) return j({ error: 'DF-Signature mal formado' }, 401)

      const now = Math.floor(Date.now() / 1000)
      const tsNum = Number(t)
      if (!Number.isFinite(tsNum) || Math.abs(now - tsNum) > TOLERANCE_SECONDS) {
        return j({ error: 'timestamp fora da tolerância (replay?)' }, 401)
      }

      const signed = `${t}.${rawBody}`
      const expected = await hmacSHA256Hex(webhookSecret, signed)
      if (!timingSafeEqualHex(expected, v1)) {
        return j({ error: 'assinatura inválida' }, 401)
      }
    }
    // Se webhookSecret não configurado, aceita sem validar (modo dev/setup)

    // -----------------------------------------------------------------------
    // 2) DEDUPLICAÇÃO — evita processar mesmo evento 2x
    // -----------------------------------------------------------------------
    try {
      const { data: jaExiste } = await supabase
        .from('eventos_contato')
        .select('id')
        .eq('tipo', 'webhook_deflow')
        .filter('metadata->>eventId', 'eq', String(eventId))
        .gte('created_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
        .limit(1)
      if (jaExiste && jaExiste.length > 0) {
        return j({ ok: true, deduplicado: true, eventId })
      }
    } catch { /* sem dedupe se erro de schema */ }

    // -----------------------------------------------------------------------
    // 3) EXTRAÇÃO DEFENSIVA dos campos (camelCase + snake_case)
    // -----------------------------------------------------------------------
    const status = data.status ?? null
    const amount = Number(data.amountCents ?? data.amount_cents ?? data.amount ?? 0)
    const fee    = Number(data.feeCents ?? data.fee_cents ?? data.fee ?? 0)
    const net    = Number(data.netAmountCents ?? data.net_amount_cents ?? data.netAmount ?? (amount - fee))

    // Log do payload (auditoria + dedup)
    try {
      await supabase.from('eventos_contato').insert({
        contato_id: null,
        tipo: 'webhook_deflow',
        metadata: { event, depositId, eventId, status, amount, fee, net, raw: payload },
      })
    } catch { /* log opcional */ }

    // -----------------------------------------------------------------------
    // 4) PROCESSA via RPC atômica
    // -----------------------------------------------------------------------
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
    if (!result?.ok) return j(result, 200)  // 200 mesmo se não casou — evita retry infinito

    // -----------------------------------------------------------------------
    // 5) NOTIFICA n8n pra mandar WhatsApp pro cliente (fire-and-forget)
    // -----------------------------------------------------------------------
    try {
      const { data: cfg } = await supabase
        .from('configuracoes').select('valor')
        .eq('chave', 'deflow_webhook_n8n_url').maybeSingle()
      const n8nUrl = (cfg?.valor as string | undefined)?.trim()
      if (n8nUrl) {
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

// ============================================================================
// Helpers HMAC
// ============================================================================
async function hmacSHA256Hex(secret: string, data: string): Promise<string> {
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false, ['sign']
  )
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(data))
  return Array.from(new Uint8Array(sig))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

// ============================================================================
// gerar-pix-deflow — DeFlow real (POST /v1/deposit/create, mode=exact)
//
// Modo "exact": cliente paga o valor BRUTO do pedido. DeFlow desconta taxa
// do crédito. Recebemos LÍQUIDO (netAmountCents) — esse vai pra caixa.
//
// Linkagem pedido_em_aberto.pix_id = deposit.id (lookup reverso no webhook).
// X-DF-Idempotency-Key é UUID determinístico baseado no pedido_em_aberto_id
// pra evitar criar 2 depósitos diferentes pro mesmo pedido em retry.
//
// INPUT:  { pedido_em_aberto_id: uuid }
// OUTPUT: { ok, pix_id, pix_copia_cola, pix_qr_image_url, pix_expira_em,
//           valor_bruto, valor_liquido, taxa, modo }
//
// Fallback STUB: se faltar credencial DeFlow em configuracoes, retorna
// QR placeholder pra ainda permitir testes do fluxo n8n.
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const DEFLOW_BASE = 'https://api.deflow.exchange'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { pedido_em_aberto_id } = await req.json()
    if (!pedido_em_aberto_id) return j({ error: 'pedido_em_aberto_id obrigatório' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: pedido, error: pErr } = await supabase
      .from('pedido_em_aberto')
      .select('id, contato_id, total, status, valor_primeira_parcela, is_parcelado, is_cobranca_saldo, pix_id, pix_copia_cola, pix_qr_image_url, pix_expira_em, pix_liquido_cents, pix_taxa_cents')
      .eq('id', pedido_em_aberto_id).single()
    if (pErr || !pedido) return j({ error: 'pedido não encontrado' }, 404)
    if (pedido.status !== 'aguardando_pagamento') {
      return j({ error: `pedido em estado inválido: ${pedido.status}` }, 400)
    }

    // Idempotente: se já tem Pix gerado, devolve o existente
    if (pedido.pix_copia_cola) {
      return j({
        ok: true, idempotente: true,
        pix_id:          pedido.pix_id,
        pix_copia_cola:  pedido.pix_copia_cola,
        pix_qr_image_url: pedido.pix_qr_image_url,
        pix_expira_em:   pedido.pix_expira_em,
        valor_bruto:     Number(pedido.total),
        valor_liquido:   pedido.pix_liquido_cents ? pedido.pix_liquido_cents / 100 : null,
        taxa:            pedido.pix_taxa_cents ? pedido.pix_taxa_cents / 100 : null,
      })
    }

    // VALOR a cobrar: se parcelado, é a 1ª parcela (50%); senão, total
    const valorBruto = Number(pedido.valor_primeira_parcela ?? pedido.total)
    const amountCents = Math.round(valorBruto * 100)
    if (!Number.isFinite(amountCents) || amountCents <= 0) {
      return j({ error: 'valor inválido pra gerar Pix' }, 400)
    }

    // Credenciais DeFlow
    const { data: configs } = await supabase
      .from('configuracoes').select('chave, valor')
      .in('chave', ['deflow_api_key','deflow_secret','deflow_passphrase','deflow_wallet_id'])
    const cfg: Record<string,string> = {}
    for (const c of (configs || []) as any[]) cfg[c.chave] = (c.valor as string || '').trim()

    const apiKey     = cfg['deflow_api_key']
    const secret     = cfg['deflow_secret']
    const passphrase = cfg['deflow_passphrase']
    const walletId   = cfg['deflow_wallet_id']

    // STUB se faltar credencial — permite testar fluxo sem DeFlow real
    if (!apiKey || !secret || !passphrase) {
      const stubId   = `STUB-${pedido.id}`
      const stubCola = `00020126360014BR.GOV.BCB.PIX0114STUB${pedido.id.slice(0,8)}520400005303986540${valorBruto.toFixed(2)}5802BR5910SANTA FLOR6009SAO PAULO62070503***6304STUB`
      const expira   = new Date(Date.now() + 24 * 3600 * 1000).toISOString()

      await supabase.from('pedido_em_aberto').update({
        pix_id: stubId,
        pix_copia_cola: stubCola,
        pix_qr_base64: '',
        pix_qr_image_url: '',
        pix_expira_em: expira,
        pix_bruto_cents: amountCents,
        updated_at: new Date().toISOString(),
      }).eq('id', pedido_em_aberto_id)

      return j({
        ok: true, modo: 'stub',
        aviso: 'credenciais DeFlow não configuradas — Pix retornado é placeholder',
        pix_id: stubId,
        pix_copia_cola: stubCola,
        pix_qr_image_url: '',
        pix_expira_em: expira,
        valor_bruto: valorBruto,
        valor_liquido: null,
        taxa: null,
      })
    }

    // DeFlow real: UUID v4 determinístico baseado no pedido pra idempotência
    const idempotencyKey = uuidv4FromSeed(pedido.id)
    const body: Record<string, unknown> = {
      amountCents,
      mode: 'exact',  // cliente paga cheio, taxa deduzida do crédito → recebemos líquido
    }
    if (walletId) body.walletId = walletId

    const r = await fetch(`${DEFLOW_BASE}/v1/deposit/create`, {
      method: 'POST',
      headers: {
        'Authorization':         `Bearer ${apiKey}`,
        'X-DF-Secret':           secret,
        'X-DF-Passphrase':       passphrase,
        'X-DF-Idempotency-Key':  idempotencyKey,
        'Content-Type':          'application/json',
      },
      body: JSON.stringify(body),
    })

    if (!r.ok) {
      const errBody = await r.text()
      return j({ error: `DeFlow ${r.status}: ${errBody.slice(0, 500)}` }, 502)
    }

    const resp = await r.json()
    const d = resp.data || resp
    const depositId   = d.id
    const qrCopyPaste = d.qrCopyPaste
    const qrImageUrl  = d.qrImageUrl || ''
    const feeCents    = d.feeCents ?? null
    const netAmountCents = d.netAmountCents ?? null
    const expiresAt   = d.expiresAt || new Date(Date.now() + 24 * 3600 * 1000).toISOString()

    if (!depositId || !qrCopyPaste) {
      return j({ error: 'resposta DeFlow malformada', details: JSON.stringify(d).slice(0, 300) }, 502)
    }

    await supabase.from('pedido_em_aberto').update({
      pix_id: depositId,
      pix_copia_cola: qrCopyPaste,
      pix_qr_image_url: qrImageUrl,
      pix_expira_em: expiresAt,
      pix_bruto_cents: amountCents,
      pix_taxa_cents: feeCents,
      pix_liquido_cents: netAmountCents,
      updated_at: new Date().toISOString(),
    }).eq('id', pedido_em_aberto_id)

    return j({
      ok: true, modo: 'real',
      pix_id: depositId,
      pix_copia_cola: qrCopyPaste,
      pix_qr_image_url: qrImageUrl,
      pix_expira_em: expiresAt,
      valor_bruto: valorBruto,
      valor_liquido: netAmountCents ? netAmountCents / 100 : null,
      taxa: feeCents ? feeCents / 100 : null,
    })

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ error: msg }, 500)
  }
})

// UUID v4 determinístico a partir do pedido_em_aberto_id pra X-DF-Idempotency-Key
// Mesmo pedido tentando gerar Pix de novo (retry) usa MESMO idempotency-key
// e o DeFlow retorna o depósito já criado em vez de duplicar.
function uuidv4FromSeed(seed: string): string {
  // Simple deterministic UUID v4-shaped string from seed
  // Use SHA via TextEncoder + crypto.subtle would be async; doing simple hash
  const hash = simpleHash(seed)
  // Format as UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  const h = (hash + hash + hash).slice(0, 32)
  return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-8${h.slice(17,20)}-${h.slice(20,32)}`
}
function simpleHash(s: string): string {
  let h = 0n
  for (const c of s) h = (h * 31n + BigInt(c.charCodeAt(0))) & 0xffffffffffffffffn
  return h.toString(16).padStart(16, '0').repeat(2)
}

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

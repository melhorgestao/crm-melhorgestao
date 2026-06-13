// ============================================================================
// gerar-pix-deflow
//
// Tool do AGENT_CLOSING. Gera cobrança Pix para um pedido_em_aberto.
//
// MODO ATUAL: STUB (DeFlow ainda não tem API key liberada).
//   - Retorna copia-cola fake e QR code placeholder.
//   - Atualiza pedido_em_aberto.pix_id|pix_qr|pix_copia_cola|pix_expira_em.
//   - Workflow n8n já roda 100% — quando a key DeFlow chegar, só destrava o
//     bloco "DEFLOW_REAL" abaixo (basta setar DEFLOW_API_KEY em configuracoes).
//
// INPUT:  { pedido_em_aberto_id: uuid }
// OUTPUT: { ok, pix_copia_cola, pix_qr_base64, pix_expira_em, valor }
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { pedido_em_aberto_id } = await req.json()
    if (!pedido_em_aberto_id) return j({ error: 'pedido_em_aberto_id obrigatório' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: pedido, error } = await supabase
      .from('pedido_em_aberto')
      .select('id, contato_id, total, status, pix_id, pix_copia_cola, pix_qr_base64, pix_expira_em')
      .eq('id', pedido_em_aberto_id).single()
    if (error || !pedido) return j({ error: 'pedido não encontrado' }, 404)
    if (pedido.status !== 'aguardando_pagamento') {
      return j({ error: `pedido em estado inválido: ${pedido.status}` }, 400)
    }
    if (pedido.pix_copia_cola) {
      // idempotente — devolve o já gerado
      return j({
        ok: true, idempotente: true,
        pix_id: pedido.pix_id,
        pix_copia_cola: pedido.pix_copia_cola,
        pix_qr_base64:  pedido.pix_qr_base64,
        pix_expira_em:  pedido.pix_expira_em,
        valor: Number(pedido.total),
      })
    }

    // Tenta DeFlow se key configurada — senão fica no stub
    const { data: cfg } = await supabase
      .from('configuracoes').select('valor').eq('chave', 'deflow_api_key').maybeSingle()
    const deflowKey = (cfg?.valor as string | undefined)?.trim()

    let pixId: string
    let pixCopiaCola: string
    let pixQrBase64: string
    const expiraEm = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()

    if (deflowKey) {
      // ----------------- DEFLOW_REAL (descomenta quando endpoint estiver pronto) -----------------
      // const r = await fetch('https://api.deflow.exchange/v1/pix/charge', {
      //   method: 'POST',
      //   headers: {
      //     'Authorization': `Bearer ${deflowKey}`,
      //     'Content-Type': 'application/json',
      //   },
      //   body: JSON.stringify({
      //     amount: Number(pedido.total),
      //     description: `Santa Flor — pedido ${pedido.id.slice(0,8)}`,
      //     external_id: pedido.id,
      //     expires_in_seconds: 86400,
      //   }),
      // })
      // if (!r.ok) return j({ error: `DeFlow ${r.status}: ${await r.text()}` }, 502)
      // const d = await r.json()
      // pixId        = d.id
      // pixCopiaCola = d.qr_code || d.copy_paste
      // pixQrBase64  = d.qr_code_base64 || ''
      // -------------------------------------------------------------------------------------------
      return j({ error: 'DeFlow key configurada mas integração real ainda em stub — descomente o bloco DEFLOW_REAL na edge gerar-pix-deflow' }, 501)
    } else {
      // STUB: gera valores fake só pra fluxo rodar ponta a ponta
      pixId        = `STUB-${pedido.id}`
      pixCopiaCola = `00020126360014BR.GOV.BCB.PIX0114STUB${pedido.id.slice(0,8)}520400005303986540${pedido.total.toFixed(2)}5802BR5910SANTA FLOR6009SAO PAULO62070503***6304STUB`
      pixQrBase64  = '' // n8n pode renderizar placeholder
    }

    await supabase
      .from('pedido_em_aberto')
      .update({
        pix_id: pixId,
        pix_copia_cola: pixCopiaCola,
        pix_qr_base64:  pixQrBase64,
        pix_expira_em:  expiraEm,
        updated_at: new Date().toISOString(),
      })
      .eq('id', pedido_em_aberto_id)

    return j({
      ok: true,
      pix_id: pixId,
      pix_copia_cola: pixCopiaCola,
      pix_qr_base64:  pixQrBase64,
      pix_expira_em:  expiraEm,
      valor: Number(pedido.total),
      modo: deflowKey ? 'real' : 'stub',
    })

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ error: msg }, 500)
  }
})

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

// ============================================================================
// router-process — Edge Function que absorve a 2ª metade do Router n8n.
// Chamada APÓS o Wait 12s (debounce) do n8n.
//
// INPUT (POST):
//   {
//     contato_id, instancia_uuid,
//     telefone_clean, instancia_nome,
//     evolution_url, evolution_apikey,
//     recebida_em (ISO da msg que disparou esse processamento)
//   }
//
// FAZ:
//   1) PROCESS BATCH: chama process_batch_mensagens — descobre se essa msg
//      é a "última" do buffer (debounce). Se não for, retorna superseded.
//   2) Decide qual agent chamar (start vs closing) por ultima_interacao
//   3) Chama Edge Function do agent (agent-start ou agent-closing)
//   4) Salva resposta no buffer (out)
//   5) Insert eventos_contato (router_turn)
//
// OUTPUT (200):
//   { ok: bool, deve_enviar: bool, motivo?, resposta_texto?, contato_id, ... }
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const ESTADOS_FECHAMENTO = new Set([
  'em_fechamento', 'aguardando_pagamento', 'cliente_pendente',
])

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const t0 = Date.now()

  try {
    const {
      contato_id, instancia_uuid, recebida_em,
      telefone_clean, instancia_nome, evolution_url, evolution_apikey,
    } = await req.json()

    if (!contato_id) return j({ ok: false, error: 'contato_id obrigatório' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 1) PROCESS BATCH (debounce) — pega mensagens acumuladas no buffer
    const { data: batchData, error: batchErr } = await supabase.rpc('process_batch_mensagens', {
      p_contato_id: contato_id,
      p_minha_recebida_em: recebida_em,
    })
    if (batchErr) return j({ ok: false, error: `process_batch: ${batchErr.message}` }, 500)

    const batch = (batchData as any) || {}
    if (batch.superseded || batch.devo_processar === false) {
      return j({
        ok: true, deve_enviar: false, motivo: 'superseded',
        contato_id, took_ms: Date.now() - t0,
      })
    }

    const mensagens_concat = batch.mensagens_concat || ''
    const count_msgs       = batch.count_msgs || 0

    // 2) Decide qual agent chamar (estado atual do contato)
    const { data: contatoInfo } = await supabase.from('contatos')
      .select('ultima_interacao').eq('id', contato_id).maybeSingle()
    const estado = contatoInfo?.ultima_interacao || ''
    const targetAgent = ESTADOS_FECHAMENTO.has(estado) ? 'agent-closing' : 'agent-start'

    // 3) Chama o agent
    const agentRes = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/${targetAgent}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
      },
      body: JSON.stringify({
        contato_id,
        mensagens: mensagens_concat,
        instancia_id: instancia_uuid,
      }),
    })
    const agentJson = await agentRes.json().catch(() => ({}))
    const resposta_texto = (agentJson?.resposta_texto || '').toString().trim()
    const respostas: Array<{ texto: string; delay_ms?: number }> = Array.isArray(agentJson?.respostas) ? agentJson.respostas : []

    if (!resposta_texto && respostas.length === 0) {
      return j({
        ok: false, deve_enviar: false, motivo: 'agent_sem_resposta',
        agent_called: targetAgent, agent_debug: agentJson?.debug,
        contato_id, took_ms: Date.now() - t0,
      })
    }

    // 4) Envia múltiplas mensagens (com delay) DENTRO da Edge, depois
    // devolve deve_enviar=false pra n8n não duplicar.
    if (respostas.length >= 2) {
      const enviados: any[] = []
      const evoBase = evolution_url.replace(/\/+$/, '')
      for (const r of respostas as Array<any>) {
        const tipo = r.tipo === 'image' ? 'image' : 'text'
        if (r.delay_ms && r.delay_ms > 0) {
          await new Promise(res => setTimeout(res, Math.min(r.delay_ms, 5000)))
        }
        try {
          let sendRes: Response
          let bufMsg = ''
          if (tipo === 'image' && r.url) {
            // Evolution sendMedia
            sendRes = await fetch(`${evoBase}/message/sendMedia/${encodeURIComponent(instancia_nome)}`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'apikey': evolution_apikey },
              body: JSON.stringify({
                number: telefone_clean,
                mediatype: 'image',
                media: r.url,
                caption: r.caption || '',
                fileName: r.fileName || 'foto.jpg',
              }),
            })
            bufMsg = `[image:${r.url}] ${r.caption || ''}`.trim()
          } else {
            const txt = String(r.texto || '').trim()
            if (!txt) continue
            sendRes = await fetch(`${evoBase}/message/sendText/${encodeURIComponent(instancia_nome)}`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'apikey': evolution_apikey },
              body: JSON.stringify({ number: telefone_clean, text: txt }),
            })
            bufMsg = txt
          }
          enviados.push({ tipo, ok: sendRes.ok, status: sendRes.status, len: bufMsg.length })
          // Salva no buffer (out)
          await supabase.from('mensagens_buffer').insert({
            contato_id, telefone: telefone_clean, mensagem: bufMsg,
            tipo, direcao: 'out',
            instancia_id: instancia_uuid,
            processada_em: new Date().toISOString(),
          })
        } catch (e) {
          enviados.push({ tipo, ok: false, error: e instanceof Error ? e.message : String(e) })
        }
      }
      await supabase.from('eventos_contato').insert({
        contato_id, tipo: 'router_turn', canal: instancia_nome,
        instancia_id: instancia_uuid,
        metadata: {
          msg_in: mensagens_concat.slice(0, 500),
          msg_in_count: count_msgs,
          agent_called: targetAgent,
          multi_msg: enviados,
        },
      })
      return j({
        ok: true, deve_enviar: false, motivo: 'enviado_multi',
        contato_id, telefone_clean, instancia_nome,
        agent_called: targetAgent,
        enviados,
        took_ms: Date.now() - t0,
      })
    }

    // 5) Caminho single-message (legado): salva buffer + evento, n8n manda
    await Promise.all([
      supabase.from('mensagens_buffer').insert({
        contato_id,
        telefone: telefone_clean,
        mensagem: resposta_texto,
        tipo: 'text',
        direcao: 'out',
        instancia_id: instancia_uuid,
        processada_em: new Date().toISOString(),
      }),
      supabase.from('eventos_contato').insert({
        contato_id,
        tipo: 'router_turn',
        canal: instancia_nome,
        instancia_id: instancia_uuid,
        metadata: {
          msg_in: mensagens_concat.slice(0, 500),
          msg_in_count: count_msgs,
          msg_out: resposta_texto.slice(0, 200),
          agent_called: targetAgent,
        },
      }),
    ])

    return j({
      ok: true,
      deve_enviar: true,
      resposta_texto,
      contato_id,
      telefone_clean,
      instancia_nome,
      evolution_url,
      evolution_apikey,
      agent_called: targetAgent,
      took_ms: Date.now() - t0,
    })

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ ok: false, error: msg, took_ms: Date.now() - t0 }, 500)
  }
})

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

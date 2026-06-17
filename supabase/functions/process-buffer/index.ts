// ============================================================================
// process-buffer — Edge Function que encapsula o flush do mensagens_buffer.
//
// MODOS:
//
// 1) POST /  (chamada normal pelo router-process)
//    Body: { contato_id, minha_recebida_em }
//    Faz: chama RPC process_batch_mensagens (debounce + agregação atômica)
//    Retorna: { devo_processar, mensagens_concat, count_msgs, superseded }
//
// 2) POST /cron  (safety net — chamado por pg_cron a cada 1 min)
//    Body: { max_idade_seg?: number (default 180) }
//    Faz: varre buffer (in) com mensagens não processadas há mais que N seg
//         e dispara router-process pra cada contato_id pendente.
//    Retorna: { ok, recuperadas, contatos: [...] }
//
// PORQUÊ: o router-process já chama o RPC diretamente, mas centralizar aqui
// permite (a) versionar a lógica de flush em TypeScript, (b) ter um cron de
// safety que recupera mensagens órfãs se algo no n8n cair.
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const url = new URL(req.url)
  const isCron = url.pathname.endsWith('/cron') || url.searchParams.get('mode') === 'cron'

  try {
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {}

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    if (isCron) return await handleCron(supabase, body)
    return await handleFlush(supabase, body)

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ ok: false, error: msg }, 500)
  }
})

// ---- modo flush normal ----------------------------------------------------
async function handleFlush(supabase: any, body: any) {
  const { contato_id, minha_recebida_em } = body

  if (!contato_id) return j({ ok: false, error: 'contato_id obrigatório' }, 400)
  if (!minha_recebida_em) return j({ ok: false, error: 'minha_recebida_em obrigatório' }, 400)

  const { data, error } = await supabase.rpc('process_batch_mensagens', {
    p_contato_id: contato_id,
    p_minha_recebida_em: minha_recebida_em,
  })

  if (error) return j({ ok: false, error: error.message }, 500)

  const batch = (data as any) || {}
  return j({
    ok: true,
    devo_processar:   batch.devo_processar !== false && !batch.superseded,
    superseded:       !!batch.superseded,
    mensagens_concat: batch.mensagens_concat || '',
    count_msgs:       batch.count_msgs || 0,
  })
}

// ---- modo cron (safety net) -----------------------------------------------
async function handleCron(supabase: any, body: any) {
  const max_idade_seg = Math.max(60, Number(body.max_idade_seg || 180))
  const cutoff = new Date(Date.now() - max_idade_seg * 1000).toISOString()

  // Mensagens que entraram, ninguém processou e estão velhas
  const { data: orfas, error } = await supabase
    .from('mensagens_buffer')
    .select('contato_id, recebida_em, instancia_id, telefone')
    .eq('direcao', 'in')
    .is('processada_em', null)
    .lt('recebida_em', cutoff)
    .order('recebida_em', { ascending: true })
    .limit(50)

  if (error) return j({ ok: false, error: error.message }, 500)

  // Agrupa por contato (uma chamada router-process por contato)
  const porContato = new Map<string, any>()
  for (const m of (orfas || [])) {
    if (!porContato.has(m.contato_id)) porContato.set(m.contato_id, m)
  }

  const resultados: any[] = []
  for (const [contato_id, m] of porContato.entries()) {
    // resolve instância pra ter url/apikey
    const { data: inst } = await supabase.from('instancias')
      .select('evolution_url,evolution_apikey,evolution_instance')
      .eq('id', m.instancia_id).maybeSingle()

    if (!inst) { resultados.push({ contato_id, skipped: 'sem_instancia' }); continue }

    try {
      const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/router-process`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
        },
        body: JSON.stringify({
          contato_id,
          instancia_uuid:   m.instancia_id,
          telefone_clean:   m.telefone,
          instancia_nome:   inst.evolution_instance,
          evolution_url:    inst.evolution_url,
          evolution_apikey: inst.evolution_apikey,
          recebida_em:      m.recebida_em,
          origem:           'cron_safety',
        }),
      })
      const rj = await r.json().catch(() => ({}))
      resultados.push({ contato_id, deve_enviar: !!rj.deve_enviar, motivo: rj.motivo })
    } catch (e) {
      resultados.push({ contato_id, error: e instanceof Error ? e.message : String(e) })
    }
  }

  return j({ ok: true, recuperadas: resultados.length, contatos: resultados, cutoff })
}

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

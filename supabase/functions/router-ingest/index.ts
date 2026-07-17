// ============================================================================
// router-ingest — Edge Function que absorve a 1ª metade do Router n8n.
//
// INPUT (POST): body bruto do webhook Evolution
//   { instance, data: { key, message, pushName, ... }, ... }
//
// FAZ:
//   1) Extrai campos (telefone, msg_text, message_type, ctwa, etc)
//   2) Resolve instância pelo nome (tabela instancias)
//   3) Filtros: from_me? tipo aceito (text/audio)? comando "/"?
//   4) GET/CREATE contato (RPC get_or_create_contato)
//   5) Bot ativo? (lê configuracoes.bot_ativo_global)
//   6) Se audioMessage → chama transcrever-audio
//   7) Salva mensagem no buffer (mensagens_buffer direcao=in)
//
// OUTPUT (200) — n8n decide rota com base em deve_processar:
//   {
//     ok: true,
//     deve_processar: bool,
//     motivo?: string,            // razão pra ignorar (from_me, tipo_ignorado, ...)
//     contato_id, instancia_uuid,
//     telefone_clean, instancia_nome,
//     evolution_url, evolution_apikey,
//     recebida_em (ISO)
//   }
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const TIPOS_ACEITOS = new Set([
  'conversation', 'extendedTextMessage', 'audioMessage',
  'deviceSentMessage', 'ephemeralMessage', 'viewOnceMessage',
])
const EVOLUTION_BASE_URL_DEFAULT = 'https://evo.melhorgestao.online'

function unwrapMessage(msg: Record<string, unknown>): Record<string, unknown> {
  const nested = (msg.deviceSentMessage as any)?.message
    || (msg.ephemeralMessage as any)?.message
    || (msg.viewOnceMessage as any)?.message
  return (nested && typeof nested === 'object') ? nested as Record<string, unknown> : msg
}

function extractMsgText(msg: Record<string, unknown>): string {
  const inner = unwrapMessage(msg)
  return String(
    inner.conversation
    || (inner.extendedTextMessage as any)?.text
    || (inner.imageMessage as any)?.caption
    || ''
  )
}

function detectMessageType(msg: Record<string, unknown>): string {
  const inner = unwrapMessage(msg)
  const keys = Object.keys(inner).filter((k) => k !== 'messageContextInfo')
  return keys[0] || 'unknown'
}

function extractContatoId(data: unknown): string | null {
  if (!data || typeof data !== 'object') return null
  if (Array.isArray(data)) return (data[0] as { id?: string })?.id ?? null
  return (data as { id?: string }).id ?? null
}

function isBotPausado(botPausadoAte: string | null | undefined): boolean {
  if (!botPausadoAte) return false
  const t = Date.parse(botPausadoAte)
  return !Number.isNaN(t) && t > Date.now()
}

/** Dígitos locais BR (DDD + número), sem código país 55. */
function normalizeTelefoneBr(raw: string): string {
  let d = String(raw || '').replace(/\D/g, '')
  if ((d.length === 12 || d.length === 13) && d.startsWith('55')) d = d.slice(2)
  return d
}

function extractTelefoneFromEvolution(key: Record<string, unknown> | undefined): string {
  const jid = String(
    key?.remoteJidAlt
    || key?.remoteJid
    || key?.participant
    || ''
  )
  // Ignora LID puro (@lid) quando não há alternativa com telefone real
  if (jid.includes('@lid') && !key?.remoteJidAlt) return ''
  return normalizeTelefoneBr(jid)
}

/** número no formato Evolution: BR nacional (10 díg. fixo, ou 11 com 9 no 3º)
 *  → prefixa 55; estrangeiro (já com DDI) → usa como está. */
function numeroEvolution(telefone: string): string {
  const nd = String(telefone || '').replace(/\D/g, '')
  return (nd.length === 10 || (nd.length === 11 && nd.charAt(2) === '9')) ? '55' + nd : nd
}

/**
 * Dispara a apresentação/cardápio de /start pra um contato:
 *   1) reseta pra 1ª interação (zera avanço/bloqueio de follow-up)
 *   2) chama o edge agent-start (monta os blocos + re-carimba data_start=NOW)
 *   3) envia os blocos via Evolution e loga o evento.
 * Usado tanto pelo comando /start no webhook quanto pelo trigger direto do
 * executa_comando_dono (pg_net).
 */
async function dispararStart(
  supabase: any,
  p: {
    cid: string
    instancia_uuid: string
    instancia_nome: string
    evolution_url: string
    evolution_apikey: string
    telefone_clean: string
    from_me?: boolean
    comando?: string
  },
): Promise<{ enviados: any[]; start_error: string | null }> {
  // volta pra 'start' zerando qualquer avanço/bloqueio de follow-up
  // (o lead pode já ter ido pra wait_follow_up enquanto o chip estava off).
  const { error: resetErr } = await supabase.from('contatos').update({
    ultima_interacao:        'start',
    data_start:              null,
    follow_up_tentativas:    0,
    data_wait_follow_up:     null,
    follow_up_reservado_ate: null,
    followup_bloqueado:      false,
    updated_at:              new Date().toISOString(),
  }).eq('id', p.cid)

  // agent-start monta os blocos da apresentação (mensagens vazias = saudação
  // padrão) e re-carimba data_start=NOW dentro dele.
  let respostas: any[] = []
  let startErr: string | null = null
  try {
    const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/agent-start`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
      },
      body: JSON.stringify({ contato_id: p.cid, mensagens: '', instancia_id: p.instancia_uuid }),
    })
    const rj = await r.json().catch(() => ({}))
    respostas = Array.isArray(rj?.respostas) ? rj.respostas : []
    if (!respostas.length) {
      // devolve o máximo de diagnóstico possível (status HTTP + debug do agent-start)
      const dbg = rj?.debug
        ? ` debug=${JSON.stringify({ ja_comprou: rj.debug.ja_comprou, apresentado_em: rj.debug.apresentado_em, primeira: rj.debug.primeira_interacao_rigida, contato_carregado: rj.debug.contato_carregado })}`
        : ''
      startErr = `agent-start sem blocos (http ${r.status}) erro=${rj?.error || 'nenhum'}` +
        (resetErr ? ` reset_error=${resetErr.message}` : '') + dbg
    }
  } catch (e) {
    startErr = e instanceof Error ? e.message : String(e)
  }

  // envia os blocos via Evolution (mesmo padrão do router-process)
  const number = numeroEvolution(p.telefone_clean)
  const enviados: any[] = []
  const evoBase = (p.evolution_url || EVOLUTION_BASE_URL_DEFAULT).replace(/\/+$/, '')
  for (const rp of respostas) {
    if (rp.delay_ms && rp.delay_ms > 0) {
      await new Promise(res => setTimeout(res, Math.min(rp.delay_ms, 5000)))
    }
    try {
      let sendRes: Response
      let bufMsg = ''
      if (rp.tipo === 'image' && rp.url) {
        sendRes = await fetch(`${evoBase}/message/sendMedia/${encodeURIComponent(p.instancia_nome)}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'apikey': p.evolution_apikey },
          body: JSON.stringify({
            number, mediatype: 'image', media: rp.url,
            caption: rp.caption || '', fileName: rp.fileName || 'foto.jpg', delay: 1200,
          }),
        })
        bufMsg = `[image:${rp.url}] ${rp.caption || ''}`.trim()
      } else {
        const txt = String(rp.texto || '').trim()
        if (!txt) continue
        sendRes = await fetch(`${evoBase}/message/sendText/${encodeURIComponent(p.instancia_nome)}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'apikey': p.evolution_apikey },
          body: JSON.stringify({ number, text: txt, delay: 1200 }),
        })
        bufMsg = txt
      }
      enviados.push({ tipo: rp.tipo, ok: sendRes.ok, status: sendRes.status })
      await supabase.from('mensagens_buffer').insert({
        contato_id: p.cid, telefone: p.telefone_clean, mensagem: bufMsg,
        tipo: rp.tipo === 'image' ? 'image' : 'text', direcao: 'out',
        instancia_id: p.instancia_uuid, processada_em: new Date().toISOString(),
      })
    } catch (e) {
      enviados.push({ tipo: rp.tipo, ok: false, error: e instanceof Error ? e.message : String(e) })
    }
  }

  // OBS: o builder do supabase-js não tem .catch() (só .then) — usar try/await.
  try {
    await supabase.from('eventos_contato').insert({
      contato_id: p.cid, tipo: 'comando_start_manual', canal: p.instancia_nome,
      instancia_id: p.instancia_uuid,
      metadata: { comando: p.comando || '/start', from_me: p.from_me ?? true, enviados, start_error: startErr },
    })
  } catch (_) { /* log é best-effort */ }

  return { enviados, start_error: startErr }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const raw = await req.json()

    // ── Trigger direto (pg_net do executa_comando_dono no comando /start) ────
    // O router n8n ativo trata "/" via executa_comando_dono, que dispara ISSO
    // aqui com os IDs. Resolve telefone/instância e roda a apresentação.
    // body: { trigger:'comando_start', contato_id, instancia_id }
    if (raw?.trigger === 'comando_start' && raw?.contato_id) {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      )
      const cid = String(raw.contato_id)
      const { data: cRow } = await supabase.from('contatos')
        .select('telefone, instancia_id').eq('id', cid).maybeSingle()
      const instId = raw.instancia_id || (cRow as any)?.instancia_id
      if (!(cRow as any)?.telefone || !instId) {
        return j({ ok: false, motivo: 'start_trigger_sem_dados', contato_id: cid })
      }
      const { data: iRow } = await supabase.from('instancias')
        .select('evolution_instance, evolution_url, evolution_apikey').eq('id', instId).maybeSingle()
      if (!(iRow as any)?.evolution_instance) {
        return j({ ok: false, motivo: 'start_trigger_sem_instancia', contato_id: cid })
      }
      const work = dispararStart(supabase, {
        cid,
        instancia_uuid:   instId,
        instancia_nome:   (iRow as any).evolution_instance,
        evolution_url:    (iRow as any).evolution_url || EVOLUTION_BASE_URL_DEFAULT,
        evolution_apikey: (iRow as any).evolution_apikey,
        telefone_clean:   (cRow as any).telefone,
        comando:          '/start',
      }).catch(async (e) => {
        // garante um evento mesmo se algo estourar (observabilidade)
        try {
          await supabase.from('eventos_contato').insert({
            contato_id: cid, tipo: 'comando_start_manual', canal: (iRow as any).evolution_instance,
            instancia_id: instId,
            metadata: { comando: '/start', erro_fatal: e instanceof Error ? e.message : String(e) },
          })
        } catch (_) { /* log é best-effort */ }
        return { enviados: [], start_error: e instanceof Error ? e.message : String(e) }
      })

      // IMPORTANTE: roda em BACKGROUND. O pg_net (quem chama isso) fecha a conexão
      // assim que recebe a resposta; sem waitUntil o runtime mata a função no meio
      // do envio (data_start já carimbado, mas blocos + log não completam). Com
      // waitUntil a função responde rápido e segue viva até terminar tudo.
      const er = (globalThis as any).EdgeRuntime
      if (er?.waitUntil) {
        er.waitUntil(work)
        return j({ ok: true, motivo: 'start_enfileirado', contato_id: cid })
      }
      const res = await work
      return j({ ok: true, motivo: 'start_disparado', contato_id: cid, ...res })
    }

    const ev = raw.body || raw   // n8n às vezes envelopa em body

    // 1) extrai campos
    const instancia_nome = ev.instance || ev.body?.instance || ''
    const telefone_clean = extractTelefoneFromEvolution(ev.data?.key)
    const from_me = !!ev.data?.key?.fromMe
    const msg = ev.data?.message || {}
    const msg_text = extractMsgText(msg)
    const message_type = detectMessageType(msg)
    const push_name = ev.data?.pushName || ''
    const msg_id = ev.data?.key?.id || ''
    const ctwa_source_id  = msg.messageContextInfo?.ctwaContext?.sourceId  || null
    const ctwa_source_url = msg.messageContextInfo?.ctwaContext?.sourceUrl || null

    // 2) filtros baratos antes de bater no banco.
    // ATENÇÃO: comandos "/" são digitados PELO DONO no WhatsApp (fromMe=true,
    // ou pode vir de um chip INTERNO nosso). Deixa passar pra ser tratado no
    // bloco de comando lá embaixo. Filtro de INTERNO acontece após DB lookup.
    const isComando = msg_text.trim().startsWith('/')
    if (from_me && !isComando)                return j({ ok: true, deve_processar: false, motivo: 'from_me' })
    if (!isComando && !TIPOS_ACEITOS.has(message_type)) {
      return j({ ok: true, deve_processar: false, motivo: 'tipo_ignorado', message_type })
    }
    if (!telefone_clean || telefone_clean.length < 10) return j({ ok: true, deve_processar: false, motivo: 'sem_telefone' })
    if (!instancia_nome)                      return j({ ok: true, deve_processar: false, motivo: 'sem_instancia' })

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 3) resolve instância + checa bot global + checa se remetente é INTERNO
    //    (qualquer chip configurado em instancias.numero — todos os "nossos"
    //    números). Mensagem de número INTERNO é ignorada como fromMe.
    const [instRes, botRes, internoRes] = await Promise.all([
      supabase.from('instancias')
        .select('id,evolution_url,evolution_apikey,evolution_instance,status,ativo,pausado_ate,motivo_pausa')
        .eq('evolution_instance', instancia_nome)
        .eq('ativo', true).maybeSingle(),
      supabase.from('configuracoes')
        .select('valor').eq('chave', 'bot_ativo_global').maybeSingle(),
      supabase.from('instancias')
        .select('id,nome').eq('numero', telefone_clean).maybeSingle(),
    ])

    const inst = instRes.data
    if (!inst?.id) return j({ ok: true, deve_processar: false, motivo: 'instancia_nao_encontrada' })
    if (inst.status !== 'ativo') return j({
      ok: true, deve_processar: false,
      motivo: `instancia_${inst.status}`,
      motivo_pausa: inst.motivo_pausa,
      pausado_ate: inst.pausado_ate,
    })

    // Remetente é um dos nossos chips INTERNO → trata como fromMe (ignora,
    // exceto comandos "/"). Útil quando uma instância manda alerta pra outra,
    // ou quando o dono manda msg manual de um chip nosso pra outro.
    if (internoRes.data?.id && !isComando) {
      return j({
        ok: true, deve_processar: false, motivo: 'from_interno',
        from_interno_instancia: internoRes.data.nome,
      })
    }

    const evolution_url    = inst.evolution_url    || EVOLUTION_BASE_URL_DEFAULT
    const evolution_apikey = inst.evolution_apikey
    const instancia_uuid   = inst.id

    // Comandos "/" do dono passam mesmo com o bot globalmente pausado
    // (igual ao fluxo n8n, que trata comando antes da checagem de bot ativo).
    const botAtivo = (botRes.data?.valor ?? 'true') !== 'false'
    if (!botAtivo && !isComando) return j({
      ok: true, deve_processar: false, motivo: 'bot_pausado',
      contato_id: null, instancia_uuid, telefone_clean, instancia_nome,
      evolution_url, evolution_apikey,
    })

    // 4) comando "/" — digitado pelo dono no WhatsApp (fromMe=true).
    //    Executa direto e SAI sem rodar o agente.
    if (isComando) {
      const comando = msg_text.trim().split(/\s+/)[0].toLowerCase()
      const { data: contatoCmd, error: contatoCmdErr } = await supabase.rpc('get_or_create_contato', {
        p_telefone: telefone_clean, p_nome: push_name, p_instancia_id: instancia_uuid,
        p_canal_origem: ctwa_source_id ? 'ADS' : 'BASE',
        p_mensagem: msg_text.replace(/\n/g, ' '),
        p_metadata: { ctwa_source_id, ctwa_source_url },
      })
      const cid = extractContatoId(contatoCmd)
      if (!cid) {
        return j({
          ok: false, deve_processar: false, motivo: 'comando_sem_contato',
          comando, cmd_error: contatoCmdErr?.message || 'contato_id ausente',
          instancia_uuid, telefone_clean, instancia_nome, evolution_url, evolution_apikey,
        }, 500)
      }

      // ── /start ──────────────────────────────────────────────────────────
      // Dono dispara MANUALMENTE a apresentação/cardápio pra um lead que não
      // recebeu (msg do lead não carregou 100%, ou chegou enquanto o chip
      // estava offline/restringido). Reseta pra 1ª interação, chama o
      // agent-start (que devolve os blocos e re-carimba data_start=NOW → o
      // relógio de 24h→follow-up recomeça a partir de AGORA) e envia via
      // Evolution aqui mesmo.
      if (comando === '/start') {
        const res = await dispararStart(supabase, {
          cid,
          instancia_uuid,
          instancia_nome,
          evolution_url,
          evolution_apikey,
          telefone_clean,
          from_me,
          comando,
        })
        return j({
          ok: true, deve_processar: false, motivo: 'start_disparado',
          comando, contato_id: cid, ...res,
          instancia_uuid, telefone_clean, instancia_nome, evolution_url, evolution_apikey,
        })
      }

      const { data: cmdResult, error: cmdErr } = await supabase.rpc('executa_comando_dono', {
        p_contato_id: cid, p_comando: comando,
      })
      // Log evento pra auditoria
      try {
        await supabase.from('eventos_contato').insert({
          contato_id: cid,
          tipo: 'comando_dono',
          canal: instancia_nome,
          instancia_id: instancia_uuid,
          metadata: { comando, from_me, result: cmdResult, error: cmdErr?.message || null },
        })
      } catch (_) { /* log é best-effort */ }
      return j({
        ok: true, deve_processar: false, motivo: 'comando_executado',
        comando, contato_id: cid,
        instancia_uuid, telefone_clean, instancia_nome,
        evolution_url, evolution_apikey,
        cmd_result: cmdResult,
        cmd_error: cmdErr?.message || null,
      })
    }

    // 5) GET/CREATE contato
    const { data: contato, error: cErr } = await supabase.rpc('get_or_create_contato', {
      p_telefone: telefone_clean, p_nome: push_name, p_instancia_id: instancia_uuid,
      p_canal_origem: ctwa_source_id ? 'ADS' : 'BASE',
      p_mensagem: msg_text.replace(/\n/g, ' '),
      p_metadata: { ctwa_source_id, ctwa_source_url },
    })
    if (cErr || !contato) return j({ ok: false, error: cErr?.message || 'get_or_create_contato falhou' }, 500)
    const contato_id = extractContatoId(contato)
    if (!contato_id) return j({ ok: false, error: 'contato sem id' }, 500)
    const bot_pausado_ate = (contato as { bot_pausado_ate?: string | null }).bot_pausado_ate ?? null
    const estado_atual = (contato as { ultima_interacao?: string | null }).ultima_interacao ?? null

    // 6) transcrever áudio se for o caso
    let texto_final = msg_text
    if (message_type === 'audioMessage') {
      try {
        const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/transcrever-audio`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          },
          body: JSON.stringify({ instancia_id: instancia_uuid, msg_id }),
        })
        const tj = await r.json()
        texto_final = (tj?.texto || '').trim() || '[áudio sem texto]'
      } catch {
        texto_final = '[áudio não transcrito]'
      }
    }

    // 7) salva no buffer (in)
    const recebida_em = new Date().toISOString()
    const { error: bufErr } = await supabase.from('mensagens_buffer').insert({
      contato_id, telefone: telefone_clean,
      mensagem: texto_final,
      tipo: message_type === 'audioMessage' ? 'audio' : 'text',
      direcao: 'in',
      instancia_id: instancia_uuid,
      recebida_em,
    })
    if (bufErr) return j({ ok: false, error: bufErr.message }, 500)

    if (isBotPausado(bot_pausado_ate)) {
      return j({
        ok: true,
        deve_processar: false,
        motivo: 'bot_pausado_contato',
        contato_id,
        instancia_uuid,
        telefone_clean,
        instancia_nome,
        evolution_url,
        evolution_apikey,
        recebida_em,
        bot_pausado_ate,
      })
    }

    // Estado suporte = atendimento humano. Msg fica gravada no buffer
    // pra histórico, mas o processamento é pulado até /voltar ou botão.
    if (estado_atual === 'suporte') {
      return j({
        ok: true,
        deve_processar: false,
        motivo: 'em_suporte_humano',
        contato_id,
        instancia_uuid,
        telefone_clean,
        instancia_nome,
        evolution_url,
        evolution_apikey,
        recebida_em,
      })
    }

    return j({
      ok: true,
      deve_processar: true,
      contato_id,
      instancia_uuid,
      telefone_clean,
      instancia_nome,
      evolution_url,
      evolution_apikey,
      recebida_em,
    })

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

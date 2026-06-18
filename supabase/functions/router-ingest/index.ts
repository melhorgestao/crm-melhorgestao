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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const raw = await req.json()
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
    // ATENÇÃO: comandos "/" são digitados PELO DONO no WhatsApp (fromMe=true).
    // Deixa passar pra ser tratado no bloco de comando lá embaixo.
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

    // 3) resolve instância + checa bot global em paralelo
    const [instRes, botRes] = await Promise.all([
      supabase.from('instancias')
        .select('id,evolution_url,evolution_apikey,evolution_instance,status,ativo,pausado_ate,motivo_pausa')
        .eq('evolution_instance', instancia_nome)
        .eq('ativo', true).maybeSingle(),
      supabase.from('configuracoes')
        .select('valor').eq('chave', 'bot_ativo_global').maybeSingle(),
    ])

    const inst = instRes.data
    if (!inst?.id) return j({ ok: true, deve_processar: false, motivo: 'instancia_nao_encontrada' })
    if (inst.status !== 'ativo') return j({
      ok: true, deve_processar: false,
      motivo: `instancia_${inst.status}`,
      motivo_pausa: inst.motivo_pausa,
      pausado_ate: inst.pausado_ate,
    })

    const evolution_url    = inst.evolution_url    || EVOLUTION_BASE_URL_DEFAULT
    const evolution_apikey = inst.evolution_apikey
    const instancia_uuid   = inst.id

    const botAtivo = (botRes.data?.valor ?? 'true') !== 'false'
    if (!botAtivo) return j({
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
      const { data: cmdResult, error: cmdErr } = await supabase.rpc('executa_comando_dono', {
        p_contato_id: cid, p_comando: comando,
      })
      // Log evento pra auditoria
      await supabase.from('eventos_contato').insert({
        contato_id: cid,
        tipo: 'comando_dono',
        canal: instancia_nome,
        instancia_id: instancia_uuid,
        metadata: { comando, from_me, result: cmdResult, error: cmdErr?.message || null },
      }).catch(() => {})
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

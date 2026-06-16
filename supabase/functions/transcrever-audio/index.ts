// ============================================================================
// transcrever-audio — pega áudio do WhatsApp via Evolution API e transcreve
// com OpenAI Whisper.
//
// INPUT:  { instancia_id: uuid, msg_id: string }
// OUTPUT: { ok: true, texto: "...", idioma: "pt", duracao_seg?: number }
//
// Fluxo:
//   1. Lê config da instância (evolution_url, evolution_instance, evolution_apikey)
//   2. Chama Evolution POST /chat/getBase64FromMediaMessage/{instance}
//   3. Decodifica base64 → Blob
//   4. Multipart POST OpenAI /v1/audio/transcriptions (model whisper-1)
//   5. Retorna texto transcrito
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { instancia_id, msg_id } = await req.json()
    if (!instancia_id || !msg_id) {
      return j({ error: 'instancia_id e msg_id são obrigatórios' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 1) Config da instância Evolution
    const { data: inst, error: iErr } = await supabase
      .from('instancias')
      .select('evolution_url, evolution_instance, evolution_apikey')
      .eq('id', instancia_id).single()
    if (iErr || !inst) return j({ error: 'instância não encontrada' }, 404)
    if (!inst.evolution_url || !inst.evolution_instance || !inst.evolution_apikey) {
      return j({ error: 'config Evolution incompleta na instância' }, 400)
    }

    // 2) OpenAI key
    const { data: cfg } = await supabase
      .from('configuracoes').select('valor')
      .eq('chave', 'openai_api_key').maybeSingle()
    const openaiKey = (cfg?.valor as string | undefined)?.trim()
    if (!openaiKey) return j({ error: 'openai_api_key não configurada' }, 400)

    // 3) Baixa áudio da Evolution (base64)
    const evoUrl = `${inst.evolution_url.replace(/\/+$/, '')}/chat/getBase64FromMediaMessage/${encodeURIComponent(inst.evolution_instance)}`
    const evoRes = await fetch(evoUrl, {
      method: 'POST',
      headers: {
        'apikey':       inst.evolution_apikey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: { key: { id: msg_id } },
        convertToMp4: false,
      }),
    })
    if (!evoRes.ok) {
      const t = await evoRes.text()
      return j({ error: `Evolution ${evoRes.status}: ${t.slice(0, 300)}` }, 502)
    }
    const evoJson = await evoRes.json()
    const base64 = evoJson.base64 || evoJson.data?.base64 || evoJson.media || evoJson
    const mimetype = evoJson.mimetype || evoJson.data?.mimetype || 'audio/ogg'
    if (!base64 || typeof base64 !== 'string') {
      return j({ error: 'base64 do áudio ausente na resposta da Evolution',
                 detalhe: JSON.stringify(evoJson).slice(0, 300) }, 502)
    }

    // 4) base64 → Uint8Array
    const audioBytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0))
    const ext = mimetype.includes('mp3') ? 'mp3' :
                mimetype.includes('m4a') ? 'm4a' :
                mimetype.includes('wav') ? 'wav' : 'ogg'

    // 5) POST OpenAI /v1/audio/transcriptions (multipart)
    const form = new FormData()
    form.append('file', new Blob([audioBytes], { type: mimetype }), `audio.${ext}`)
    form.append('model', 'whisper-1')
    form.append('language', 'pt')
    form.append('response_format', 'json')

    const whisperRes = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${openaiKey}` },
      body: form,
    })
    if (!whisperRes.ok) {
      const t = await whisperRes.text()
      return j({ error: `OpenAI Whisper ${whisperRes.status}: ${t.slice(0, 300)}` }, 502)
    }
    const wJson = await whisperRes.json()
    const texto = (wJson.text || '').trim()
    if (!texto) {
      return j({ ok: true, texto: '', vazio: true,
                 aviso: 'transcrição retornou vazia (áudio silencioso?)' })
    }

    return j({
      ok: true,
      texto,
      idioma: 'pt',
      tamanho_bytes: audioBytes.length,
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

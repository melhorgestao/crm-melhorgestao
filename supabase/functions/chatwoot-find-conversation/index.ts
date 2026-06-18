// ============================================================================
// chatwoot-find-conversation — proxy server-side pro Chatwoot.
//
// Existe porque o Chatwoot self-hosted não retorna Access-Control-Allow-Origin
// → frontend não consegue chamar direto. Edge Function chama no servidor
// (sem CORS) e devolve { url, conversation_id, inbox_id }.
//
// INPUT (POST):
//   { telefone: string }
//
// OUTPUT (200):
//   { ok: true, url, conversation_id, inbox_id, contact_id }
//   ou
//   { ok: false, error, debug: { tentativas: [...] } }
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const debug: any = { tentativas: [] }

  try {
    const { telefone } = await req.json()
    if (!telefone) return j({ ok: false, error: 'telefone obrigatório' }, 400)

    const tel = String(telefone).replace(/\D/g, '')
    if (!tel) return j({ ok: false, error: 'telefone vazio' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 1) Lê config Chatwoot do banco
    const { data: cfgRows } = await supabase
      .from('configuracoes').select('chave,valor')
      .in('chave', ['chatwoot_url', 'chatwoot_account_id', 'chatwoot_api_token'])
    const cfg: Record<string, string> = Object.fromEntries((cfgRows || []).map((c: any) => [c.chave, c.valor]))

    const baseUrl   = (cfg.chatwoot_url || '').replace(/\/$/, '')
    const accountId = cfg.chatwoot_account_id
    const apiToken  = cfg.chatwoot_api_token

    if (!baseUrl || !accountId || !apiToken) {
      return j({ ok: false, error: 'config Chatwoot incompleta em configuracoes' }, 400)
    }

    // 2) Tenta variantes do telefone
    const variants = Array.from(new Set([
      `+${tel}`,
      tel,
      tel.startsWith('55') ? tel.slice(2) : null,
      tel.length >= 10 ? tel.slice(-11) : null,
      tel.length >= 10 ? tel.slice(-10) : null,
    ].filter(Boolean) as string[]))

    debug.variants = variants

    for (const q of variants) {
      const searchUrl = `${baseUrl}/api/v1/accounts/${accountId}/contacts/search?q=${encodeURIComponent(q)}&include=contact_inboxes`
      const r = await fetch(searchUrl, {
        headers: { 'Content-Type': 'application/json', 'api_access_token': apiToken },
      })
      const txt = await r.text()
      let body: any = null
      try { body = JSON.parse(txt) } catch {}
      const payload = body?.payload || []
      debug.tentativas.push({ q, status: r.status, matches: payload.length })

      for (const c of payload) {
        // Lista conversas desse contato
        const convUrl = `${baseUrl}/api/v1/accounts/${accountId}/contacts/${c.id}/conversations`
        const cr = await fetch(convUrl, {
          headers: { 'Content-Type': 'application/json', 'api_access_token': apiToken },
        })
        const cjTxt = await cr.text()
        let cj: any = null
        try { cj = JSON.parse(cjTxt) } catch {}
        const convs = cj?.payload || []
        debug.tentativas.push({ contact_id: c.id, contact_name: c.name, conversations: convs.length })

        if (convs.length > 0) {
          // Prioriza ABERTA, senão a 1ª
          const open = convs.find((x: any) => x.status === 'open') || convs[0]
          const url = `${baseUrl}/app/accounts/${accountId}/inbox/${open.inbox_id}/conversations/${open.id}`
          return j({
            ok: true,
            url,
            conversation_id: open.id,
            inbox_id: open.inbox_id,
            contact_id: c.id,
            contact_name: c.name,
            status: open.status,
            debug,
          })
        }
      }
    }

    // Não achou — fallback URL pro dashboard com filtro
    const fallback = `${baseUrl}/app/accounts/${accountId}/conversations?contact_phone=${encodeURIComponent('+' + tel)}`
    return j({ ok: false, error: 'conversa não encontrada', url: fallback, debug })

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ ok: false, error: msg, debug }, 500)
  }
})

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

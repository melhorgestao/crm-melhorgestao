// ============================================================================
// agent-closing — Edge Function que substitui o workflow n8n AGENT_CLOSING.
//
// INPUT (POST):
//   { contato_id: uuid, mensagens: string, instancia_id: uuid }
//
// OUTPUT (200):
//   { resposta_texto: string, contato_id: uuid, debug?: {...} }
//
// FLUXO:
//   1) Carrega contato (com endereço), pendência, catálogo ativo
//   2) Monta system prompt de fechamento (state machine, bônus, parcelamento)
//   3) Chama OpenRouter com tool calling (loop até output final)
//   4) Retorna texto pro Router enviar via Evolution
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { buildClosingPrompt, type ContatoClosing, type ProdutoCat } from './prompt.ts'
import { CLOSING_TOOL_SCHEMAS, executeClosingTool } from './tools.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const OPENROUTER_MODEL = 'meta-llama/llama-3.3-70b-instruct'
const MAX_TOOL_ITERATIONS = 8
const LLM_TIMEOUT_MS = 50000

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const t0 = Date.now()
  const debug: Record<string, any> = {}

  try {
    const body = await req.json()
    const { contato_id, mensagens = '', instancia_id = null } = body

    if (!contato_id) return j({ error: 'contato_id obrigatório' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 1) chave OpenRouter
    const { data: cfg } = await supabase
      .from('configuracoes')
      .select('valor')
      .eq('chave', 'openrouter_api_key')
      .maybeSingle()
    const openrouterKey = (cfg?.valor as string | undefined)?.trim()
    if (!openrouterKey) {
      return j({ error: 'openrouter_api_key não configurada em configuracoes' }, 500)
    }

    // 2) carrega contexto em paralelo
    const [contatoRes, pendenciaRes, catalogoRes] = await Promise.all([
      supabase.from('contatos')
        .select('id,nome,ja_comprou,cidade,uf,ultima_interacao,instancia_id,cep,rua,numero,complemento,bairro')
        .eq('id', contato_id).maybeSingle(),
      supabase.rpc('consultar_pendencia_contato', { p_contato_id: contato_id }).maybeSingle(),
      supabase.from('produtos')
        .select('tag,nome_oficial,preco,emoji')
        .eq('ativo', true)
        .order('preco', { ascending: true }),
    ])

    const contato: ContatoClosing = (contatoRes.data ?? {}) as ContatoClosing
    const pendencia = pendenciaRes.data ?? {}
    const catalogo: ProdutoCat[] = (catalogoRes.data ?? []) as ProdutoCat[]

    const instanciaIdResolvido = instancia_id || (contato as any).instancia_id || null

    debug.contato_carregado = !!contato.id
    debug.tem_endereco = !!(contato.cep && contato.rua && contato.numero)
    debug.tem_pendencia = !!(pendencia as any)?.tem_pendencia
    debug.catalogo_itens = catalogo.length

    // 3) prompts
    const systemPrompt = buildClosingPrompt({
      contato, pendencia, catalogo,
      contato_id, instancia_id: instanciaIdResolvido,
    })
    const userMessage = `Mensagens recentes do cliente:\n${mensagens || '(vazio)'}`

    const messages: any[] = [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: userMessage },
    ]

    // 4) loop de tool calling
    let resposta = ''
    let iter = 0
    const toolsUsed: string[] = []

    while (iter < MAX_TOOL_ITERATIONS) {
      iter++
      const llmRes = await callOpenRouter(openrouterKey, messages, CLOSING_TOOL_SCHEMAS)
      const choice = llmRes?.choices?.[0]
      const msg = choice?.message
      if (!msg) {
        debug.no_message = true
        debug.llm_raw = JSON.stringify(llmRes).slice(0, 400)
        break
      }

      const toolCalls = msg.tool_calls
      if (toolCalls && toolCalls.length > 0) {
        messages.push(msg)
        for (const tc of toolCalls) {
          const name = tc.function?.name
          let args: any = {}
          try { args = JSON.parse(tc.function?.arguments || '{}') } catch {}
          toolsUsed.push(name)
          const toolResult = await executeClosingTool({
            name, args, contato_id, instancia_id: instanciaIdResolvido, supabase,
          })
          messages.push({
            role: 'tool',
            tool_call_id: tc.id,
            name,
            content: typeof toolResult === 'string' ? toolResult : JSON.stringify(toolResult),
          })
        }
        continue
      }

      resposta = (msg.content || '').toString().trim()
      break
    }

    if (!resposta) {
      resposta = 'Deu uma instabilidade aqui no fechamento, pode repetir sua última mensagem? 🙏'
      debug.fallback_used = true
    }

    debug.iterations = iter
    debug.tools_used = toolsUsed
    debug.took_ms = Date.now() - t0

    return j({ resposta_texto: resposta, contato_id, debug })

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    debug.took_ms = Date.now() - t0
    return j({
      resposta_texto: 'Deu uma instabilidade aqui no fechamento, pode repetir sua última mensagem? 🙏',
      contato_id: null,
      error: msg,
      debug,
    }, 200)
  }
})

async function callOpenRouter(key: string, messages: any[], tools: any[]) {
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), LLM_TIMEOUT_MS)
  try {
    const r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type':   'application/json',
        'Authorization':  `Bearer ${key}`,
        'HTTP-Referer':   'https://melhorgestao.online',
        'X-Title':        'Santa Flor CRM',
      },
      body: JSON.stringify({
        model: OPENROUTER_MODEL,
        messages,
        tools,
        tool_choice: 'auto',
        temperature: 0.3,
        max_tokens: 900,
      }),
      signal: ctrl.signal,
    })
    const txt = await r.text()
    try { return JSON.parse(txt) }
    catch { return { error: 'parse', body_preview: txt.slice(0, 400), status: r.status } }
  } finally { clearTimeout(timer) }
}

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

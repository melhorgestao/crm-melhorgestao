// ============================================================================
// agent-start — Edge Function que substitui o workflow n8n AGENT_START.
//
// INPUT (POST):
//   { contato_id: uuid, mensagens: string, instancia_id: uuid }
//
// OUTPUT (200):
//   { resposta_texto: string, contato_id: uuid, debug?: {...} }
//
// FLUXO:
//   1) Carrega contexto: contato + últimos pedidos + pendência
//   2) Monta system prompt (calorosa, regras de venda, triagens, cardápio se 1ª)
//   3) Chama OpenRouter (Llama 3.3 70B) com tool calling
//   4) Loop: enquanto LLM pedir tools, executa e devolve resultado
//   5) Retorna texto final pro Router n8n enviar via Evolution
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { buildSystemPrompt, type Contato } from './prompt.ts'
import { TOOL_SCHEMAS, executeTool } from './tools.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const OPENROUTER_MODEL = 'openai/gpt-4o-mini'
const MAX_TOOL_ITERATIONS = 5
const LLM_TIMEOUT_MS = 45000

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

    // 1) chave do OpenRouter
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
    const [contatoRes, pedidosRes, pendenciaRes] = await Promise.all([
      supabase.from('contatos')
        .select('id,nome,ja_comprou,cidade,uf,ultima_interacao,canal_atual')
        .eq('id', contato_id).maybeSingle(),
      supabase.rpc('consultar_pedidos_contato', { p_contato_id: contato_id }),
      supabase.rpc('consultar_pendencia_contato', { p_contato_id: contato_id }).maybeSingle(),
    ])

    const contato: Contato = (contatoRes.data ?? {}) as Contato
    const pedidos = Array.isArray(pedidosRes.data) ? pedidosRes.data : []
    const pendencia = pendenciaRes.data ?? {}

    debug.contato_carregado = !!contato.id
    debug.qtd_pedidos = pedidos.length
    debug.tem_pendencia = !!(pendencia as any)?.tem_pendencia

    // 3) prompts
    const systemPrompt = buildSystemPrompt({ contato, pedidos, pendencia })
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
      const llmRes = await callOpenRouter(openrouterKey, messages, TOOL_SCHEMAS)
      const choice = llmRes?.choices?.[0]
      const msg = choice?.message

      if (!msg) {
        debug.no_message = true
        debug.llm_raw = JSON.stringify(llmRes).slice(0, 400)
        break
      }

      // se tem tool_calls, executa cada uma
      const toolCalls = msg.tool_calls
      if (toolCalls && toolCalls.length > 0) {
        // adiciona a msg do assistant antes das responses
        messages.push(msg)

        for (const tc of toolCalls) {
          const name = tc.function?.name
          let args: any = {}
          try { args = JSON.parse(tc.function?.arguments || '{}') } catch {}
          toolsUsed.push(name)
          const toolResult = await executeTool({
            name, args, contato_id, instancia_id, supabase, openrouterKey
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

      // resposta final em texto
      resposta = (msg.content || '').toString().trim()
      break
    }

    if (!resposta) {
      resposta = 'Oi! Tô com uma instabilidade aqui, pode repetir sua mensagem? 🙏'
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
      resposta_texto: 'Oi! Tô com uma instabilidade aqui, pode repetir sua mensagem? 🙏',
      contato_id: null,
      error: msg,
      debug,
    }, 200) // 200 pra n8n não ficar perdido
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
        temperature: 0.4,
        max_tokens: 800,
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

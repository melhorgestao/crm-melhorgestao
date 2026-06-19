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
    const [contatoRes, pedidosRes, pendenciaRes, msgOutRes, historyRes, catalogoRes, cupomRes, configRes] = await Promise.all([
      supabase.from('contatos')
        .select('id,nome,ja_comprou,cidade,uf,ultima_interacao,canal_atual,fotos_enviadas,apresentacao_enviada_em')
        .eq('id', contato_id).maybeSingle(),
      supabase.rpc('consultar_pedidos_contato', { p_contato_id: contato_id }),
      supabase.rpc('consultar_pendencia_contato', { p_contato_id: contato_id }).maybeSingle(),
      supabase.from('mensagens_buffer')
        .select('id', { count: 'exact', head: true })
        .eq('contato_id', contato_id).eq('direcao', 'out'),
      supabase.from('mensagens_buffer')
        .select('direcao,mensagem,recebida_em,processada_em')
        .eq('contato_id', contato_id)
        .order('recebida_em', { ascending: false }).limit(20),
      supabase.from('produtos')
        .select('tag,nome_oficial,preco,emoji')
        .eq('ativo', true)
        .order('preco', { ascending: true }),
      supabase.rpc('cupom_para_contato', { p_contato_id: contato_id }),
      supabase.rpc('get_agent_config', { p_agent: 'start' }),
    ])

    const contato: Contato = (contatoRes.data ?? {}) as Contato
    const fotosEnviadas: string[] = Array.isArray((contato as any).fotos_enviadas) ? (contato as any).fotos_enviadas : []
    const pedidos = Array.isArray(pedidosRes.data) ? pedidosRes.data : []
    const pendencia = pendenciaRes.data ?? {}
    const msgsOutCount = msgOutRes.count ?? 0
    const history = (historyRes.data ?? []).slice().reverse()
    const catalogo = (catalogoRes.data ?? []) as Array<{ tag?: string; nome_oficial?: string; preco?: number; emoji?: string }>
    const cupom = cupomRes.data as { nome: string; desconto_pct: number; expira_em?: string | null } | null
    const config = (configRes.data ?? {}) as Record<string, any>

    debug.contato_carregado = !!contato.id
    debug.qtd_pedidos = pedidos.length
    debug.tem_pendencia = !!(pendencia as any)?.tem_pendencia
    debug.msgs_out_count = msgsOutCount
    debug.history_len = history.length
    debug.catalogo_itens = catalogo.length
    debug.cupom_disponivel = cupom ? { nome: cupom.nome, pct: cupom.desconto_pct } : null

    // Detecta se 1ª mensagem é SAUDAÇÃO PURA ou PERGUNTA DIRETA.
    // Saudação pura → usa template configurado.
    // Pergunta direta → agent responde a pergunta no bloco 3 (sem saudação).
    const msgLower = String(mensagens || '').toLowerCase().trim()
    const ehSaudacaoPura = (() => {
      if (!msgLower) return true
      // tem ? → pergunta, exceto se for "tudo bem?" / "esta aberto?" etc
      if (msgLower.includes('?')) {
        return /(tudo bem|tudo certo|tem alguem|tem alguém|esta aberto|está aberto|esta ai|tá ai|ta ai)/i.test(msgLower)
      }
      // sem ? → saudação se curta (≤ 6 palavras)
      return msgLower.split(/\s+/).length <= 6
    })()

    // Resolve saudação pelo canal (com fallback BASE)
    function resolverSaudacao(): string {
      const canal = (contato.canal_atual || contato.canal_origem || 'BASE').toUpperCase()
      const saldo = Number((pendencia as any)?.saldo_devedor_total || 0)
      const nome = (contato.nome || '').split(' ')[0] || 'amigo(a)'
      let tpl: string
      if (contato.ja_comprou) {
        tpl = config.saudacao_cliente || 'Oi, {nome}! Em que posso te ajudar?'
      } else if (canal === 'ADS') {
        tpl = config.saudacao_ads  || config.saudacao_base || 'Como posso ajudar, {nome}?'
      } else if (canal === 'REP') {
        tpl = config.saudacao_rep  || config.saudacao_base || 'Salve, {nome}!'
      } else {
        tpl = config.saudacao_base || 'Como posso ajudar, {nome}?'
      }
      return String(tpl)
        .replace(/\{nome\}/g,  nome)
        .replace(/\{saldo\}/g, saldo.toFixed(2).replace('.', ','))
    }
    const saudacaoResolvida = resolverSaudacao()
    debug.eh_saudacao_pura = ehSaudacaoPura
    debug.saudacao_canal = (contato.canal_atual || contato.canal_origem || 'BASE')

    // 3) prompts
    // Regra: SÓ é primeira interação se NÃO é cliente.
    // Reapresentação opcional: se reapresentar_meses != null E apresentação foi
    // enviada há mais que X meses E contato NÃO é cliente → considera primeira de novo.
    const apresentadoEm = (contato as any).apresentacao_enviada_em
      ? new Date((contato as any).apresentacao_enviada_em)
      : null
    const reapresentarMeses: number | null = typeof config.reapresentar_meses === 'number'
      ? config.reapresentar_meses : null
    const passouTempoReapresentar = !!(apresentadoEm && reapresentarMeses && reapresentarMeses > 0
      && (Date.now() - apresentadoEm.getTime()) > (reapresentarMeses * 30 * 24 * 3600 * 1000))
    const isPrimeiraInteracao = !contato.ja_comprou && (
      !apresentadoEm || passouTempoReapresentar
    )
    debug.apresentado_em = apresentadoEm?.toISOString()
    debug.reapresentar_meses = reapresentarMeses
    debug.reapresentou_por_tempo = passouTempoReapresentar
    debug.ja_comprou = !!contato.ja_comprou
    const systemPrompt = buildSystemPrompt({
      contato, pedidos, pendencia, isPrimeiraInteracao, catalogo, cupom,
      config, ehSaudacaoPura, saudacaoResolvida,
    })
    const userMessage = `Mensagem nova do cliente:\n${mensagens || '(vazio)'}`

    // Constrói messages com history real
    const messages: any[] = [{ role: 'system', content: systemPrompt }]
    for (const h of history) {
      const role = h.direcao === 'in' ? 'user' : 'assistant'
      const content = String(h.mensagem || '').trim()
      if (content) messages.push({ role, content })
    }
    messages.push({ role: 'user', content: userMessage })

    // 4) loop de tool calling
    let resposta = ''
    let iter = 0
    let chainToClosing = false
    const toolsUsed: string[] = []
    const fotosNovas: Array<{ url: string; caption?: string; tag: string }> = []

    while (iter < MAX_TOOL_ITERATIONS) {
      iter++
      const llmRes = await callOpenRouter(openrouterKey, messages, TOOL_SCHEMAS,
        typeof config.llm_temperature === 'number' ? config.llm_temperature : undefined)
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
          const toolResult = await executeTool({
            name, args, contato_id, instancia_id, supabase, openrouterKey,
            fotosEnviadas,
          })
          if (name === 'iniciar_fechamento' && (toolResult as any)?.ok) chainToClosing = true
          if (name === 'enviar_foto_produto' && (toolResult as any)?.send) {
            fotosNovas.push({
              url:     (toolResult as any).url,
              caption: (toolResult as any).caption,
              tag:     (toolResult as any).foto_tag,
            })
            fotosEnviadas.push((toolResult as any).foto_tag)
          }
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

    // 4.5) Chain pra closing: se chamou iniciar_fechamento, agente de fechamento
    // ASSUME a conversa imediatamente — pede CEP/itens sem esperar nova mensagem.
    if (chainToClosing) {
      debug.chained_to_closing = true
      try {
        const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/agent-closing`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          },
          body: JSON.stringify({
            contato_id,
            mensagens: mensagens || '[entrou em fechamento]',
            instancia_id,
            entrou_agora: true,
          }),
        })
        const cj = await r.json().catch(() => ({}))
        const closingTxt = (cj?.resposta_texto || '').toString().trim()
        if (closingTxt) resposta = closingTxt
        debug.closing_debug = cj?.debug
      } catch (e) {
        debug.chain_error = e instanceof Error ? e.message : String(e)
      }
    }

    if (!resposta) {
      resposta = 'Oi! Tô com uma instabilidade aqui, pode repetir sua mensagem?'
      debug.fallback_used = true
    }

    debug.iterations = iter
    debug.tools_used = toolsUsed
    debug.took_ms = Date.now() - t0

    const SUPABASE_PUBLIC = (Deno.env.get('SUPABASE_URL') || '').replace(/\/+$/, '')
    const TABELA_URL = String(
      config.foto_apresentacao_url
      || `${SUPABASE_PUBLIC}/storage/v1/object/public/Start/TabelaOficial.png`
    )

    // Se é PRIMEIRA INTERAÇÃO: quebra em 3 mensagens com foto TabelaOficial
    // como bloco 2 (caption = cardápio+bônus).
    if (isPrimeiraInteracao && !chainToClosing) {
      const blocos = splitWelcomeIntoBlocks(resposta)
      if (blocos.length >= 2) {
        const out: any[] = [{ tipo: 'text', texto: blocos[0].texto, delay_ms: 0 }]
        if (blocos.length >= 3) {
          // bloco do meio vira foto da tabela com o cardápio como caption
          out.push({
            tipo: 'image', url: TABELA_URL,
            caption: blocos[1].texto,
            fileName: 'tabela-oficial.png',
            delay_ms: 2000,
          })
          out.push({ tipo: 'text', texto: blocos[2].texto, delay_ms: 2000 })
        } else {
          out.push({ tipo: 'text', texto: blocos[1].texto, delay_ms: 2000 })
        }
        // Marca TabelaOficial + apresentacao_enviada_em
        if (!fotosEnviadas.includes('tabela_oficial')) fotosEnviadas.push('tabela_oficial')
        await supabase.from('contatos').update({
          fotos_enviadas: fotosEnviadas,
          apresentacao_enviada_em: new Date().toISOString(),
        }).eq('id', contato_id)
        debug.split_in_blocks = out.length
        debug.tabela_oficial_enviada = true
        debug.apresentacao_marcada = true
        return j({ resposta_texto: out[0].texto, respostas: out, contato_id, debug })
      }
    }

    // Caminho com fotos NOVAS solicitadas via tool enviar_foto_produto
    if (fotosNovas.length > 0) {
      const out: any[] = [{ tipo: 'text', texto: resposta, delay_ms: 0 }]
      for (const f of fotosNovas) {
        out.push({
          tipo: 'image', url: f.url, caption: f.caption || '',
          fileName: `${f.tag}.jpg`, delay_ms: 1500,
        })
      }
      await supabase.from('contatos').update({ fotos_enviadas: fotosEnviadas }).eq('id', contato_id)
      debug.fotos_enviadas_novas = fotosNovas.map(f => f.tag)
      return j({ resposta_texto: resposta, respostas: out, contato_id, debug })
    }

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

async function callOpenRouter(key: string, messages: any[], tools: any[], tempOverride?: number) {
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
        temperature: typeof tempOverride === 'number' ? tempOverride : 0.4,
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

// Quebra o welcome em 3 blocos. Marcadores no prompt: "📋 *Nosso cardápio:*"
// inicia o bloco 2; "Como posso te ajudar" inicia o bloco 3.
function splitWelcomeIntoBlocks(texto: string): Array<{ texto: string; delay_ms: number }> {
  const t = String(texto || '').trim()
  if (!t) return []

  const idxCardapio = t.search(/📋\s*\*?Nosso\s*card[áa]pio/i)
  const idxAjuda    = t.search(/Como\s+posso\s+te?\s*ajudar/i)

  const blocos: Array<{ texto: string; delay_ms: number }> = []

  // Bloco 1: do início até o cardápio
  const fimBloco1 = idxCardapio > 0 ? idxCardapio : (idxAjuda > 0 ? idxAjuda : t.length)
  const bloco1 = t.slice(0, fimBloco1).trim()
  if (bloco1) blocos.push({ texto: bloco1, delay_ms: 0 })

  // Bloco 2: cardápio até pergunta
  if (idxCardapio > 0) {
    const fimBloco2 = idxAjuda > idxCardapio ? idxAjuda : t.length
    const bloco2 = t.slice(idxCardapio, fimBloco2).trim()
    if (bloco2) blocos.push({ texto: bloco2, delay_ms: 2000 })
  }

  // Bloco 3: pergunta final
  if (idxAjuda > 0) {
    const bloco3 = t.slice(idxAjuda).trim()
    if (bloco3) blocos.push({ texto: bloco3, delay_ms: 2000 })
  }

  // Se só achou 1 bloco, devolve vazio (deixa fluxo single-msg)
  return blocos.length >= 2 ? blocos : []
}

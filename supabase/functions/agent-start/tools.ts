// ============================================================================
// agent-start / tools.ts — schemas (formato OpenAI/OpenRouter) + executor.
//
// Tools são funções TS comuns. Cada uma:
//  - tem schema JSON pro LLM
//  - executa via RPC do Supabase ou chamada interna
//  - retorna JSON (vira tool message no histórico do LLM)
// ============================================================================

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface ToolCtx {
  name: string
  args: Record<string, any>
  contato_id: string
  instancia_id?: string | null
  supabase: SupabaseClient
  openrouterKey: string
  fotosEnviadas?: string[]
}

// Mapa produto → arquivo no bucket "Start"
const FOTO_MAP: Record<string, { tag: string; arquivo: string }> = {
  cbd:        { tag: 'cbd',        arquivo: 'Cbd.jpg' },
  verde:      { tag: 'cbd',        arquivo: 'Cbd.jpg' },
  'cbd 4000': { tag: 'cbd',        arquivo: 'Cbd.jpg' },
  amarelo:    { tag: 'full6k',     arquivo: 'Full6k.jpg' },
  full6k:     { tag: 'full6k',     arquivo: 'Full6k.jpg' },
  '6000':     { tag: 'full6k',     arquivo: 'Full6k.jpg' },
  vermelho:   { tag: 'full10k',    arquivo: 'Full10k.jpg' },
  full10k:    { tag: 'full10k',    arquivo: 'Full10k.jpg' },
  '10000':    { tag: 'full10k',    arquivo: 'Full10k.jpg' },
  gummy:      { tag: 'gummy',      arquivo: 'Gummy.jpg' },
  bear:       { tag: 'gummy',      arquivo: 'Gummy.jpg' },
  pomada:     { tag: 'cannaderm',  arquivo: 'Cannaderm.jpg' },
  cannaderm:  { tag: 'cannaderm',  arquivo: 'Cannaderm.jpg' },
  lub:        { tag: 'lub',        arquivo: 'Lub.jpg' },
  lubrificante: { tag: 'lub',      arquivo: 'Lub.jpg' },
  intimo:     { tag: 'lub',        arquivo: 'Lub.jpg' },
}

// ---- SCHEMAS pro OpenRouter (formato OpenAI tools v1) ----------------------
export const TOOL_SCHEMAS = [
  {
    type: 'function',
    function: {
      name: 'buscar_conhecimento',
      description: 'Busca informações sobre PRODUTOS, PREÇOS, BÔNUS, ARGUMENTOS DE VENDA, FAQs (interações medicamentosas, golpes, efeitos colaterais). Use SEMPRE que o cliente perguntar sobre esses temas.',
      parameters: {
        type: 'object',
        properties: {
          pergunta: { type: 'string', description: 'Pergunta do cliente em linguagem natural.' },
        },
        required: ['pergunta'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'consultar_pedido',
      description: 'Retorna últimos 5 pedidos do cliente (data, produto, valor, status, rastreio). Use quando cliente perguntar histórico, valores ou status de pagamento.',
      parameters: { type: 'object', properties: {}, required: [] },
    },
  },
  {
    type: 'function',
    function: {
      name: 'consultar_rastreio',
      description: 'Retorna dados de rastreio dos últimos pedidos (link, código, status de postagem). Use quando perguntar "onde tá meu pedido", "quando chega".',
      parameters: { type: 'object', properties: {}, required: [] },
    },
  },
  {
    type: 'function',
    function: {
      name: 'consultar_cep',
      description: 'Calcula preço e prazo de frete via Superfrete pra um CEP. Use quando cliente perguntar "quanto fica o frete" ou "prazo de entrega". Se não passou CEP, peça primeiro.',
      parameters: {
        type: 'object',
        properties: {
          to_cep:       { type: 'string', description: 'CEP de destino (8 dígitos).' },
          qtd_produtos: { type: 'number', description: 'Quantidade de produtos. Default 1.' },
        },
        required: ['to_cep'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'escalar_suporte',
      description: 'Encaminha o contato pro Kanban Suporte (atendimento humano). Use APENAS se cliente pedir atendente, dúvida que não consegue responder, ou loop de incompreensão.',
      parameters: {
        type: 'object',
        properties: {
          motivo: { type: 'string', description: 'Motivo curto da escalação em português.' },
        },
        required: ['motivo'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'enviar_foto_produto',
      description: 'Envia foto do produto. Use UMA ÚNICA VEZ por conversa quando cliente perguntar/demonstrar interesse específico em um produto. Não use pra produtos já mencionados de passagem; só quando há foco explícito. Aceita keyword: cbd | verde | amarelo | full6k | vermelho | full10k | gummy | pomada | cannaderm | lub. Se já foi enviada antes, retorna already_sent=true e nada acontece — não tente outra vez.',
      parameters: {
        type: 'object',
        properties: {
          produto: { type: 'string', description: 'Keyword do produto.' },
        },
        required: ['produto'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'iniciar_fechamento',
      description: 'Marca contato como em_fechamento. Router encaminha a PRÓXIMA msg do cliente pro AGENT_CLOSING. Use quando cliente expressa intenção CLARA de comprar ("quero", "manda", "vou levar").',
      parameters: {
        type: 'object',
        properties: {
          produto_pretendido: { type: 'string', description: 'Opcional: descrição curta do que cliente quer. Ex: "2 amarelo".' },
        },
        required: [],
      },
    },
  },
]

// ---- EXECUTOR --------------------------------------------------------------
export async function executeTool(ctx: ToolCtx): Promise<any> {
  const { name, args, contato_id, supabase, openrouterKey, fotosEnviadas = [] } = ctx

  try {
    switch (name) {

      case 'buscar_conhecimento': {
        if (!args.pergunta) return { error: 'pergunta obrigatória' }
        // Chama buscar-conhecimento-agent que já existe
        const r = await invokeFunction(supabase, 'buscar-conhecimento-agent', {
          pergunta: args.pergunta, limit: 5
        })
        return { chunks: r?.chunks ?? [] }
      }

      case 'consultar_pedido': {
        const { data, error } = await supabase.rpc('consultar_pedidos_contato', {
          p_contato_id: contato_id,
        })
        if (error) return { error: error.message }
        return { pedidos: data ?? [] }
      }

      case 'consultar_rastreio': {
        const { data, error } = await supabase.rpc('consultar_rastreio_contato', {
          p_contato_id: contato_id,
        })
        if (error) return { error: error.message }
        return { rastreios: data ?? [] }
      }

      case 'consultar_cep': {
        if (!args.to_cep) return { error: 'to_cep obrigatório' }
        const r = await invokeFunction(supabase, 'consultar-frete-agent', {
          to_cep: args.to_cep,
          qtd_produtos: args.qtd_produtos || 1,
        })
        return r
      }

      case 'escalar_suporte': {
        const motivo = args.motivo || 'escalação genérica'
        const { data, error } = await supabase.rpc('marcar_contato_suporte', {
          p_contato_id: contato_id, p_motivo: motivo,
        })
        if (error) return { error: error.message }
        return { ok: true, data }
      }

      case 'enviar_foto_produto': {
        const key = String(args.produto || '').toLowerCase().trim()
        const match = FOTO_MAP[key]
        if (!match) return { send: false, error: `produto desconhecido: ${args.produto}` }
        if (fotosEnviadas.includes(match.tag)) return { send: false, already_sent: true, foto_tag: match.tag }
        const url = `${Deno.env.get('SUPABASE_URL')}/storage/v1/object/public/Start/${match.arquivo}`
        return { send: true, url, foto_tag: match.tag, caption: '' }
      }

      case 'iniciar_fechamento': {
        const { data, error } = await supabase.rpc('iniciar_fechamento_contato', {
          p_contato_id: contato_id,
          p_produto_pretendido: args.produto_pretendido || '',
        })
        if (error) return { error: error.message }
        return { ok: true, data }
      }

      default:
        return { error: `tool desconhecida: ${name}` }
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return { error: msg }
  }
}

// Chama outra Edge Function usando fetch interno (mais confiável que supabase.functions.invoke).
async function invokeFunction(_supabase: SupabaseClient, name: string, body: any) {
  const url = `${Deno.env.get('SUPABASE_URL')}/functions/v1/${name}`
  const r = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
    },
    body: JSON.stringify(body),
  })
  const txt = await r.text()
  try { return JSON.parse(txt) }
  catch { return { error: 'parse', body_preview: txt.slice(0, 300), status: r.status } }
}

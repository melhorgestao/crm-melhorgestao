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

// Alias keyword (que o LLM manda) → tag REAL do produto na tabela.
// Tags reais: verde | amarelo | vermelho | gummy | pomada | lub.
const TAG_ALIAS: Record<string, string> = {
  verde: 'verde', cbd: 'verde', cbd4000: 'verde', '4000': 'verde', '4000mg': 'verde',
  amarelo: 'amarelo', full6k: 'amarelo', '6000': 'amarelo', '6k': 'amarelo', '6000mg': 'amarelo',
  vermelho: 'vermelho', full10k: 'vermelho', '10000': 'vermelho', '10k': 'vermelho', '10000mg': 'vermelho',
  gummy: 'gummy', bear: 'gummy', gummybear: 'gummy',
  pomada: 'pomada', cannaderm: 'pomada',
  lub: 'lub', lubrificante: 'lub', intimo: 'lub', lubintimo: 'lub',
}

// Fallback LEGADO (arquivo fixo no bucket Start) SÓ se o produto não tiver
// arte_url cadastrada. Keyed pela tag real do produto.
const FOTO_LEGACY: Record<string, string> = {
  verde: 'Cbd.jpg', amarelo: 'Full6k.jpg', vermelho: 'Full10k.jpg',
  gummy: 'Gummy.jpg', pomada: 'Cannaderm.jpg', lub: 'Lub.jpg',
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
      description: 'Envia a ARTE (imagem) de um produto pro cliente. Chame quando você RECOMENDAR um produto específico OU o cliente focar num produto, na PRIMEIRA VEZ que ESSE produto aparece na conversa — uma vez por PRODUTO (pode enviar de produtos diferentes na mesma conversa). Não envie em saudação genérica nem pra produto citado só de passagem. Keywords: verde/cbd/4000 | amarelo/6000 | vermelho/10000 | gummy | pomada/cannaderm | lub. Se já foi enviada antes, retorna already_sent=true — não tente de novo.',
      parameters: {
        type: 'object',
        properties: {
          produto: { type: 'string', description: 'Keyword ou nome do produto (ex: verde, amarelo, gummy, cannaderm, "6.000 mg").' },
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
        const raw = String(args.produto || '').toLowerCase().trim()
        const nk = raw.replace(/[^a-z0-9]/g, '')
        // resolve keyword → tag real do produto
        const tag = TAG_ALIAS[raw] || TAG_ALIAS[nk] || nk
        // já enviada pra este contato? (persistido em contatos.fotos_enviadas)
        if (fotosEnviadas.includes(tag)) return { send: false, already_sent: true, foto_tag: tag }

        // 1) busca a ARTE do produto por tag
        let arte: string | null = null
        let prodNome = ''
        const { data: prodByTag } = await supabase
          .from('produtos').select('arte_url, foto_url, nome_oficial, emoji')
          .eq('tag', tag).eq('ativo', true).maybeSingle()
        if (prodByTag) { arte = (prodByTag as any).arte_url || null; prodNome = (prodByTag as any).nome_oficial || '' }

        // 2) fallback: casa pelo NOME do produto contendo a keyword
        if (!arte && raw.length >= 3) {
          const { data: byName } = await supabase
            .from('produtos').select('arte_url, tag, nome_oficial')
            .ilike('nome_oficial', `%${raw}%`).eq('ativo', true).limit(1).maybeSingle()
          if ((byName as any)?.arte_url) { arte = (byName as any).arte_url; prodNome = (byName as any).nome_oficial || '' }
        }

        // 3) fallback LEGADO: arquivo fixo no bucket (só se não tiver arte cadastrada)
        const base = (Deno.env.get('SUPABASE_URL') || '').replace(/\/+$/, '')
        const legacy = FOTO_LEGACY[tag]
        const url = arte || (legacy ? `${base}/storage/v1/object/public/Start/${legacy}` : null)

        if (!url) return { send: false, error: `sem arte cadastrada pro produto: ${args.produto}` }
        return { send: true, url, foto_tag: tag, caption: '', usou_arte: !!arte, produto: prodNome }
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

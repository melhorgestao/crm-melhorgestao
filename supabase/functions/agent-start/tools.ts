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
// ATENÇÃO: nomes EXATOS (case-sensitive!) dos arquivos que existem no bucket.
// Os antigos .jpg (Cbd.jpg, Full6k.jpg, Lub.jpg...) NÃO existem → Evolution
// recebia 404 e descartava a imagem em silêncio (texto ia, foto não).
const FOTO_LEGACY: Record<string, string> = {
  verde: 'Cbd.png', amarelo: 'Full6k.png', vermelho: 'Full10k.png',
  gummy: 'Gummy.png', pomada: 'cannaderm.png', lub: 'lub.png',
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
        const foto = await resolverFotoProduto(supabase, tag, raw)
        if (!foto) return { send: false, error: `sem arte cadastrada pro produto: ${args.produto}` }
        return { send: true, ...foto, caption: '' }
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

// ---- FOTOS DE PRODUTO (determinístico) -------------------------------------

/** Resolve a URL da arte de um produto: arte_url do cadastro (Estoque >
 *  Editar Produto > ArteProduto) → match por nome → arquivo legado no bucket Start. */
export async function resolverFotoProduto(
  supabase: SupabaseClient, tag: string, rawKeyword = '',
): Promise<{ url: string; foto_tag: string; usou_arte: boolean; produto: string } | null> {
  let arte: string | null = null
  let prodNome = ''
  const { data: prodByTag } = await supabase
    .from('produtos').select('arte_url, nome_oficial')
    .eq('tag', tag).eq('ativo', true).maybeSingle()
  if (prodByTag) { arte = (prodByTag as any).arte_url || null; prodNome = (prodByTag as any).nome_oficial || '' }

  if (!arte && rawKeyword.length >= 3) {
    const { data: byName } = await supabase
      .from('produtos').select('arte_url, nome_oficial')
      .ilike('nome_oficial', `%${rawKeyword}%`).eq('ativo', true).limit(1).maybeSingle()
    if ((byName as any)?.arte_url) { arte = (byName as any).arte_url; prodNome = (byName as any).nome_oficial || '' }
  }

  const base = (Deno.env.get('SUPABASE_URL') || '').replace(/\/+$/, '')
  const legacy = FOTO_LEGACY[tag]
  const legacyUrl = legacy ? `${base}/storage/v1/object/public/Start/${legacy}` : null

  // Valida a URL ANTES de anexar: a Evolution descarta imagem com link morto
  // EM SILÊNCIO (texto vai, foto não) e a tag ficaria marcada sem entrega.
  const urlViva = async (u: string | null): Promise<boolean> => {
    if (!u) return false
    try {
      const r = await fetch(u, { method: 'HEAD', signal: AbortSignal.timeout(4000) })
      return r.ok
    } catch (_) { return false }
  }
  for (const cand of [arte, legacyUrl]) {
    if (cand && await urlViva(cand)) {
      return { url: cand, foto_tag: tag, usou_arte: cand === arte, produto: prodNome }
    }
  }
  return null
}

/** Detecta quais produtos estão EM FOCO num texto (resposta do agente).
 *  Retorna tags na ordem de aparição. Usado pra anexar foto automaticamente
 *  quando o LLM esquece de chamar enviar_foto_produto. */
export function detectarProdutosNoTexto(texto: string, incluirCbdGenerico = false): string[] {
  const t = String(texto || '').toLowerCase()
  const firstIdx = (patterns: RegExp[]) => {
    let best = -1
    for (const p of patterns) {
      const m = t.match(p)
      if (m && m.index !== undefined && (best === -1 || m.index < best)) best = m.index
    }
    return best
  }
  const found: Array<{ tag: string; idx: number }> = []
  const gummyIdx = firstIdx([/gummy/, /\bgomi\b/, /jujuba/])
  if (gummyIdx >= 0) found.push({ tag: 'gummy', idx: gummyIdx })
  const vermIdx = firstIdx([/vermelho/, /10[.\s]?000\s?mg/, /\b1\s?:\s?2\b/])
  if (vermIdx >= 0) found.push({ tag: 'vermelho', idx: vermIdx })
  // AMARELO: o nome oficial do Gummy contém "CBD 1:1 THC 6.000 mg" — se gummy
  // foi detectado, "1:1"/"6.000 mg" NÃO contam como amarelo (evita anexar a
  // foto do óleo errado junto). Só a PALAVRA "amarelo" conta nesse caso.
  const amareloWord = firstIdx([/amarelo/])
  const amareloNum  = firstIdx([/6[.\s]?000\s?mg/, /\b1\s?:\s?1\b/])
  const amareloIdx  = amareloWord >= 0 ? amareloWord : (gummyIdx === -1 ? amareloNum : -1)
  if (amareloIdx >= 0) found.push({ tag: 'amarelo', idx: amareloIdx })
  let verdeIdx = firstIdx([/\bverde\b/, /4[.\s]?000\s?mg/])
  // "cbd" genérico → verde (apelido oficial do produto), mas SÓ quando nenhum
  // outro óleo/gummy foi citado (CBD aparece no nome de todos). Usado na
  // PERGUNTA do lead ("me fala do cbd"), onde a intenção é o Verde.
  if (verdeIdx === -1 && incluirCbdGenerico && found.length === 0) {
    verdeIdx = firstIdx([/\bcbd\b/, /canabidiol/])
  }
  if (verdeIdx >= 0) found.push({ tag: 'verde', idx: verdeIdx })
  const pomadaIdx = firstIdx([/cannaderm/, /pomada/])
  if (pomadaIdx >= 0) found.push({ tag: 'pomada', idx: pomadaIdx })
  const lubIdx = firstIdx([/lubrificante/])
  if (lubIdx >= 0) found.push({ tag: 'lub', idx: lubIdx })
  return found.sort((a, b) => a.idx - b.idx).map(f => f.tag)
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

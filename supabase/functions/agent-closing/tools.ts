// ============================================================================
// agent-closing / tools.ts — schemas + executor das tools de fechamento.
// ============================================================================

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface ToolCtx {
  name: string
  args: Record<string, any>
  contato_id: string
  instancia_id?: string | null
  supabase: SupabaseClient
  fotosEnviadas?: string[]
}

// Alias keyword → tag REAL do produto (mesmo mapa do agent-start).
const TAG_ALIAS: Record<string, string> = {
  verde: 'verde', cbd: 'verde', cbd4000: 'verde', '4000': 'verde', '4000mg': 'verde',
  amarelo: 'amarelo', full6k: 'amarelo', '6000': 'amarelo', '6k': 'amarelo', '6000mg': 'amarelo',
  vermelho: 'vermelho', full10k: 'vermelho', '10000': 'vermelho', '10k': 'vermelho', '10000mg': 'vermelho',
  gummy: 'gummy', bear: 'gummy', gummybear: 'gummy',
  pomada: 'pomada', cannaderm: 'pomada',
  lub: 'lub', lubrificante: 'lub', intimo: 'lub', lubintimo: 'lub',
}

// Fallback LEGADO (arquivo fixo no bucket Start) se o produto não tiver arte_url.
const FOTO_LEGACY: Record<string, string> = {
  verde: 'Cbd.jpg', amarelo: 'Full6k.jpg', vermelho: 'Full10k.jpg',
  gummy: 'Gummy.jpg', pomada: 'Cannaderm.jpg', lub: 'Lub.jpg',
}

export const CLOSING_TOOL_SCHEMAS = [
  {
    type: 'function',
    function: {
      name: 'buscar_conhecimento',
      description: 'RAG semântico pra responder dúvidas pontuais DURANTE o fechamento (interações medicamentosas, modo de uso, ingredientes, segurança). NÃO use para preço/catálogo (já tem no system prompt).',
      parameters: {
        type: 'object',
        properties: { pergunta: { type: 'string', description: 'Pergunta do cliente.' } },
        required: ['pergunta'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'consultar_cep',
      description: 'Consulta ViaCEP. Use logo que cliente mandar o CEP pra preencher rua/bairro/cidade/uf. Retorna {cep, rua, bairro, cidade, uf}.',
      parameters: {
        type: 'object',
        properties: { cep: { type: 'string', description: 'CEP 8 dígitos sem hífen.' } },
        required: ['cep'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'consultar_frete',
      description: 'Calcula preço e prazo de frete via Superfrete pro CEP de destino. Use IMEDIATAMENTE após consultar_cep retornar OK, pra mostrar opções de frete ao cliente ANTES de pedir mais dados.',
      parameters: {
        type: 'object',
        properties: {
          to_cep:       { type: 'string', description: 'CEP de destino 8 dígitos.' },
          qtd_produtos: { type: 'number', description: 'Quantidade total de produtos. Default 1.' },
        },
        required: ['to_cep'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'salvar_endereco',
      description: 'Persiste endereço completo + CPF no banco. Chame APÓS cliente confirmar todos os campos. CPF é obrigatório pra etiqueta de envio.',
      parameters: {
        type: 'object',
        properties: {
          cep:         { type: 'string', description: 'CEP só dígitos.' },
          rua:         { type: 'string', description: 'Logradouro.' },
          numero:      { type: 'string', description: 'Número (texto).' },
          complemento: { type: 'string', description: 'Apto/bloco/casa (vazio se nada).' },
          bairro:      { type: 'string', description: 'Bairro.' },
          cidade:      { type: 'string', description: 'Cidade.' },
          uf:          { type: 'string', description: 'UF 2 letras.' },
          cpf:         { type: 'string', description: 'CPF do cliente (11 dígitos, com ou sem máscara). Obrigatório pra etiqueta.' },
        },
        required: ['cep', 'rua', 'numero', 'bairro', 'cidade', 'uf', 'cpf'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'calcular_pedido',
      description: 'Calcula preço final, frete (Superfrete), aplica bônus e cria pedido_em_aberto. Retorna resumo + pedido_em_aberto_id. modalidade_frete_escolhida só quando NÃO for frete grátis (qtd 2-3 = sempre grátis). brindes_tags só quando qtd>=4. Se retornar pendencias, atenda-as antes.',
      parameters: {
        type: 'object',
        properties: {
          itens:                       { type: 'array', description: 'Lista de itens.', items: { type: 'object', properties: { tag: { type: 'string' }, qtd: { type: 'number' } }, required: ['tag', 'qtd'] } },
          brindes_tags:                { type: 'array', description: 'Tags dos brindes escolhidos (vazio se não tem).', items: { type: 'string' } },
          modalidade_frete_escolhida:  { type: 'string', description: 'PAC|MINI|SEDEX (só quando cliente paga frete).' },
          is_parcelado:                { type: 'boolean', description: 'True se cliente pediu parcelar 50/50 (só 4+ produtos).' },
        },
        required: ['itens'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'gerar_pix_deflow',
      description: 'Gera o Pix DeFlow pro pedido_em_aberto criado por calcular_pedido. Chame APÓS cliente confirmar resumo. Retorna copia-cola pronto.',
      parameters: {
        type: 'object',
        properties: { pedido_em_aberto_id: { type: 'string', description: 'UUID retornado por calcular_pedido.' } },
        required: ['pedido_em_aberto_id'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'gerar_pix_saldo_devedor',
      description: 'Use APENAS quando cliente tem pendência e quer pagar o restante. Cria cobrança do saldo exato e gera Pix imediato. NÃO use pra pedido novo.',
      parameters: { type: 'object', properties: {}, required: [] },
    },
  },
  {
    type: 'function',
    function: {
      name: 'enviar_foto_produto',
      description: 'Envia a ARTE (imagem) de um produto pro cliente. Chame quando o cliente perguntar/focar num produto específico durante o fechamento, na PRIMEIRA VEZ que ESSE produto aparece — uma vez por PRODUTO. Keywords: verde/cbd/4000 | amarelo/6000 | vermelho/10000 | gummy | pomada/cannaderm | lub. Se já foi enviada, retorna already_sent=true — não tente de novo. NÃO desvie da state machine: responda + foto e siga o passo atual.',
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
      name: 'escalar_suporte',
      description: 'Encaminha pro Kanban Suporte. APENAS em casos sérios: reclamação grave, irritação, pediu_atendente. Estado vira "suporte".',
      parameters: {
        type: 'object',
        properties: { motivo: { type: 'string', description: 'Motivo curto: irritacao | reclamacao | pediu_atendente | duvida_fora_escopo' } },
        required: ['motivo'],
      },
    },
  },
]

export async function executeClosingTool(ctx: ToolCtx): Promise<any> {
  const { name, args, contato_id, instancia_id, supabase, fotosEnviadas = [] } = ctx

  try {
    switch (name) {

      case 'buscar_conhecimento': {
        if (!args.pergunta) return { error: 'pergunta obrigatória' }
        const r = await invokeFunction('buscar-conhecimento-agent', { pergunta: args.pergunta, limit: 5 })
        return { chunks: r?.chunks ?? [] }
      }

      case 'consultar_cep': {
        if (!args.cep) return { error: 'cep obrigatório' }
        const cepClean = String(args.cep).replace(/\D/g, '')
        const r = await fetch(`https://viacep.com.br/ws/${cepClean}/json/`)
        if (!r.ok) return { error: `ViaCEP ${r.status}` }
        const j = await r.json()
        if (j.erro) return { error: 'CEP não encontrado' }
        const rua = j.logradouro || ''
        const cidade = j.localidade || ''
        const uf = j.uf || ''
        // Persiste JÁ no contato pra os dados sobreviverem entre turnos (o
        // agent recarrega o contexto a cada mensagem). Assim, no ESTADO 3 o
        // salvar_endereco só completa numero+CPF. numero/cpf vazios NÃO apagam
        // o que já existe (upsert usa COALESCE-preserva).
        try {
          await supabase.rpc('upsert_endereco_contato', {
            p_contato_id:  contato_id,
            p_cep:         cepClean,
            p_rua:         rua,
            p_numero:      '',
            p_complemento: '',
            p_bairro:      j.bairro || '',
            p_cidade:      cidade,
            p_uf:          uf,
            p_cpf:         null,
          })
        } catch (_) { /* persistência é best-effort; segue com os dados retornados */ }
        // cep_de_cidade = ViaCEP não trouxe logradouro (CEP geral de cidade) →
        // o agent precisa pedir a RUA no ESTADO 3.
        return {
          cep: cepClean,
          rua,
          bairro: j.bairro || '',
          cidade,
          uf,
          cep_de_cidade: !rua,
        }
      }

      case 'consultar_frete': {
        if (!args.to_cep) return { error: 'to_cep obrigatório' }
        const r = await invokeFunction('consultar-frete-agent', {
          to_cep: String(args.to_cep).replace(/\D/g, ''),
          qtd_produtos: args.qtd_produtos || 1,
        })
        return r
      }

      case 'salvar_endereco': {
        const cpfLimpo = String(args.cpf || '').replace(/\D/g, '')
        if (cpfLimpo && cpfLimpo.length !== 11) {
          return { error: 'CPF inválido (precisa ter 11 dígitos)' }
        }
        const { data, error } = await supabase.rpc('upsert_endereco_contato', {
          p_contato_id:  contato_id,
          p_cep:         String(args.cep || '').replace(/\D/g, ''),
          p_rua:         args.rua || '',
          p_numero:      args.numero || '',
          p_complemento: args.complemento || '',
          p_bairro:      args.bairro || '',
          p_cidade:      args.cidade || '',
          p_uf:          (args.uf || '').toUpperCase(),
          p_cpf:         cpfLimpo || null,
        })
        if (error) return { error: error.message }
        if (data && data.ok === false) return { error: data.error || 'falha ao salvar endereço' }
        return { ok: true }
      }

      case 'enviar_foto_produto': {
        const raw = String(args.produto || '').toLowerCase().trim()
        const nk = raw.replace(/[^a-z0-9]/g, '')
        const tag = TAG_ALIAS[raw] || TAG_ALIAS[nk] || nk
        // já enviada pra este contato? (persistido em contatos.fotos_enviadas)
        if (fotosEnviadas.includes(tag)) return { send: false, already_sent: true, foto_tag: tag }
        const foto = await resolverFotoProduto(supabase, tag, raw)
        if (!foto) return { send: false, error: `sem arte cadastrada pro produto: ${args.produto}` }
        return { send: true, ...foto, caption: '' }
      }

      case 'calcular_pedido': {
        if (!Array.isArray(args.itens) || args.itens.length === 0) return { error: 'itens obrigatórios' }
        const r = await invokeFunction('calcular-pedido', {
          contato_id,
          instancia_id,
          itens: args.itens,
          brindes_tags: args.brindes_tags || [],
          modalidade_frete_escolhida: args.modalidade_frete_escolhida || null,
          is_parcelado: !!args.is_parcelado,
        })
        return r
      }

      case 'gerar_pix_deflow': {
        if (!args.pedido_em_aberto_id) return { error: 'pedido_em_aberto_id obrigatório' }
        const r = await invokeFunction('gerar-pix-deflow', {
          pedido_em_aberto_id: args.pedido_em_aberto_id,
        })
        return r
      }

      case 'gerar_pix_saldo_devedor': {
        const { data, error } = await supabase.rpc('criar_cobranca_saldo_devedor', {
          p_contato_id:   contato_id,
          p_instancia_id: instancia_id,
        })
        if (error) return { error: error.message }
        return data ?? { ok: true }
      }

      case 'escalar_suporte': {
        const motivo = args.motivo || 'escalação genérica'
        const { error } = await supabase.rpc('marcar_contato_suporte', {
          p_contato_id: contato_id, p_motivo: motivo,
        })
        if (error) return { error: error.message }
        return { ok: true }
      }

      default:
        return { error: `tool desconhecida: ${name}` }
    }
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) }
  }
}

// ---- FOTOS DE PRODUTO (determinístico — mesmo padrão do agent-start) -------

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
  const url = arte || (legacy ? `${base}/storage/v1/object/public/Start/${legacy}` : null)
  if (!url) return null
  return { url, foto_tag: tag, usou_arte: !!arte, produto: prodNome }
}

/** Detecta quais produtos estão EM FOCO num texto (resposta do agente). */
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

async function invokeFunction(name: string, body: any) {
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

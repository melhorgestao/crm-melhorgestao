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
      description: 'Consulta ViaCEP. Use APENAS pra preencher rua/bairro/cidade/uf a partir do CEP. Retorna {cep, rua, bairro, cidade, uf}. Não calcula frete.',
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
      name: 'salvar_endereco',
      description: 'Persiste o endereço completo no banco. Chame APÓS cliente confirmar todos os campos.',
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
        },
        required: ['cep', 'rua', 'numero', 'bairro', 'cidade', 'uf'],
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
  const { name, args, contato_id, instancia_id, supabase } = ctx

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
        return {
          cep: cepClean,
          rua: j.logradouro,
          bairro: j.bairro,
          cidade: j.localidade,
          uf: j.uf,
        }
      }

      case 'salvar_endereco': {
        const { error } = await supabase.rpc('upsert_endereco_contato', {
          p_contato_id:  contato_id,
          p_cep:         String(args.cep || '').replace(/\D/g, ''),
          p_rua:         args.rua || '',
          p_numero:      args.numero || '',
          p_complemento: args.complemento || '',
          p_bairro:      args.bairro || '',
          p_cidade:      args.cidade || '',
          p_uf:          (args.uf || '').toUpperCase(),
        })
        if (error) return { error: error.message }
        return { ok: true }
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

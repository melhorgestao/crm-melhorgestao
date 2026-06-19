// ============================================================================
// calcular-pedido
//
// Tool do AGENT_CLOSING. Recebe pedido em linguagem livre (já parseado em itens),
// calcula bônus, frete (via consultar-frete-agent), monta resumo formatado e
// PERSISTE um pedido_em_aberto via RPC criar_pedido_em_aberto.
//
// INPUT:
//   {
//     contato_id: uuid,
//     instancia_id: uuid,
//     itens: [{ tag: "verde", qtd: 2 }, ...],
//     brindes_tags?: ["pomada", "gummy"],   // opcional, requerido se qtd dispara bônus
//     modalidade_frete_escolhida?: "PAC" | "MINI" | "SEDEX"  // só quando frete não é grátis
//   }
//
// OUTPUT:
//   {
//     ok: true,
//     pedido_em_aberto_id: uuid,
//     resumo_formatado: string,
//     total: number,
//     subtotal: number,
//     frete: { gratis: boolean, modalidade, preco, prazo_min, prazo_max },
//     bonus: { qtd_brindes_devidos: 0|1|2, brindes_aplicados: [...] },
//     pendencias: ["escolher_brinde" | "escolher_modalidade_frete" | "endereco"]
//   }
//
// REGRAS DE BÔNUS (escala fixa, não cumulativo com frete):
//   qtd_total = 1     → sem bônus, cliente paga frete
//   qtd_total ∈ {2,3} → frete grátis Sedex, sem brindes
//   qtd_total ∈ {4..7}→ 1 brinde produto, cliente paga frete (escolhe modalidade)
//   qtd_total ≥ 8     → 2 brindes produto, cliente paga frete (escolhe modalidade)
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface Item { tag: string; qtd: number }
interface ProdutoRow {
  tag: string; nome_oficial: string; emoji: string;
  preco: number; peso: number; ativo: boolean; ordem: number;
}

function calcularBonusEFrete(qtdTotal: number): { brindesDevidos: 0|1|2; freteGratis: boolean } {
  if (qtdTotal >= 8) return { brindesDevidos: 2, freteGratis: false }
  if (qtdTotal >= 4) return { brindesDevidos: 1, freteGratis: false }
  if (qtdTotal >= 2) return { brindesDevidos: 0, freteGratis: true }
  return { brindesDevidos: 0, freteGratis: false }
}

function brl(n: number): string {
  return n.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const body = await req.json()
    const {
      contato_id, instancia_id,
      itens, brindes_tags = [],
      modalidade_frete_escolhida,
      is_parcelado = false,
    } = body as {
      contato_id: string
      instancia_id: string
      itens: Item[]
      brindes_tags?: string[]
      modalidade_frete_escolhida?: 'PAC'|'MINI'|'SEDEX'
      is_parcelado?: boolean
    }

    if (!contato_id || !instancia_id || !Array.isArray(itens) || itens.length === 0) {
      return j({ error: 'contato_id, instancia_id e itens são obrigatórios' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 1) Carrega contato + endereço
    const { data: contato, error: cErr } = await supabase
      .from('contatos')
      .select('id, cep, rua, numero, complemento, bairro, cidade, uf')
      .eq('id', contato_id).single()
    if (cErr || !contato) return j({ error: 'contato não encontrado' }, 404)
    if (!contato.cep || !contato.rua || !contato.numero || !contato.uf) {
      return j({ ok: false, pendencias: ['endereco'],
                 error: 'endereço incompleto — peça CEP, número, etc antes de calcular' }, 200)
    }

    // 2) Carrega catálogo
    const tagsNecessarios = Array.from(new Set([...itens.map(i => i.tag),
                                                  ...(brindes_tags || [])]))
    const { data: produtos, error: pErr } = await supabase
      .from('produtos').select('tag, nome_oficial, emoji, preco, peso, ativo, ordem')
      .in('tag', tagsNecessarios)
    if (pErr) return j({ error: pErr.message }, 500)
    const prodMap = new Map<string, ProdutoRow>(
      (produtos || []).map((p: any) => [p.tag, p as ProdutoRow])
    )

    // 3) Valida itens
    const itensEnriquecidos = itens
      .filter(i => i.qtd > 0)
      .map(i => {
        const p = prodMap.get(i.tag)
        if (!p) throw new Error(`produto não encontrado: ${i.tag}`)
        if (!p.ativo) throw new Error(`produto inativo: ${i.tag}`)
        return {
          tag: i.tag,
          nome_oficial: p.nome_oficial,
          emoji: p.emoji || '•',
          qtd: i.qtd,
          preco_unit: Number(p.preco),
          peso_unit:  Number(p.peso || 300),
          subtotal:   Number(p.preco) * i.qtd,
        }
      })

    const qtdTotal     = itensEnriquecidos.reduce((s, x) => s + x.qtd, 0)
    const subtotal     = itensEnriquecidos.reduce((s, x) => s + x.subtotal, 0)
    const pesoTotal_g  = itensEnriquecidos.reduce((s, x) => s + x.qtd * x.peso_unit, 0)

    // 4) Bônus
    const { brindesDevidos, freteGratis } = calcularBonusEFrete(qtdTotal)
    const pendencias: string[] = []

    let brindesAplicados: Array<{ tag: string; nome_oficial: string; emoji: string }> = []
    if (brindesDevidos > 0) {
      if (brindes_tags.length < brindesDevidos) {
        pendencias.push('escolher_brinde')
      } else {
        brindesAplicados = brindes_tags.slice(0, brindesDevidos).map(s => {
          const p = prodMap.get(s)
          if (!p) throw new Error(`brinde não encontrado: ${s}`)
          return { tag: s, nome_oficial: p.nome_oficial, emoji: p.emoji || '🎁' }
        })
      }
    }

    // 5) Frete
    let modalidade: string | null = null
    let fretePreco = 0
    let prazoMin: number | null = null
    let prazoMax: number | null = null
    let modalidadesDisponiveis: any[] = []

    if (freteGratis) {
      modalidade = 'SEDEX'
      fretePreco = 0
      // ainda assim consulta pra ter prazo
      try {
        const fr = await chamarConsultarFrete(supabase, contato.cep, qtdTotal, pesoTotal_g)
        const sedex = fr.modalidades?.find((m: any) => /sedex/i.test(m.nome))
        prazoMin = sedex?.prazo_min ?? null
        prazoMax = sedex?.prazo_max ?? null
      } catch { /* prazo opcional */ }
    } else {
      // cliente paga frete → precisa modalidade escolhida
      const fr = await chamarConsultarFrete(supabase, contato.cep, qtdTotal, pesoTotal_g)
      modalidadesDisponiveis = fr.modalidades || []
      if (!modalidade_frete_escolhida) {
        pendencias.push('escolher_modalidade_frete')
      } else {
        const mod = modalidadesDisponiveis.find((m: any) =>
          new RegExp(modalidade_frete_escolhida, 'i').test(m.nome))
        if (!mod) {
          pendencias.push('escolher_modalidade_frete')
        } else {
          modalidade = modalidade_frete_escolhida
          fretePreco = Number(mod.preco)
          prazoMin   = mod.prazo_min ?? null
          prazoMax   = mod.prazo_max ?? null
        }
      }
    }

    // 5.5) Cupom (aplicação automática sobre o subtotal de produtos, NUNCA sobre frete)
    const { data: cupomData } = await supabase.rpc('cupom_para_contato', { p_contato_id: contato_id })
    const cupom = (cupomData && typeof cupomData === 'object' ? cupomData : null) as any
    const descontoPct = cupom ? Number(cupom.desconto_pct) : 0
    const descontoValor = subtotal * (descontoPct / 100)
    const subtotalComDesconto = subtotal - descontoValor

    const total = subtotalComDesconto + fretePreco

    // 6) Resumo formatado
    const linhasProdutos = itensEnriquecidos.map(x => {
      const emojis = x.emoji.repeat(x.qtd)
      return `${emojis} ${x.nome_oficial} (${x.qtd}x) — R$ ${brl(x.subtotal)}`
    }).join('\n')

    const linhaBrindes = brindesAplicados.length
      ? brindesAplicados.map(b => `🎁 Brinde: ${b.emoji} ${b.nome_oficial}`).join('\n')
      : ''

    const linhaFrete = freteGratis
      ? `📦 Sedex — *GRÁTIS*${prazoMin ? `\n⏱ ${prazoMin} a ${prazoMax} dias` : ''}`
      : modalidade
        ? `📦 ${modalidade} — R$ ${brl(fretePreco)}${prazoMin ? `\n⏱ ${prazoMin} a ${prazoMax} dias` : ''}`
        : `📦 Frete: *aguardando escolha de modalidade*`

    const linhaDesconto = cupom
      ? `\n🎟 Cupom ${cupom.nome}: -${descontoPct}% (-R$ ${brl(descontoValor)})`
      : ''

    const resumo = [
      '📋 *Resumo do pedido:*',
      '',
      linhasProdutos,
      linhaBrindes,
      linhaDesconto.trim(),
      '',
      linhaFrete,
      '',
      `💳 *Total: R$ ${brl(total)}*`,
    ].filter(Boolean).join('\n')

    // 7) Se tem pendência, NÃO grava ainda — só devolve estado
    if (pendencias.length > 0) {
      return j({
        ok: true,
        pendencias,
        modalidades_disponiveis: modalidadesDisponiveis,
        brindes_devidos: brindesDevidos,
        subtotal, total,
        frete: { gratis: freteGratis, modalidade, preco: fretePreco,
                 prazo_min: prazoMin, prazo_max: prazoMax },
        resumo_formatado: resumo,
      })
    }

    // 8) Grava pedido_em_aberto
    const enderecoSnapshot = {
      cep: contato.cep, rua: contato.rua, numero: contato.numero,
      complemento: contato.complemento, bairro: contato.bairro,
      cidade: contato.cidade, uf: contato.uf,
    }

    const { data: rpcRes, error: rpcErr } = await supabase.rpc('criar_pedido_em_aberto', {
      p_contato_id: contato_id,
      p_instancia_id: instancia_id,
      p_itens: itensEnriquecidos,
      p_brindes: brindesAplicados,
      p_modalidade_frete: modalidade,
      p_frete_preco: fretePreco,
      p_frete_prazo_min: prazoMin,
      p_frete_prazo_max: prazoMax,
      p_frete_gratis: freteGratis,
      p_endereco_snapshot: enderecoSnapshot,
      p_subtotal: subtotal,
      p_total: total,
      p_resumo_formatado: resumo,
      p_is_parcelado: !!is_parcelado,
    })
    if (rpcErr) return j({ error: rpcErr.message }, 500)

    return j({
      ok: true,
      pedido_em_aberto_id: rpcRes.pedido_em_aberto_id,
      resumo_formatado: resumo,
      subtotal, total,
      is_parcelado: !!is_parcelado,
      valor_a_pagar_pix: rpcRes.valor_a_pagar_pix,
      frete: { gratis: freteGratis, modalidade, preco: fretePreco,
               prazo_min: prazoMin, prazo_max: prazoMax },
      brindes_aplicados: brindesAplicados,
      cupom: cupom ? { nome: cupom.nome, pct: descontoPct, desconto_valor: descontoValor } : null,
      pendencias: [],
    })

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ error: msg }, 500)
  }
})

async function chamarConsultarFrete(supabase: any, cep: string, qtd: number, peso_g: number) {
  const url = `${Deno.env.get('SUPABASE_URL')}/functions/v1/consultar-frete-agent`
  const r = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
    },
    body: JSON.stringify({ to_cep: cep, qtd_produtos: qtd, peso_g }),
  })
  if (!r.ok) throw new Error(`consultar-frete-agent: ${r.status}`)
  return await r.json()
}

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

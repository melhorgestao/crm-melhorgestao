// ============================================================================
// regenerar-chunks-tabela
//
// Lê a tabela `produtos` (source of truth do catálogo) e regenera os chunks
// da categoria 'tabela' em knowledge_chunks. 1 chunk por produto, com
// embedding gerado pela OpenAI.
//
// Idempotente:
//   - Match por título "<emoji> <nome_oficial>" → se existe, UPDATE
//   - Se não existe, INSERT
//   - Chunks órfãos (produto não existe mais) são DESATIVADOS (ativo=false)
//     em vez de deletados — preserva histórico
//
// Requer: configuracoes.openai_api_key
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface Produto {
  id: string; tag: string | null; nome_oficial: string; emoji: string | null;
  preco: number | null; posologia: string | null; ativo: boolean; ordem: number;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: cfg } = await supabase
      .from('configuracoes').select('valor').eq('chave', 'openai_api_key').maybeSingle()
    const openaiKey = (cfg?.valor as string | undefined)?.trim()
    if (!openaiKey) return j({ error: 'openai_api_key não configurada' }, 400)

    const { data: produtos, error: pErr } = await supabase
      .from('produtos')
      .select('id, tag, nome_oficial, emoji, preco, posologia, ativo, ordem')
      .eq('ativo', true)
      .order('ordem', { ascending: true })
      .order('nome_oficial', { ascending: true })
    if (pErr) return j({ error: pErr.message }, 500)

    const ativos = (produtos || []) as Produto[]
    if (ativos.length === 0) return j({ ok: true, criados: 0, atualizados: 0, desativados: 0 })

    // Carrega chunks existentes de tabela
    const { data: existentes, error: eErr } = await supabase
      .from('knowledge_chunks')
      .select('id, titulo, conteudo, ativo, observacao')
      .eq('categoria', 'tabela')
    if (eErr) return j({ error: eErr.message }, 500)
    const existMap = new Map<string, any>((existentes || []).map((c: any) => [c.titulo, c]))

    let criados = 0, atualizados = 0, ignorados = 0
    const titulosGerados = new Set<string>()

    for (const p of ativos) {
      if (!p.emoji || !p.nome_oficial) { ignorados++; continue }
      const titulo = `${p.emoji} ${p.nome_oficial}`.trim()
      titulosGerados.add(titulo)

      // Catálogo deve ficar limpo: só nome + preço.
      // Apelidos vão em "sobre_produtos", posologia/modo de uso também.
      // Embedding focado ranqueia melhor pra "quanto custa X" e nada mais.
      const conteudoLinhas = [
        p.nome_oficial,
        '',
        p.preco != null
          ? `Preço: R$ ${Number(p.preco).toLocaleString('pt-BR',{minimumFractionDigits:2})}`
          : 'Preço: a consultar',
      ]
      const conteudo = conteudoLinhas.join('\n')

      const textForEmbedding = `${titulo}\n\n${conteudo}`
      const embRes = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${openaiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ model: 'text-embedding-3-small', input: textForEmbedding }),
      })
      if (!embRes.ok) {
        const t = await embRes.text()
        return j({ error: `OpenAI embedding: ${embRes.status}`, details: t.slice(0,200) }, 500)
      }
      const embedding = (await embRes.json())?.data?.[0]?.embedding
      if (!embedding) return j({ error: 'embedding ausente' }, 500)

      const existente = existMap.get(titulo)
      const payload = {
        titulo, categoria: 'tabela', conteudo, embedding,
        ativo: true, observacao: 'auto-gerado a partir da tabela produtos',
        updated_at: new Date().toISOString(),
      }

      if (existente) {
        const { error } = await supabase
          .from('knowledge_chunks').update(payload).eq('id', existente.id)
        if (error) return j({ error: error.message, on: 'update', titulo }, 500)
        atualizados++
      } else {
        const { error } = await supabase
          .from('knowledge_chunks').insert(payload)
        if (error) return j({ error: error.message, on: 'insert', titulo }, 500)
        criados++
      }
    }

    // Desativa chunks de produto que não existe mais (mas só os auto-gerados)
    let desativados = 0
    for (const c of (existentes || []) as any[]) {
      if (titulosGerados.has(c.titulo)) continue
      if (c.observacao !== 'auto-gerado a partir da tabela produtos') continue
      if (!c.ativo) continue
      const { error } = await supabase
        .from('knowledge_chunks').update({ ativo: false, updated_at: new Date().toISOString() }).eq('id', c.id)
      if (!error) desativados++
    }

    return j({
      ok: true, criados, atualizados, desativados, ignorados,
      total_produtos_processados: ativos.length,
    })

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ error: msg }, 500)
  }
})

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

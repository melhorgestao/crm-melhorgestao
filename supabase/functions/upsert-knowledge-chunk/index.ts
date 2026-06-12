// ============================================================================
// upsert-knowledge-chunk
//
// Recebe { id?, titulo, categoria, conteudo, observacao?, ativo? }
// 1) Gera embedding via OpenAI text-embedding-3-small a partir de titulo+conteudo
// 2) INSERT (se id ausente) ou UPDATE (se id presente) em knowledge_chunks
// 3) Retorna { ok, id, action: 'created' | 'updated' }
// ============================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const CATEGORIAS = ['tabela','sobre_produtos','bonus','argumentos_venda','faq']

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { id, titulo, categoria, conteudo, observacao, ativo } = await req.json()

    if (!titulo || !categoria || !conteudo) {
      return json({ error: 'titulo, categoria e conteudo são obrigatórios' }, 400)
    }
    if (!CATEGORIAS.includes(categoria)) {
      return json({ error: `categoria inválida (use ${CATEGORIAS.join('|')})` }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Chave OpenAI
    const { data: cfg } = await supabase
      .from('configuracoes').select('valor').eq('chave', 'openai_api_key').maybeSingle()
    const openaiKey = cfg?.valor as string | undefined
    if (!openaiKey || openaiKey.trim() === '') {
      return json({ error: 'openai_api_key não configurada em configuracoes' }, 400)
    }

    // Embedding (titulo + conteudo concatenados pra capturar contexto)
    const textForEmbedding = `${titulo.trim()}\n\n${conteudo.trim()}`
    const embRes = await fetch('https://api.openai.com/v1/embeddings', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'text-embedding-3-small',
        input: textForEmbedding,
      }),
    })
    if (!embRes.ok) {
      const t = await embRes.text()
      return json({ error: `OpenAI embedding falhou: ${embRes.status}`, details: t.slice(0, 200) }, 500)
    }
    const embJson = await embRes.json()
    const embedding = embJson?.data?.[0]?.embedding
    if (!embedding) return json({ error: 'embedding ausente na resposta' }, 500)

    // UPSERT
    const payload: any = {
      titulo:     titulo.trim(),
      categoria,
      conteudo:   conteudo.trim(),
      embedding,
      observacao: observacao ? String(observacao).trim() || null : null,
      ativo:      ativo !== false,
      updated_at: new Date().toISOString(),
    }

    if (id) {
      const { data, error } = await supabase
        .from('knowledge_chunks').update(payload).eq('id', id)
        .select('id, titulo, categoria').single()
      if (error) return json({ error: error.message }, 500)
      return json({ ok: true, id: data.id, action: 'updated' })
    } else {
      const { data, error } = await supabase
        .from('knowledge_chunks').insert(payload)
        .select('id, titulo, categoria').single()
      if (error) return json({ error: error.message }, 500)
      return json({ ok: true, id: data.id, action: 'created' })
    }

  } catch (err) {
    const msg = err instanceof Error ? err.message : 'erro desconhecido'
    return json({ error: msg }, 500)
  }
})

function json(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

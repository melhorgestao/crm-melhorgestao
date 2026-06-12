// ============================================================================
// buscar-conhecimento-agent
//
// Recebe { pergunta, categoria?, limit? }
// 1) Gera embedding via OpenAI text-embedding-3-small (lê chave de configuracoes)
// 2) Chama RPC buscar_conhecimento (cosine similarity, top-k)
// 3) Retorna { chunks: [...] }
// ============================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { pergunta, categoria = null, limit = 5 } = await req.json()

    if (!pergunta || typeof pergunta !== 'string') {
      return json({ error: 'pergunta (string) é obrigatória' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Lê chave OpenAI da configuracoes
    const { data: cfg } = await supabase
      .from('configuracoes')
      .select('valor')
      .eq('chave', 'openai_api_key')
      .maybeSingle()

    const openaiKey = cfg?.valor as string | undefined
    if (!openaiKey || openaiKey.trim() === '') {
      return json({ error: 'openai_api_key não configurada em configuracoes' }, 400)
    }

    // Gera embedding
    const embRes = await fetch('https://api.openai.com/v1/embeddings', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'text-embedding-3-small',
        input: pergunta,
      }),
    })

    if (!embRes.ok) {
      const t = await embRes.text()
      return json({ error: `OpenAI embedding falhou: ${embRes.status}`, details: t.slice(0, 200) }, 500)
    }

    const embJson = await embRes.json()
    const embedding = embJson?.data?.[0]?.embedding
    if (!embedding) return json({ error: 'embedding ausente na resposta OpenAI' }, 500)

    // Chama RPC
    const { data: chunks, error } = await supabase.rpc('buscar_conhecimento', {
      p_embedding: embedding,
      p_categoria: categoria,
      p_limit: limit,
    })

    if (error) return json({ error: error.message }, 500)

    return json({ chunks: chunks ?? [], usados: { categoria, limit } })

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

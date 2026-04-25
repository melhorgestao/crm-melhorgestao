const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { order_id, api_key } = await req.json()

    if (!api_key) {
      return new Response(JSON.stringify({ error: 'api_key obrigatório' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    if (!order_id) {
      return new Response(JSON.stringify({ error: 'order_id obrigatório' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    console.log('imprimir-etiqueta order_id:', order_id)

    // SuperFrete: GET /api/v0/order/info/{id} retorna { print: { url: '...' } } após pagar
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 15000)

    const res = await fetch(`https://api.superfrete.com/api/v0/order/info/${order_id}`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${api_key}`,
        'Accept': 'application/json',
        'User-Agent': 'CRM-Lovable-SuperFrete/1.0 (suporte@crm.local)',
      },
      signal: controller.signal,
    })
    clearTimeout(timeoutId)

    const ct = res.headers.get('content-type') || ''
    const data = ct.includes('json') ? await res.json() : { raw: await res.text() }

    if (!res.ok) {
      return new Response(JSON.stringify({ error: data?.error || data?.message || `HTTP ${res.status}`, details: data }), {
        status: res.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const printUrl = data?.print?.url || data?.print_url || data?.label || null
    const tracking = data?.tracking || data?.self_tracking || null
    const status = data?.status || null

    return new Response(JSON.stringify({ url: printUrl, tracking, status, raw: data }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    const msg = error instanceof Error ? error.message : 'Erro desconhecido'
    console.error('imprimir-etiqueta error:', error)
    return new Response(JSON.stringify({ error: msg }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

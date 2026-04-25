const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
}

const getErrorDetails = (error: unknown) => {
  if (error instanceof Error) {
    return { message: error.message, stack: error.stack }
  }
  return { message: 'Erro interno desconhecido', stack: undefined }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { order_id, api_key } = await req.json()

    if (!api_key || api_key.trim() === '') {
      return new Response(JSON.stringify({ error: 'API key não configurada' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    if (!order_id) {
      return new Response(JSON.stringify({ error: 'ID da etiqueta não fornecido' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    console.log('pagar-etiqueta - order_id:', order_id)

    const payload = { orders: [order_id] }

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 25000)

    const res = await fetch('https://api.superfrete.com/api/v0/checkout', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${api_key}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'CRM-Lovable-SuperFrete/1.0 (suporte@crm.local)',
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    })
    clearTimeout(timeoutId)

    const ct = res.headers.get('content-type') || ''
    const data = ct.includes('json') ? await res.json() : { raw: await res.text() }
    console.log('SuperFrete checkout response:', res.status, JSON.stringify(data))

    if (!res.ok) {
      const errorMsg = data.error || data.message || `Erro: ${res.status}`
      return new Response(JSON.stringify({ error: errorMsg, details: data }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: res.status,
      })
    }

    const orderResult = data?.purchase?.orders?.[0] || data?.orders?.[0] || data
    let tracking = orderResult?.tracking || orderResult?.self_tracking || orderResult?.tracking_code || ''
    const status = orderResult?.status || 'paid'

    // Polling: SuperFrete demora 1-5s pra popular tracking + print URL após o checkout.
    // Tentamos até 4x (~6s no total) — se não vier, o superfrete-sync popula depois.
    let printUrl: string | null = null
    const infoHeaders = {
      'Authorization': `Bearer ${api_key}`,
      'Accept': 'application/json',
      'User-Agent': 'CRM-Lovable-SuperFrete/1.0 (suporte@crm.local)',
    }

    for (let attempt = 0; attempt < 4; attempt++) {
      await sleep(attempt === 0 ? 800 : 1500)
      try {
        const infoRes = await fetch(`https://api.superfrete.com/api/v0/order/info/${order_id}`, { headers: infoHeaders })
        if (!infoRes.ok) continue
        const info = await infoRes.json()
        if (!printUrl) {
          printUrl = info?.print?.url || info?.print_url || null
          if (printUrl) console.log(`print URL obtida (attempt ${attempt + 1}):`, printUrl)
        }
        const t = info?.tracking || info?.self_tracking || info?.tracking_code || ''
        if (t && !tracking) {
          tracking = t
          console.log(`tracking obtido (attempt ${attempt + 1}):`, tracking)
        }
        // Se já temos os dois, sai do loop
        if (tracking && printUrl) break
      } catch (e) {
        console.warn(`order/info attempt ${attempt + 1} falhou:`, e)
      }
    }

    // NÃO usa order_id como fallback de tracking — codigo_rastreio só armazena rastreio real.
    // Se vazio, o superfrete-sync popula depois.

    return new Response(JSON.stringify({
      success: true,
      status,
      tracking,
      print_url: printUrl,
      data,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    const errorDetails = getErrorDetails(error)
    console.error('pagar-etiqueta error:', error)
    return new Response(JSON.stringify({
      error: errorDetails.message,
      stack: errorDetails.stack,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})

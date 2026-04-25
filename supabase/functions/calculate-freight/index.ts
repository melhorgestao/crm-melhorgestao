import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
}

const getErrorMessage = (error: unknown) => error instanceof Error ? error.message : 'Erro interno desconhecido'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { from_cep, to_cep, peso, largura, altura, comprimento, quantidade, services, api_key } = await req.json()

    if (!api_key || api_key.trim() === '') {
      return new Response(JSON.stringify({ error: 'API key não configurada. Configure a chave_api_superfrete no sistema.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    const payload = {
      from: { postal_code: from_cep },
      to: { postal_code: to_cep },
      services: services || '1,2',
      products: [{
        weight: peso / 1000,
        width: largura,
        height: altura,
        length: comprimento,
        quantity: quantidade || 1,
      }],
    }

    const res = await fetch('https://api.superfrete.com/api/v0/calculator', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${api_key}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify(payload),
    })

    if (!res.ok) {
      const errorText = await res.text()
      return new Response(JSON.stringify({ error: `SuperFrete API error: ${res.status}`, details: errorText }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: res.status,
      })
    }

    const text = await res.text()
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      return new Response(JSON.stringify({ error: 'Resposta inválida da SuperFrete', response: text }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      })
    }

    const item = Array.isArray(data) ? data[0] : data
    const discount = item?.discount ? (typeof item.discount === 'string' ? parseFloat(item.discount) : item.discount) : 0
    const priceWithDiscount = typeof item?.price === 'string' ? parseFloat(item.price) : item?.price || 0
    
    if (!priceWithDiscount) {
      return new Response(JSON.stringify({ error: 'Nenhum preço retornado pela SuperFrete', data }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      })
    }

    const price = priceWithDiscount + discount

    return new Response(JSON.stringify({ price, source: 'superfrete' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: getErrorMessage(error) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
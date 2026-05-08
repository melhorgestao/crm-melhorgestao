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
    const { from_cep, to_cep, peso, width, height, length, quantity, service, api_key } = await req.json()

    if (!api_key || api_key.trim() === '') {
      return new Response(JSON.stringify({ error: 'API key não configurada' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // O peso é enviado em GRAMAS - converter para KG
    const pesoKg = peso / 1000;
    
    // Arredondar para cima em intervalos de 0.5kg para ficar na faixa correta
    let faixaPeso = 0.3;
    if (pesoKg <= 0.3) faixaPeso = 0.3;
    else if (pesoKg <= 0.5) faixaPeso = 0.5;
    else if (pesoKg <= 1) faixaPeso = 1;
    else if (pesoKg <= 2) faixaPeso = 2;
    else if (pesoKg <= 5) faixaPeso = 5;
    else if (pesoKg <= 10) faixaPeso = 10;
    else if (pesoKg <= 15) faixaPeso = 15;
    else if (pesoKg <= 20) faixaPeso = 20;
    else faixaPeso = 30;

    console.log('Peso:', peso, 'g (',pesoKg.toFixed(2),'kg) -> faixa:', faixaPeso, 'kg');

    // SuperFrete service IDs oficiais: 1=PAC, 2=SEDEX, 17=Mini Envios
    const serviceNum = Number(service);
    const validServices = [1, 2, 17];
    const finalService = validServices.includes(serviceNum) ? serviceNum : 2;
    console.log('cotar-frete - service final:', finalService);

    const payload = {
      from: { postal_code: from_cep },
      to: { postal_code: to_cep },
      volumes: [{
        weight: faixaPeso,
        width: width || 11,
        height: height || 2,
        length: length || 16,
        quantity: quantity || 1,
      }],
      service: finalService,
    }

    const res = await fetch('https://api.superfrete.com/api/v0/rates', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${api_key}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'MelhorGestaoCRM/1.0 (contato@melhorgestao.online)',
      },
      body: JSON.stringify(payload),
    })

    if (!res.ok) {
      const errorText = await res.text()
      console.error('SuperFrete rates error:', res.status, errorText.substring(0, 500))
      return new Response(JSON.stringify({ error: `SuperFrete API error: ${res.status}`, details: errorText.substring(0, 200) }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: res.status,
      })
    }

    const data = await res.json()
    const item = Array.isArray(data) ? data[0] : data
    const discount = item?.discount ? (typeof item.discount === 'string' ? parseFloat(item.discount) : item.discount) : 0
    const priceWithDiscount = typeof item?.price === 'string' ? parseFloat(item.price) : item?.price || 0
    
    if (!priceWithDiscount) {
      return new Response(JSON.stringify({ error: 'Nenhum preço retornado', data }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      })
    }

    const price = priceWithDiscount + discount

    return new Response(JSON.stringify({ price, discount, original_price: priceWithDiscount, source: 'superfrete' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: getErrorMessage(error) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
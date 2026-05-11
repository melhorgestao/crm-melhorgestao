import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
}

const getErrorDetails = (error: unknown) => {
  if (error instanceof Error) {
    return {
      message: error.message,
      stack: error.stack,
    }
  }

  return {
    message: 'Erro interno desconhecido',
    stack: undefined,
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const {
      from_name, from_document, from_address, from_number, from_complement,
      from_district, from_city, from_state, from_cep, from_phone,
      to_name, to_document, to_address, to_number, to_complement,
      to_district, to_city, to_state, to_cep, to_phone,
      peso, width, height, length, service, api_key,
      valor_frete_cotado, products
    } = await req.json()

    console.log('gerar-etiqueta recebido - peso:', peso, 'valor_frete_cotado:', valor_frete_cotado)

    if (!api_key || api_key.trim() === '') {
      return new Response(JSON.stringify({ error: 'API key não configurada' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // Validar dados obrigatórios
    if (!from_cep || !to_cep || !from_name || !to_name) {
      return new Response(JSON.stringify({ error: 'Dados obrigatórios faltando', from_cep, to_cep, from_name, to_name }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // Limpar CEPs
    const fromCep = String(from_cep).replace(/\D/g, '');
    const toCep = String(to_cep).replace(/\D/g, '');

    if (fromCep.length < 8 || toCep.length < 8) {
      return new Response(JSON.stringify({ error: 'CEP inválido', fromCep, toCep }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // SuperFrete usa faixas de peso - converter gramas para KG
    const pesoKg = peso / 1000;
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

    console.log('gerar-etiqueta - service recebido:', service, 'tipo:', typeof service);

    // SuperFrete service IDs oficiais: 1=PAC, 2=SEDEX, 17=Mini Envios
    const serviceNum = Number(service);
    const validServices = [1, 2, 17];
    const finalService = validServices.includes(serviceNum) ? serviceNum : 2;
    console.log('gerar-etiqueta - service final enviado para SuperFrete:', finalService);

    const payload = {
      from: {
        name: from_name,
        document: from_document,
        address: from_address,
        ...(from_number && String(from_number).trim() !== '' ? { number: String(from_number).trim() } : {}),
        ...(from_complement && String(from_complement).trim() !== '' ? { complement: String(from_complement).trim() } : {}),
        district: from_district,
        city: from_city,
        state_abbr: from_state,
        postal_code: fromCep,
        phone: from_phone,
      },
      to: {
        name: to_name,
        document: to_document,
        address: to_address,
        // Envia number/complement somente quando tem valor.
        // Nunca enviar 'S/N': se nao houver numero ou complemento, omitimos o campo.
        ...(to_number && String(to_number).trim() !== '' ? { number: String(to_number).trim() } : {}),
        ...(to_complement && String(to_complement).trim() !== '' ? { complement: String(to_complement).trim() } : {}),
        district: to_district,
        city: to_city,
        state_abbr: to_state,
        postal_code: toCep,
        phone: to_phone,
      },
      volumes: [{
        weight: faixaPeso,
        width: width || 11,
        height: height || 2,
        length: length || 16,
        quantity: 1,
      }],
      options: {
        receipt: false,
        own_hand: false,
        insurance_value: 0,
        // DAC (Declaração Auxiliar de Conteúdo) — preenche descrição/qtd/valor na etiqueta
        ...(Array.isArray(products) && products.length > 0 ? { 
          platform: 'MelhorGestaoCRM',
          tags: [{ tag: 'crm', url: '' }],
        } : {}),
      },
      // SuperFrete usa "products" para preencher a DAC com nome/qtd/valor unitário
      products: Array.isArray(products) && products.length > 0 ? products.map((p: any) => ({
        name: String(p.name || p.nome || 'Produto'),
        quantity: String(p.quantity || p.quantidade || 1),
        unitary_value: String(p.unitary_value || p.valor_unitario || 0),
      })) : [{
        name: 'Produto',
        quantity: '1',
        unitary_value: '0',
      }],
      service: finalService,
    }

    console.log('Payload enviado:', JSON.stringify(payload))

    const res = await fetch('https://api.superfrete.com/api/v0/cart', {
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
      console.error('SuperFrete cart error:', errorText)
      return new Response(JSON.stringify({ error: `SuperFrete error: ${res.status}`, details: errorText }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: res.status,
      })
    }

    const data = await res.json()
    console.log('SuperFrete cart response:', data)

    // Tenta buscar o tracking real via /order/info — SuperFrete já emite o código de rastreio na geração
    let tracking = data.tracking || data.tracking_code || null;
    const orderId = data.id || data.order_id || null;

    if (!tracking && orderId) {
      try {
        const infoRes = await fetch(`https://api.superfrete.com/api/v0/order/info/${orderId}`, {
          headers: {
            'Authorization': `Bearer ${api_key}`,
            'Accept': 'application/json',
            'User-Agent': 'MelhorGestaoCRM/1.0 (contato@melhorgestao.online)',
          },
        });
        if (infoRes.ok) {
          const ct = infoRes.headers.get('content-type') || '';
          if (ct.includes('json')) {
            const info = await infoRes.json();
            tracking = info.tracking || info.tracking_code || null;
            console.log('order/info tracking:', tracking);
          }
        }
      } catch (e) {
        console.warn('Falha ao buscar tracking em order/info:', e);
      }
    }

    return new Response(JSON.stringify({ ...data, tracking }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    const errorDetails = getErrorDetails(error)
    console.error('gerar-etiqueta error:', error)
    return new Response(JSON.stringify({ 
      error: errorDetails.message,
      stack: errorDetails.stack,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
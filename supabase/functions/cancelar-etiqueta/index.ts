import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { order_id, api_key, reason } = await req.json();

    if (!api_key || api_key.trim() === '') {
      return new Response(JSON.stringify({ error: 'API key não configurada' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    if (!order_id) {
      return new Response(JSON.stringify({ error: 'ID da etiqueta não fornecido' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    console.log('cancelar-etiqueta - order_id:', order_id);

    // SuperFrete cancelamento: POST /api/v0/order/cancel
    // Funciona tanto antes quanto depois do pagamento
    // IMPORTANTE: order.description é OBRIGATÓRIO pela API
    const motivo = reason || 'Etiqueta gerada com endereço errado';
    const payload = {
      order: {
        id: order_id,
        reason_id: '2',
        description: motivo,
      },
    };

    console.log('cancelar-etiqueta - payload:', JSON.stringify(payload));

    // Timeout de 15s para não travar o frontend
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000);

    const res = await fetch('https://api.superfrete.com/api/v0/order/cancel', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${api_key}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'MelhorGestaoCRM/1.0 (contato@melhorgestao.online)',
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    const ct = res.headers.get('content-type') || '';
    const data = ct.includes('json') ? await res.json() : { raw: await res.text() };
    console.log('SuperFrete cancel response:', res.status, data);

    if (!res.ok) {
      // 404 / 422 / etc — devolvemos sucesso parcial para limpar localmente,
      // pois o usuário pediu "cancelar" e queremos UX consistente
      return new Response(JSON.stringify({
        success: false,
        cleared_locally: true,
        error: data?.error || data?.message || `SuperFrete error: ${res.status}`,
        details: data,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200, // 200 para o frontend conseguir limpar mesmo assim
      });
    }

    return new Response(JSON.stringify({ success: true, data }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('cancelar-etiqueta error:', error);
    return new Response(JSON.stringify({
      error: error instanceof Error ? error.message : 'Erro interno',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});

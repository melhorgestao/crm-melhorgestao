// ============================================================================
// consultar-frete-agent
//
// Recebe { to_cep, qtd_produtos?: number }
// 1) Obtém from_cep e peso_unitario via RPC obter_config_frete
// 2) Calcula peso total = peso_unitario * qtd_produtos
// 3) Chama Superfrete 3x em paralelo (PAC=1, SEDEX=2, Mini=17)
// 4) Retorna modalidades com valor + prazo
// ============================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SERVICOS = [
  { id: 1,  nome: 'PAC',         prazo_dias: 7 },
  { id: 2,  nome: 'SEDEX',       prazo_dias: 3 },
  { id: 17, nome: 'Mini Envios', prazo_dias: 10 },
]

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { to_cep, qtd_produtos = 1 } = await req.json()

    if (!to_cep || typeof to_cep !== 'string') {
      return json({ error: 'to_cep (string) é obrigatório' }, 400)
    }

    const cepClean = String(to_cep).replace(/\D/g, '')
    if (cepClean.length !== 8) {
      return json({ error: 'to_cep deve ter 8 dígitos' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Config de origem
    const { data: cfg, error: cfgErr } = await supabase.rpc('obter_config_frete', { p_to_cep: cepClean })
    if (cfgErr) return json({ error: 'obter_config_frete: ' + cfgErr.message }, 500)

    const fromCep        = cfg?.from_cep ?? '05010000'
    const pesoUnitario   = cfg?.peso_unitario_g ?? 300
    const qtd            = Math.max(1, Math.min(50, Number(qtd_produtos) || 1))
    const pesoTotal      = pesoUnitario * qtd

    // Chave Superfrete
    const { data: apiCfg } = await supabase
      .from('configuracoes')
      .select('valor')
      .eq('chave', 'chave_api_superfrete')
      .maybeSingle()

    const apiKey = apiCfg?.valor as string | undefined
    if (!apiKey || apiKey.trim() === '') {
      return json({ error: 'chave_api_superfrete não configurada' }, 400)
    }

    // Chama a edge cotar-frete existente para cada modalidade (em paralelo)
    const baseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!

    const results = await Promise.allSettled(SERVICOS.map(async (svc) => {
      const r = await fetch(`${baseUrl}/functions/v1/cotar-frete`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${anonKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from_cep: fromCep,
          to_cep:   cepClean,
          peso:     pesoTotal,
          width: 11, height: 2, length: 16, quantity: 1,
          service: svc.id,
          api_key: apiKey,
        }),
      })

      const data = await r.json().catch(() => ({}))
      return {
        nome:        svc.nome,
        valor_reais: typeof data?.price === 'number' ? Number(data.price.toFixed(2)) : null,
        prazo_dias:  svc.prazo_dias,
        erro:        !r.ok || data?.error ? (data?.error || `HTTP ${r.status}`) : null,
      }
    }))

    const modalidades = results.map((r, i) => {
      if (r.status === 'fulfilled') return r.value
      return {
        nome:        SERVICOS[i].nome,
        valor_reais: null,
        prazo_dias:  SERVICOS[i].prazo_dias,
        erro:        'falha rede',
      }
    })

    return json({
      from_cep:    fromCep,
      to_cep:      cepClean,
      qtd_produtos: qtd,
      peso_total_g: pesoTotal,
      modalidades,
    })

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

// ============================================================================
// consultar-frete-agent — chamada na SuperFrete /api/v0/calculator (endpoint correto).
//
// INPUT (POST): { to_cep: string, qtd_produtos?: number }
//
// FLUXO:
//   1) Lê from_cep (remetentes_uf) + peso (configuracoes) + api_key Superfrete
//   2) UMA chamada POST /api/v0/calculator com services="1,2" (PAC+SEDEX)
//   3) Mapeia o array de resposta → modalidades com preço + prazo (min/max)
//
// Resposta sempre 200 com modalidades[] e debug{}.
//
// NOTA: /api/v0/rates (usado antes) NÃO existe — retornava HTML da SPA.
//       Endpoint correto de cálculo é /api/v0/calculator (igual etiqueta).
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Apenas PAC (1) e SEDEX (2). Mini Envios (17) removido por regra do negócio.
const SERVICOS_IDS = '1,2'
const SERVICO_NOME: Record<number, string> = { 1: 'PAC', 2: 'SEDEX' }
const PRAZO_DEFAULT: Record<number, number> = { 1: 7, 2: 3 }

// Caixa P padrão (peso até 1kg)
const DIM_DEFAULT = { width: 11, height: 2, length: 16 }
const TIMEOUT_MS  = 15000

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const debug: Record<string, any> = {}

  try {
    const { to_cep, qtd_produtos = 1 } = await req.json()

    if (!to_cep || typeof to_cep !== 'string') {
      return j({ ok: false, error: 'to_cep (string) é obrigatório' }, 400)
    }

    const cepClean = String(to_cep).replace(/\D/g, '')
    if (cepClean.length !== 8) {
      return j({ ok: false, error: 'to_cep deve ter 8 dígitos', recebido: to_cep }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ---- config em paralelo ----
    const [cfgRes, apiCfgRes] = await Promise.all([
      supabase.rpc('obter_config_frete', { p_to_cep: cepClean }),
      supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').maybeSingle(),
    ])

    if (cfgRes.error) return j({ ok: false, error: 'obter_config_frete: ' + cfgRes.error.message }, 500)

    const cfg = cfgRes.data as any
    const fromCep      = String(cfg?.from_cep ?? '92035575').replace(/\D/g, '')
    const pesoUnitario = cfg?.peso_unitario_g ?? 300
    const qtd          = Math.max(1, Math.min(50, Number(qtd_produtos) || 1))
    const pesoTotalG   = pesoUnitario * qtd
    const pesoKg       = Math.max(0.3, pesoTotalG / 1000)

    const apiKey = (apiCfgRes.data?.valor as string | undefined)?.trim()
    if (!apiKey) return j({
      ok: false, error: 'chave_api_superfrete não configurada em configuracoes',
    }, 400)

    debug.from_cep = fromCep
    debug.to_cep = cepClean
    debug.peso_unitario_g = pesoUnitario
    debug.qtd_produtos = qtd
    debug.peso_total_g = pesoTotalG
    debug.peso_kg = pesoKg

    // ---- UMA chamada no endpoint correto /api/v0/calculator ----
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS)
    let arr: any[] = []
    try {
      const payload = {
        from: { postal_code: fromCep },
        to:   { postal_code: cepClean },
        services: SERVICOS_IDS,
        products: [{
          weight:   pesoKg,
          width:    DIM_DEFAULT.width,
          height:   DIM_DEFAULT.height,
          length:   DIM_DEFAULT.length,
          quantity: 1,
        }],
      }
      const r = await fetch('https://api.superfrete.com/api/v0/calculator', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type':  'application/json',
          'Accept':        'application/json',
          'User-Agent':    'MelhorGestaoCRM/1.0 (contato@melhorgestao.online)',
        },
        body: JSON.stringify(payload),
        signal: ctrl.signal,
      })
      const txt = await r.text()
      debug.http_status = r.status
      let data: any = null
      try { data = JSON.parse(txt) }
      catch { return j({ ok: false, error: 'superfrete_parse', body_preview: txt.slice(0, 300), debug }, 502) }
      if (!r.ok) return j({ ok: false, error: `superfrete HTTP ${r.status}`, body_preview: JSON.stringify(data).slice(0, 300), debug }, 502)
      arr = Array.isArray(data) ? data : [data]
    } catch (e) {
      return j({ ok: false, error: 'superfrete_fetch: ' + (e instanceof Error ? e.message : String(e)), debug }, 502)
    } finally { clearTimeout(timer) }

    // ---- mapeia array → modalidades (só PAC e SEDEX, na ordem) ----
    const modalidades = [1, 2].map(svcId => {
      const item = arr.find((x: any) => Number(x?.id) === svcId)
      const nome = SERVICO_NOME[svcId]
      if (!item || item?.error) {
        return {
          nome, valor_reais: null, preco: null,
          prazo_dias: PRAZO_DEFAULT[svcId], prazo_min: PRAZO_DEFAULT[svcId], prazo_max: PRAZO_DEFAULT[svcId],
          erro: item?.error || 'serviço indisponível',
        }
      }
      // price + discount = preço cheio (convenção etiqueta)
      const priceWithDiscount = typeof item.price === 'string' ? parseFloat(item.price) : Number(item.price)
      const discount = typeof item.discount === 'string' ? parseFloat(item.discount) : Number(item.discount || 0)
      const price = (priceWithDiscount || 0) + (discount || 0)
      if (!price || price <= 0) {
        return {
          nome, valor_reais: null, preco: null,
          prazo_dias: PRAZO_DEFAULT[svcId], prazo_min: PRAZO_DEFAULT[svcId], prazo_max: PRAZO_DEFAULT[svcId],
          erro: 'preço não retornado',
        }
      }
      const dTime = item?.delivery_time != null ? Number(item.delivery_time) : PRAZO_DEFAULT[svcId]
      const pMin  = item?.delivery_range?.min != null ? Number(item.delivery_range.min) : dTime
      const pMax  = item?.delivery_range?.max != null ? Number(item.delivery_range.max) : dTime
      const valor = Number(price.toFixed(2))
      return {
        nome,
        valor_reais: valor,
        preco:       valor,
        prazo_dias:  dTime,
        prazo_min:   pMin,
        prazo_max:   pMax,
        erro:        null,
      }
    })

    const algumOk = modalidades.some(m => m.valor_reais !== null)

    return j({
      ok: algumOk,
      from_cep: fromCep,
      to_cep: cepClean,
      qtd_produtos: qtd,
      peso_total_g: pesoTotalG,
      modalidades,
      debug,
    })

  } catch (err) {
    const msg = err instanceof Error ? err.message : 'erro desconhecido'
    return j({ ok: false, error: msg, debug }, 500)
  }
})

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

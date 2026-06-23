// ============================================================================
// consultar-frete-agent — chamada DIRETA na Superfrete (sem hops intermediários)
//
// INPUT (POST): { to_cep: string, qtd_produtos?: number }
//
// FLUXO:
//   1) Lê from_cep (remetentes_uf) + peso (configuracoes) + api_key Superfrete
//   2) 2 fetches paralelos /api/v0/rates: PAC (service 1) e SEDEX (service 2)
//      (Mini Envios REMOVIDO da resposta ao lead)
//   3) Normaliza preço + prazo e retorna
//
// Resposta sempre 200 (mesmo com erro) com modalidades[] e debug{} pra agent
// poder decidir o que fazer.
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Apenas PAC e SEDEX (Mini Envios removido por regra do negócio)
const SERVICOS = [
  { id: 1, nome: 'PAC',   prazo_default: 7 },
  { id: 2, nome: 'SEDEX', prazo_default: 3 },
]

// Caixa P padrão (peso até 1kg)
const DIM_DEFAULT = { width: 11, height: 2, length: 16 }
const TIMEOUT_MS  = 12000

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
    const fromCep      = cfg?.from_cep ?? '05010000'
    const pesoUnitario = cfg?.peso_unitario_g ?? 300
    const qtd          = Math.max(1, Math.min(50, Number(qtd_produtos) || 1))
    const pesoTotalG   = pesoUnitario * qtd
    const faixaKg      = faixaPesoKg(pesoTotalG)

    const apiKey = (apiCfgRes.data?.valor as string | undefined)?.trim()
    if (!apiKey) return j({
      ok: false, error: 'chave_api_superfrete não configurada em configuracoes',
    }, 400)

    debug.from_cep = fromCep
    debug.to_cep = cepClean
    debug.peso_unitario_g = pesoUnitario
    debug.qtd_produtos = qtd
    debug.peso_total_g = pesoTotalG
    debug.faixa_kg = faixaKg

    // ---- chama Superfrete: PAC + SEDEX em paralelo ----
    const results = await Promise.allSettled(
      SERVICOS.map(svc => chamarSuperfrete({
        from_cep: fromCep, to_cep: cepClean,
        faixa_kg: faixaKg, service: svc.id, api_key: apiKey,
      }))
    )

    const modalidades = results.map((r, i) => {
      const svc = SERVICOS[i]
      if (r.status === 'fulfilled' && r.value.ok) {
        const pMin = r.value.prazo_min ?? r.value.delivery_time ?? svc.prazo_default
        const pMax = r.value.prazo_max ?? r.value.delivery_time ?? svc.prazo_default
        return {
          nome:        svc.nome,
          valor_reais: r.value.price,
          preco:       r.value.price,          // alias p/ calcular-pedido
          prazo_dias:  r.value.delivery_time ?? pMax,
          prazo_min:   pMin,
          prazo_max:   pMax,
          erro:        null,
        }
      }
      const err = r.status === 'fulfilled' ? r.value.error : (r as any).reason?.message || 'rejected'
      return {
        nome: svc.nome, valor_reais: null, preco: null,
        prazo_dias: svc.prazo_default, prazo_min: svc.prazo_default, prazo_max: svc.prazo_default,
        erro: err,
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

interface SuperfreteRes {
  ok: boolean
  price?: number
  delivery_time?: number
  prazo_min?: number
  prazo_max?: number
  error?: string
}

async function chamarSuperfrete(args: {
  from_cep: string; to_cep: string; faixa_kg: number;
  service: number; api_key: string;
}): Promise<SuperfreteRes> {
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS)
  try {
    const payload = {
      from: { postal_code: args.from_cep },
      to:   { postal_code: args.to_cep },
      volumes: [{
        weight: args.faixa_kg,
        width:  DIM_DEFAULT.width,
        height: DIM_DEFAULT.height,
        length: DIM_DEFAULT.length,
        quantity: 1,
      }],
      service: args.service,
    }
    const r = await fetch('https://api.superfrete.com/api/v0/rates', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${args.api_key}`,
        'Content-Type':  'application/json',
        'Accept':        'application/json',
        'User-Agent':    'MelhorGestaoCRM/1.0 (contato@melhorgestao.online)',
      },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    })
    const txt = await r.text()
    let data: any = null
    try { data = JSON.parse(txt) } catch { return { ok: false, error: `parse: ${txt.slice(0,200)}` } }
    if (!r.ok) return { ok: false, error: `HTTP ${r.status}: ${(data?.error || txt).toString().slice(0, 200)}` }

    // SuperFrete retorna ARRAY. Acha o serviço pedido por id (1=PAC, 2=SEDEX),
    // fallback pro 1º que tiver preço válido.
    const arr = Array.isArray(data) ? data : [data]
    let item = arr.find((x: any) => Number(x?.id) === Number(args.service) && !x?.error)
    if (!item) item = arr.find((x: any) => !x?.error && x?.price != null)
    if (!item) return { ok: false, error: arr[0]?.error || 'resposta vazia' }

    // Preço cheio (Correios) = price + discount. Mesma convenção do fluxo de
    // etiqueta (cotar-frete): cobra-se o cheio, desconto SuperFrete é margem.
    const priceWithDiscount = typeof item.price === 'string' ? parseFloat(item.price) : Number(item.price)
    const discount = typeof item.discount === 'string' ? parseFloat(item.discount) : Number(item.discount || 0)
    const price = (priceWithDiscount || 0) + (discount || 0)
    if (!price || price <= 0) {
      return { ok: false, error: item?.error || 'preço não retornado' }
    }

    const delivery_time = item?.delivery_time != null ? Number(item.delivery_time) : undefined
    const prazo_min = item?.delivery_range?.min != null ? Number(item.delivery_range.min) : delivery_time
    const prazo_max = item?.delivery_range?.max != null ? Number(item.delivery_range.max) : delivery_time
    return { ok: true, price: Number(price.toFixed(2)), delivery_time, prazo_min, prazo_max }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  } finally { clearTimeout(timer) }
}

function faixaPesoKg(pesoG: number): number {
  const kg = pesoG / 1000
  if (kg <= 0.3) return 0.3
  if (kg <= 0.5) return 0.5
  if (kg <= 1)   return 1
  if (kg <= 2)   return 2
  if (kg <= 5)   return 5
  if (kg <= 10)  return 10
  if (kg <= 15)  return 15
  if (kg <= 20)  return 20
  return 30
}

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

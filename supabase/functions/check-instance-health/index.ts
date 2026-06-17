// ============================================================================
// check-instance-health — varre instâncias ativas e checa conexão Evolution.
//
// Pra cada instância com status='ativo' e ativo=true:
//   1) GET {evolution_url}/instance/connectionState/{evolution_instance}
//   2) Se NÃO estiver 'open' (state da Evolution), pausa via RPC pausar_instancia
//      - 'close' / 'connecting' → motivo='desconectado_evolution', 6h
//      - 401/403 (apikey inválida ou ban suspeito) → motivo='banido_suspeito', 24h
//      - timeout/erro de rede → não faz nada (pode ser falha momentânea)
//
// Roda em pg_cron a cada 5 minutos.
// Também pode ser chamado manualmente pra um id específico via ?id=<uuid>.
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const url = new URL(req.url)
  const onlyId = url.searchParams.get('id')

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    let q = supabase.from('instancias')
      .select('id,evolution_url,evolution_apikey,evolution_instance,status')
      .eq('ativo', true)
    if (onlyId) q = q.eq('id', onlyId)
    else        q = q.eq('status', 'ativo')

    const { data: instancias, error } = await q
    if (error) return j({ ok: false, error: error.message }, 500)

    const resultados: any[] = []

    for (const inst of (instancias || [])) {
      if (!inst.evolution_url || !inst.evolution_instance || !inst.evolution_apikey) {
        resultados.push({ id: inst.id, name: inst.evolution_instance, skipped: 'config_incompleta' })
        continue
      }

      const u = `${inst.evolution_url.replace(/\/+$/, '')}/instance/connectionState/${encodeURIComponent(inst.evolution_instance)}`
      let state = ''
      let httpStatus = 0
      let acao: 'nenhuma' | 'pausar' | 'banir_suspeito' = 'nenhuma'

      try {
        const ctrl = new AbortController()
        const timer = setTimeout(() => ctrl.abort(), 10000)
        const r = await fetch(u, {
          headers: { 'apikey': inst.evolution_apikey, 'Content-Type': 'application/json' },
          signal: ctrl.signal,
        })
        clearTimeout(timer)
        httpStatus = r.status
        if (r.status === 401 || r.status === 403) {
          acao = 'banir_suspeito'
        } else if (r.ok) {
          const j2 = await r.json().catch(() => ({}))
          state = j2?.instance?.state || j2?.state || ''
          if (state && state !== 'open') acao = 'pausar'
        } else {
          // 4xx/5xx genérico — pula
          resultados.push({ id: inst.id, name: inst.evolution_instance, http: r.status, skipped: 'http_erro' })
          continue
        }
      } catch (e) {
        resultados.push({ id: inst.id, name: inst.evolution_instance, skipped: 'network_error', err: e instanceof Error ? e.message : String(e) })
        continue
      }

      if (acao === 'pausar') {
        await supabase.rpc('pausar_instancia', {
          p_id: inst.id,
          p_motivo: `desconectado_evolution:${state}`,
          p_horas: 6,
        })
        resultados.push({ id: inst.id, name: inst.evolution_instance, state, action: 'paused_6h' })
      } else if (acao === 'banir_suspeito') {
        await supabase.rpc('pausar_instancia', {
          p_id: inst.id,
          p_motivo: `banido_suspeito_http_${httpStatus}`,
          p_horas: 24,
        })
        resultados.push({ id: inst.id, name: inst.evolution_instance, http: httpStatus, action: 'banned_suspect_24h' })
      } else {
        resultados.push({ id: inst.id, name: inst.evolution_instance, state, action: 'ok' })
      }
    }

    return j({ ok: true, checadas: resultados.length, resultados })

  } catch (err) {
    return j({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500)
  }
})

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

// ============================================================================
// check-instance-health — varre instâncias e mantém status sincronizado com Evolution.
//
// LÓGICA NOVA (resolve falso-positivo + falta de reativação):
//   • state='open'                  → health_check_marcar_ok (zera strikes,
//                                      REATIVA se estava 'desconectado'/'banido')
//   • state='close'/'closed'/'connecting' (transitório!) → health_check_strike
//                                      (incrementa contador; só pausa no 3º strike)
//   • timeout/network                → ignora (não conta como strike)
//   • 401/403 (apikey suspeita)      → ignora (NÃO pausa mais; era falso-positivo)
//   • pausado_admin                  → nunca mexe
//
// Resultado:
//   - Instabilidades transitórias (Evolution reconectando) NÃO pausam mais.
//   - Quando Evolution volta a 'open', CRM reativa AUTOMATICAMENTE.
//   - Só pausa quando Evolution está REALMENTE caído por 15min seguidos
//     (3 strikes × 5min cron).
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const HTTP_TIMEOUT_MS = 10000
const PAUSA_HORAS_APOS_STRIKES = 2

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const url = new URL(req.url)
  const onlyId = url.searchParams.get('id')

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Inclui instâncias pausadas (pra reativar quando voltam) — exceto pausado_admin
    let q = supabase.from('instancias')
      .select('id,evolution_url,evolution_apikey,evolution_instance,status')
      .eq('ativo', true)
      .neq('status', 'pausado_admin')
    if (onlyId) q = q.eq('id', onlyId)

    const { data: instancias, error } = await q
    if (error) return j({ ok: false, error: error.message }, 500)

    const resultados: any[] = []

    for (const inst of (instancias || [])) {
      if (!inst.evolution_url || !inst.evolution_instance || !inst.evolution_apikey) {
        resultados.push({ id: inst.id, name: inst.evolution_instance, skipped: 'config_incompleta' })
        continue
      }

      const reqUrl = `${inst.evolution_url.replace(/\/+$/, '')}/instance/connectionState/${encodeURIComponent(inst.evolution_instance)}`
      let state = ''
      let httpStatus = 0

      try {
        const ctrl = new AbortController()
        const timer = setTimeout(() => ctrl.abort(), HTTP_TIMEOUT_MS)
        const r = await fetch(reqUrl, {
          headers: { 'apikey': inst.evolution_apikey, 'Content-Type': 'application/json' },
          signal: ctrl.signal,
        })
        clearTimeout(timer)
        httpStatus = r.status

        if (r.status === 401 || r.status === 403) {
          // NÃO conta como strike — apikey errada/expirada não é ban.
          resultados.push({ id: inst.id, name: inst.evolution_instance, http: r.status, skipped: 'auth_error' })
          continue
        }

        if (!r.ok) {
          resultados.push({ id: inst.id, name: inst.evolution_instance, http: r.status, skipped: 'http_erro' })
          continue
        }

        const data = await r.json().catch(() => ({}))
        state = (data?.instance?.state || data?.state || '').toString().toLowerCase()
      } catch (e) {
        // timeout/network → não conta strike
        resultados.push({ id: inst.id, name: inst.evolution_instance, skipped: 'network_error', err: e instanceof Error ? e.message : String(e) })
        continue
      }

      // STATE = 'open' → marca ok (reativa se necessário)
      if (state === 'open') {
        const { data } = await supabase.rpc('health_check_marcar_ok', { p_id: inst.id })
        resultados.push({ id: inst.id, name: inst.evolution_instance, state, action: (data as any)?.action })
        continue
      }

      // STATE != 'open' (close, connecting, etc) → strike
      const { data } = await supabase.rpc('health_check_strike', {
        p_id: inst.id, p_state: state || 'unknown', p_horas: PAUSA_HORAS_APOS_STRIKES,
      })
      resultados.push({
        id: inst.id, name: inst.evolution_instance, state,
        action: (data as any)?.action, strikes: (data as any)?.strikes,
      })
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

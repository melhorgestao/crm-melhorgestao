import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';

/**
 * Sincroniza rastreio + status de pedidos com a SuperFrete.
 * Roda GLOBAL (montado no AppLayout) — independente da página aberta.
 *
 * - Primeiro disparo ~5s após login (pega rastreios que acabaram de ficar prontos).
 * - Depois a cada 5 minutos.
 * - Re-sync quando a aba volta ao foco.
 */
export function useTrackingAutomation() {
  const [isSyncing, setIsSyncing] = useState(false);
  const lastRunRef = useRef<number>(0);

  const syncTracking = useCallback(async () => {
    // Throttle: nunca rodar 2x em menos de 30s
    const now = Date.now();
    if (now - lastRunRef.current < 30_000) return;
    lastRunRef.current = now;

    setIsSyncing(true);
    try {
      const { data, error } = await supabase.functions.invoke('superfrete-sync', { body: {} });
      if (error) {
        console.error('[superfrete-sync] erro:', error);
      } else if (data?.updated > 0) {
        console.log(`[superfrete-sync] ${data.updated}/${data.checked} pedido(s) atualizado(s)`);
      } else {
        console.log(`[superfrete-sync] ${data?.checked ?? 0} verificado(s), sem mudança`);
      }
    } catch (e) {
      console.error('[superfrete-sync] exceção:', e);
    } finally {
      setIsSyncing(false);
    }
  }, []);

  useEffect(() => {
    const interval = setInterval(syncTracking, 5 * 60 * 1000);
    const timeout = setTimeout(syncTracking, 5000);

    const onVisible = () => {
      if (document.visibilityState === 'visible') syncTracking();
    };
    document.addEventListener('visibilitychange', onVisible);

    return () => {
      clearInterval(interval);
      clearTimeout(timeout);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [syncTracking]);

  return { isSyncing, syncTracking };
}

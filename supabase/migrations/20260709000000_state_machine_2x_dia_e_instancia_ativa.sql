-- ============================================================================
-- Ajustes no cron state-machine-transicoes:
--
-- 1) Frequência: 1x → 2x por dia (00:00 e 12:00 BRT)
--    Cron expression UTC: '0 3,15 * * *' (BRT = UTC-3)
--
-- 2) Filtro de instância ativa: TODOS os UPDATEs só processam contatos cuja
--    instância está conectada E ativa. Quando uma instância está banida/
--    desconectada, os contatos dela NÃO recebem transição automática —
--    evita penalizar leads por falha operacional do número.
--    Critério: instancias.status = 'ativo' AND instancias.ativo = true.
--
-- 3) Bloco RMKT: timeout de 3d → 24h (medido pela permanência no estado,
--    que é data_ultimo_rmkt — set no momento do disparo = entrada no estado).
--    Bloco FOLLOW_UP mantém 24h por entrada no estado (data_ultimo_follow_up).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.processar_transicoes_estado_contato()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ativacao_nunca_mais   INTEGER := 0;
  v_start_timeout         INTEGER := 0;
  v_follow_up_timeout     INTEGER := 0;
  v_wait_expirado         INTEGER := 0;
  v_em_fechamento_timeout INTEGER := 0;
  v_em_fechamento_pago    INTEGER := 0;
  v_rmkt_timeout          INTEGER := 0;
  v_suporte_timeout       INTEGER := 0;
BEGIN
  -- Critério reutilizável: instância existe, está ativa e conectada.
  -- Predicate inline com EXISTS pra deixar explícito em cada UPDATE.

  -- 1) Ativação esgotada → NUNCA_MAIS
  UPDATE public.contatos c
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'ativacao_contatos'
    AND c.ativacao_tentativas >= 3
    AND c.data_ultimo_ativacao < NOW() - INTERVAL '3 days'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_ativacao_nunca_mais = ROW_COUNT;

  -- 2) Start sem resposta 24h → wait_follow_up / cliente / suporte
  UPDATE public.contatos c
  SET ultima_interacao = CASE
        WHEN c.ja_comprou THEN 'cliente'
        WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up'
      END,
      suporte_motivo = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'rep_start_timeout' ELSE c.suporte_motivo END,
      data_suporte   = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN NOW() ELSE c.data_suporte END,
      data_wait_follow_up = CASE WHEN NOT c.ja_comprou AND c.canal_atual NOT IN ('REP', 'C-REP') THEN NOW() ELSE c.data_wait_follow_up END,
      updated_at = NOW()
  WHERE c.ultima_interacao = 'start'
    AND c.data_start < NOW() - INTERVAL '24 hours'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_start_timeout = ROW_COUNT;

  -- 3) Follow_up sem resposta 24h (permanência no estado) → wait_follow_up
  --    data_ultimo_follow_up é setado no momento do disparo da campanha follow_up,
  --    que coincide com a entrada no estado 'follow_up'.
  UPDATE public.contatos c
  SET ultima_interacao = 'wait_follow_up', data_wait_follow_up = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'follow_up'
    AND c.data_ultimo_follow_up < NOW() - INTERVAL '24 hours'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) Wait_follow_up esgotou 3 tentativas → NUNCA_MAIS
  UPDATE public.contatos c
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'wait_follow_up'
    AND c.follow_up_tentativas >= 3
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 5a) em_fechamento + ja_comprou → cliente IMEDIATO
  UPDATE public.contatos c
  SET ultima_interacao   = 'cliente',
      data_em_fechamento = NULL,
      ja_comprou         = true,
      primeira_venda_em  = COALESCE(c.primeira_venda_em,
                                    (SELECT MIN(created_at) FROM public.pedidos p
                                      WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'),
                                    NOW()),
      ultima_venda_em    = COALESCE(c.ultima_venda_em,
                                    (SELECT MAX(created_at) FROM public.pedidos p
                                      WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'),
                                    NOW()),
      updated_at         = NOW()
  WHERE c.ultima_interacao = 'em_fechamento'
    AND (c.ja_comprou = true
         OR EXISTS (SELECT 1 FROM public.pedidos p
                     WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'))
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_em_fechamento_pago = ROW_COUNT;

  -- 5b) em_fechamento 48h sem venda → wait_follow_up / cliente / suporte
  UPDATE public.contatos c
  SET ultima_interacao = CASE
        WHEN c.ja_comprou THEN 'cliente'
        WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE
        WHEN NOT c.ja_comprou AND c.canal_atual NOT IN ('REP', 'C-REP') THEN NOW()
        ELSE c.data_wait_follow_up END,
      data_em_fechamento = NULL,
      updated_at = NOW()
  WHERE c.ultima_interacao = 'em_fechamento'
    AND c.data_em_fechamento < NOW() - INTERVAL '48 hours'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  -- 6) RMKT: 24h de permanência no estado → cliente
  --    data_ultimo_rmkt é setado no disparo do RMKT, que coincide com a
  --    entrada no estado 'rmkt'. Mudança: 3d → 24h.
  --    Contador rmkt_consecutive_silenciosos NÃO é incrementado aqui
  --    (já foi incrementado no CLAIM do disparo).
  UPDATE public.contatos c
  SET ultima_interacao = 'cliente',
      updated_at = NOW()
  WHERE c.ultima_interacao = 'rmkt'
    AND c.data_ultimo_rmkt < NOW() - INTERVAL '24 hours'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

  -- 7) Suporte 48h sem ação → estado anterior (cliente ou wait_follow_up)
  UPDATE public.contatos c
  SET ultima_interacao = CASE WHEN c.ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE WHEN NOT c.ja_comprou THEN NOW() ELSE c.data_wait_follow_up END,
      estado_antes_suporte = NULL, data_suporte = NULL, suporte_motivo = NULL,
      updated_at = NOW()
  WHERE c.ultima_interacao = 'suporte'
    AND c.data_suporte < NOW() - INTERVAL '48 hours'
    AND c.canal_atual NOT IN ('REP', 'C-REP')
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_suporte_timeout = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'ativacao_nunca_mais', v_ativacao_nunca_mais,
    'start_timeout', v_start_timeout,
    'follow_up_timeout', v_follow_up_timeout,
    'wait_expirado', v_wait_expirado,
    'em_fechamento_pago_imediato', v_em_fechamento_pago,
    'em_fechamento_timeout', v_em_fechamento_timeout,
    'rmkt_timeout', v_rmkt_timeout,
    'suporte_timeout', v_suporte_timeout
  );
END $$;

GRANT EXECUTE ON FUNCTION public.processar_transicoes_estado_contato()
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- Reagenda o cron pra 2x ao dia (00:00 e 12:00 BRT = 03:00 e 15:00 UTC)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'state-machine-transicoes') THEN
    PERFORM cron.unschedule('state-machine-transicoes');
  END IF;

  PERFORM cron.schedule(
    'state-machine-transicoes',
    '0 3,15 * * *',
    $cmd$ SELECT public.processar_transicoes_estado_contato() $cmd$
  );
END $$;

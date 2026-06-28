-- ============================================================================
-- Ajustes adicionais no cron state-machine-transicoes:
--
-- 1) Reforça filtro de instância ativa em TODOS os UPDATEs (idempotente —
--    se a migration anterior 20260709 não foi aplicada ainda, esta garante).
--
-- 2) Bloqueia REP e C-REP de transitar pra estados de campanha lead
--    (wait_follow_up, follow_up). Contatos com canal_atual='REP' ou 'C-REP'
--    são representantes ou clientes-via-representante — NÃO devem receber
--    campanhas automáticas de lead. Eles vão pra 'suporte' quando o estado
--    de origem expira (já era assim para 'start' e 'em_fechamento'; agora
--    também para 'follow_up' → o cron ignora se for REP, em vez de derrubar
--    pra wait_follow_up).
--
-- 3) Mantém timeouts: 24h (start, follow_up, rmkt) / 48h (em_fechamento,
--    suporte) / 3d com 3 tentativas (ativacao).
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
  --    REP e C-REP já caíam pra 'suporte' aqui — comportamento mantido.
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

  -- 3) follow_up sem resposta 24h (permanência no estado) → wait_follow_up
  --    REP/C-REP fica parado em follow_up; NÃO volta pra wait_follow_up
  --    (não devem receber campanha de lead).
  UPDATE public.contatos c
  SET ultima_interacao = 'wait_follow_up', data_wait_follow_up = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'follow_up'
    AND c.data_ultimo_follow_up < NOW() - INTERVAL '24 hours'
    AND c.canal_atual NOT IN ('REP', 'C-REP')
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) wait_follow_up esgotou 3 tentativas → NUNCA_MAIS
  --    REP/C-REP nem deveriam estar aqui — protege caso histórico residual.
  UPDATE public.contatos c
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'wait_follow_up'
    AND c.follow_up_tentativas >= 3
    AND c.canal_atual NOT IN ('REP', 'C-REP')
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
  --     REP/C-REP cai pra 'suporte' — não recebe campanha de lead.
  UPDATE public.contatos c
  SET ultima_interacao = CASE
        WHEN c.ja_comprou THEN 'cliente'
        WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up' END,
      suporte_motivo = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'rep_fechamento_timeout' ELSE c.suporte_motivo END,
      data_suporte   = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN NOW() ELSE c.data_suporte END,
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

  -- 6) RMKT 24h de permanência no estado → cliente
  UPDATE public.contatos c
  SET ultima_interacao = 'cliente',
      updated_at = NOW()
  WHERE c.ultima_interacao = 'rmkt'
    AND c.data_ultimo_rmkt < NOW() - INTERVAL '24 hours'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

  -- 7) Suporte 48h sem ação → estado anterior (cliente ou wait_follow_up)
  --    REP/C-REP NÃO sai automaticamente do suporte — fica até atendente
  --    finalizar manualmente.
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
-- Tira REPs/C-REPs que estão presos em wait_follow_up ou follow_up agora
-- (faxina dos contatos que sofreram com o bug — ex: Snoop, Play Muscle).
-- Move pra 'suporte' com motivo claro, atendente decide.
-- ----------------------------------------------------------------------------
UPDATE public.contatos
   SET ultima_interacao = 'suporte',
       data_suporte = NOW(),
       suporte_motivo = COALESCE(suporte_motivo, 'rep_em_estado_lead'),
       data_wait_follow_up = NULL,
       data_ultimo_follow_up = NULL,
       updated_at = NOW()
 WHERE ultima_interacao IN ('wait_follow_up', 'follow_up')
   AND canal_atual IN ('REP', 'C-REP');

-- ----------------------------------------------------------------------------
-- Mantém schedule 2x/dia (00:00 e 12:00 BRT). Idempotente: re-schedule
-- não muda nada se já estava em '0 3,15 * * *'.
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

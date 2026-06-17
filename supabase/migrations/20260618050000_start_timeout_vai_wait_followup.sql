-- ============================================================================
-- Ajusta cron: 'start' parado 24h → wait_follow_up (sempre, exceto REP/C-REP)
--
-- Regra anterior jogava BASE/SCRAP em 'ativacao_contatos', mas isso conflita
-- com a regra de estado: ativacao_contatos é EXCLUSIVO de leads que JAMAIS
-- interagiram e receberam disparo de campanha. Quem mandou "oi" e sumiu deve
-- ficar como wait_follow_up (lead engajou e parou, candidato a follow-up).
--
-- Mantém REP/C-REP → suporte (rep precisa atendimento humano por padrão).
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
  v_rmkt_timeout          INTEGER := 0;
  v_suporte_timeout       INTEGER := 0;
BEGIN
  -- 1) ativacao_contatos com 3+ tentativas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS',
      data_nunca_mais  = NOW(),
      updated_at       = NOW()
  WHERE ultima_interacao = 'ativacao_contatos'
    AND ativacao_tentativas >= 3
    AND data_ultimo_ativacao < NOW() - INTERVAL '3 days';
  GET DIAGNOSTICS v_ativacao_nunca_mais = ROW_COUNT;

  -- 2) start 24h sem interação → wait_follow_up
  --    Exceção: REP/C-REP → suporte (rep precisa atendimento humano)
  --    Lead que mandou "oi" e sumiu vira candidato a follow-up automático.
  --    NÃO joga em ativacao_contatos (esse estado é EXCLUSIVO de campanha).
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up'
      END,
      suporte_motivo = CASE
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'rep_start_timeout'
        ELSE suporte_motivo
      END,
      data_suporte = CASE
        WHEN canal_atual IN ('REP', 'C-REP') THEN NOW()
        ELSE data_suporte
      END,
      data_wait_follow_up = CASE
        WHEN NOT ja_comprou AND canal_atual NOT IN ('REP', 'C-REP') THEN NOW()
        ELSE data_wait_follow_up
      END,
      updated_at = NOW()
  WHERE ultima_interacao = 'start'
    AND data_start < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_start_timeout = ROW_COUNT;

  -- 3) follow_up sem resposta há 24h → wait_follow_up
  UPDATE public.contatos
  SET ultima_interacao     = 'wait_follow_up',
      data_wait_follow_up  = NOW(),
      updated_at           = NOW()
  WHERE ultima_interacao = 'follow_up'
    AND data_ultimo_follow_up < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) wait_follow_up com 3+ tentativas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS',
      data_nunca_mais  = NOW(),
      updated_at       = NOW()
  WHERE ultima_interacao = 'wait_follow_up'
    AND follow_up_tentativas >= 3;
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 5) em_fechamento parado 48h → fallback
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up'
      END,
      data_wait_follow_up = CASE
        WHEN NOT ja_comprou AND canal_atual NOT IN ('REP', 'C-REP') THEN NOW()
        ELSE data_wait_follow_up
      END,
      data_em_fechamento = NULL,
      updated_at = NOW()
  WHERE ultima_interacao = 'em_fechamento'
    AND data_em_fechamento < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  -- 6) rmkt sem resposta há 3 dias → volta a 'cliente'
  UPDATE public.contatos
  SET ultima_interacao             = 'cliente',
      rmkt_consecutive_silenciosos = rmkt_consecutive_silenciosos + 1,
      updated_at                   = NOW()
  WHERE ultima_interacao = 'rmkt'
    AND data_ultimo_rmkt < NOW() - INTERVAL '3 days'
    AND rmkt_respondeu_em IS NULL;
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

  -- 7) suporte parado 48h sem mensagem nova → fallback
  --    (humano não respondeu nem chamou /voltar — devolve pro funil)
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        ELSE 'wait_follow_up'
      END,
      data_wait_follow_up = CASE
        WHEN NOT ja_comprou THEN NOW() ELSE data_wait_follow_up END,
      estado_antes_suporte = NULL,
      data_suporte = NULL,
      suporte_motivo = NULL,
      updated_at = NOW()
  WHERE ultima_interacao = 'suporte'
    AND data_suporte < NOW() - INTERVAL '48 hours'
    AND canal_atual NOT IN ('REP', 'C-REP');  -- REP fica em suporte indefinido
  GET DIAGNOSTICS v_suporte_timeout = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'ativacao_nunca_mais', v_ativacao_nunca_mais,
    'start_timeout', v_start_timeout,
    'follow_up_timeout', v_follow_up_timeout,
    'wait_expirado', v_wait_expirado,
    'em_fechamento_timeout', v_em_fechamento_timeout,
    'rmkt_timeout', v_rmkt_timeout,
    'suporte_timeout', v_suporte_timeout
  );
END $$;

GRANT EXECUTE ON FUNCTION public.processar_transicoes_estado_contato()
  TO authenticated, anon, service_role;

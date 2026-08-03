-- ============================================================================
-- Garante que um contato com followup_bloqueado (X no Kanban / 3 tentativas /
-- descadastro por desinteresse) NUNCA volte pra coluna de follow-up.
--
-- Furos corrigidos no cron processar_transicoes_estado_contato:
--   (3)  follow_up  -> wait   : não transita bloqueado (fica fora do funil)
--   (5b) em_fechamento -> wait : bloqueado sem compra vai pra 'start' terminal
--   (7)  suporte    -> wait   : bloqueado vai pra 'start' terminal
--   (8)  VARREDURA: qualquer bloqueado que já esteja num estado de follow-up
--        (wait_follow_up / follow_up / wait_follow_up_custom) é varrido pra
--        'start' terminal — limpa o que vazou antes deste fix.
--
-- 'start' é terminal pra bloqueado: o passo (2) start->wait já tem o guard
-- NOT followup_bloqueado, então ele fica parado e sai do Kanban.
--
-- Também: marcar_nunca_mais passa a setar followup_bloqueado + rmkt_bloqueado,
-- pra que NUNCA_MAIS seja realmente terminal mesmo que o estado mude depois.
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
  v_bloqueado_varrido     INTEGER := 0;
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
  --    NÃO transita bloqueado — fica parado em 'start' (terminal, sai do Kanban)
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
    AND NOT COALESCE(c.followup_bloqueado, false)
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_start_timeout = ROW_COUNT;

  -- 3) follow_up sem resposta 24h → wait_follow_up (REP/C-REP e bloqueado ficam de fora)
  UPDATE public.contatos c
  SET ultima_interacao = 'wait_follow_up', data_wait_follow_up = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'follow_up'
    AND c.data_ultimo_follow_up < NOW() - INTERVAL '24 hours'
    AND c.canal_atual NOT IN ('REP', 'C-REP')
    AND NOT COALESCE(c.followup_bloqueado, false)
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) wait_follow_up esgotou 3 tentativas → 'start' + nunca-mais F-UP
  UPDATE public.contatos c
  SET ultima_interacao       = 'start',
      followup_bloqueado     = true,
      data_start             = NOW(),
      follow_up_tentativas   = 0,
      follow_up_reservado_ate = NULL,
      updated_at             = NOW()
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

  -- 5b) em_fechamento 48h sem venda → wait / cliente / suporte / start(bloqueado)
  --     Bloqueado sem compra sai pra 'start' terminal — nunca pro follow-up.
  UPDATE public.contatos c
  SET ultima_interacao = CASE
        WHEN c.ja_comprou THEN 'cliente'
        WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        WHEN COALESCE(c.followup_bloqueado, false) THEN 'start'
        ELSE 'wait_follow_up' END,
      suporte_motivo = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'rep_fechamento_timeout' ELSE c.suporte_motivo END,
      data_suporte   = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN NOW() ELSE c.data_suporte END,
      data_start     = CASE
        WHEN NOT c.ja_comprou AND c.canal_atual NOT IN ('REP', 'C-REP') AND COALESCE(c.followup_bloqueado, false) THEN NOW()
        ELSE c.data_start END,
      data_wait_follow_up = CASE
        WHEN NOT c.ja_comprou AND c.canal_atual NOT IN ('REP', 'C-REP') AND NOT COALESCE(c.followup_bloqueado, false) THEN NOW()
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

  -- 7) Suporte 48h sem ação → estado anterior (REP/C-REP fica; bloqueado→start)
  UPDATE public.contatos c
  SET ultima_interacao = CASE
        WHEN c.ja_comprou THEN 'cliente'
        WHEN COALESCE(c.followup_bloqueado, false) THEN 'start'
        ELSE 'wait_follow_up' END,
      data_start = CASE
        WHEN NOT c.ja_comprou AND COALESCE(c.followup_bloqueado, false) THEN NOW()
        ELSE c.data_start END,
      data_wait_follow_up = CASE
        WHEN NOT c.ja_comprou AND NOT COALESCE(c.followup_bloqueado, false) THEN NOW()
        ELSE c.data_wait_follow_up END,
      estado_antes_suporte = NULL, data_suporte = NULL, suporte_motivo = NULL,
      updated_at = NOW()
  WHERE c.ultima_interacao = 'suporte'
    AND c.data_suporte < NOW() - INTERVAL '48 hours'
    AND c.canal_atual NOT IN ('REP', 'C-REP')
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_suporte_timeout = ROW_COUNT;

  -- 8) VARREDURA: bloqueado que vazou pra algum estado de follow-up volta pro
  --    'start' terminal. Rede de segurança pro que entrou antes deste fix.
  UPDATE public.contatos c
  SET ultima_interacao        = 'start',
      data_start              = NOW(),
      data_wait_follow_up     = NULL,
      follow_up_tentativas    = 0,
      follow_up_reservado_ate = NULL,
      updated_at              = NOW()
  WHERE COALESCE(c.followup_bloqueado, false) = true
    AND c.ultima_interacao IN ('wait_follow_up', 'follow_up', 'wait_follow_up_custom');
  GET DIAGNOSTICS v_bloqueado_varrido = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'ativacao_nunca_mais', v_ativacao_nunca_mais,
    'start_timeout', v_start_timeout,
    'follow_up_timeout', v_follow_up_timeout,
    'wait_expirado', v_wait_expirado,
    'em_fechamento_pago_imediato', v_em_fechamento_pago,
    'em_fechamento_timeout', v_em_fechamento_timeout,
    'rmkt_timeout', v_rmkt_timeout,
    'suporte_timeout', v_suporte_timeout,
    'bloqueado_varrido', v_bloqueado_varrido
  );
END $$;

GRANT EXECUTE ON FUNCTION public.processar_transicoes_estado_contato()
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- marcar_nunca_mais: além de NUNCA_MAIS, trava follow-up e RMKT (terminal real)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marcar_nunca_mais(
  p_contato_id uuid,
  p_motivo     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado_atual text;
BEGIN
  SELECT ultima_interacao INTO v_estado_atual
    FROM public.contatos WHERE id = p_contato_id;

  UPDATE public.contatos
     SET ultima_interacao        = 'NUNCA_MAIS',
         data_nunca_mais         = NOW(),
         followup_bloqueado      = true,
         rmkt_bloqueado          = true,
         followup_custom_em      = NULL,
         follow_up_reservado_ate = NULL,
         rmkt_reservado_ate      = NULL,
         bot_pausado_ate         = NULL,
         updated_at              = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'nunca_mais', v_estado_atual, 'NUNCA_MAIS',
            jsonb_build_object('motivo', COALESCE(p_motivo, 'recusa_explicita')));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'estado_anterior', v_estado_atual);
END $$;

GRANT EXECUTE ON FUNCTION public.marcar_nunca_mais(uuid, text)
  TO authenticated, anon, service_role;

-- Limpeza retroativa: quem já está NUNCA_MAIS ganha os flags de bloqueio.
UPDATE public.contatos
   SET followup_bloqueado = true, rmkt_bloqueado = true
 WHERE ultima_interacao = 'NUNCA_MAIS'
   AND (COALESCE(followup_bloqueado, false) = false OR COALESCE(rmkt_bloqueado, false) = false);

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Rodada A: substitui data_cliente por primeira_venda_em nas funções críticas.
-- Trigger sync_data_cliente garante que data_cliente continua refletindo o
-- mesmo valor — quem ainda lê data_cliente continua funcionando.
--
-- Após esta migration:
--  - claim_proximo_lead_rmkt LÊ primeira_venda_em (era data_cliente)
--  - trigger_contato_virou_cliente PARA de escrever em data_cliente
--    (sync trigger faz por baixo, e remove dependência inversa)
--  - processar_transicoes_estado_contato PARA de escrever em data_cliente
--
-- Rodada B (futuro, depois de 1 semana sem incidente):
--  - Auditar se há mais alguma função usando data_cliente
--  - DROP TRIGGER trg_sync_data_cliente + DROP COLUMN data_cliente
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) claim_proximo_lead_rmkt — usa primeira_venda_em
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id uuid,
  p_dias_gap integer DEFAULT 30
)
RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campanha_id uuid;
  v_dias_inativo integer;
  v_dias_gap integer;
BEGIN
  SELECT c.id, c.dias_inativo_min, c.intervalo_minutos
    INTO v_campanha_id, v_dias_inativo, v_dias_gap
  FROM public.campanhas c
  WHERE c.tipo = 'rmkt'
    AND c.ativa = true
    AND c.pausa_global = false
  ORDER BY c.created_at ASC
  LIMIT 1;

  v_dias_inativo := COALESCE(v_dias_inativo, p_dias_gap, 30);
  v_dias_gap     := COALESCE(v_dias_gap,     p_dias_gap, 30);

  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao = 'rmkt',
      data_ultimo_rmkt = NOW(),
      instancia_id     = p_instancia_id,
      updated_at       = NOW()
  WHERE c.id = (
    SELECT c2.id
    FROM public.contatos c2
    WHERE c2.ja_comprou = true
      AND c2.ultima_interacao = 'cliente'
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.rmkt_consecutive_silenciosos < 3
      AND (c2.data_ultimo_rmkt IS NULL OR c2.data_ultimo_rmkt < NOW() - (v_dias_gap || ' days')::INTERVAL)
      AND c2.primeira_venda_em < NOW() - (v_dias_inativo || ' days')::INTERVAL  -- antes: data_cliente
    ORDER BY c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(uuid, integer)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 2) trigger_contato_virou_cliente — para de setar data_cliente manualmente
--    (trigger sync_data_cliente faz isso quando primeira_venda_em muda)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_contato_virou_cliente()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ts timestamptz := COALESCE(NEW.created_at, NOW());
BEGIN
  IF NEW.contato_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status_pedido = 'cancelado' THEN RETURN NEW; END IF;

  UPDATE public.contatos
     SET ja_comprou                = true,
         ultima_interacao          = 'cliente',
         data_em_fechamento        = NULL,
         data_aguardando_pagamento = NULL,
         primeira_venda_em         = LEAST(COALESCE(primeira_venda_em, v_ts), v_ts),
         ultima_venda_em           = GREATEST(COALESCE(ultima_venda_em, v_ts), v_ts),
         updated_at                = NOW()
   WHERE id = NEW.contato_id;
  -- data_cliente é mantida pelo trigger trg_sync_data_cliente
  RETURN NEW;
END $$;

-- ----------------------------------------------------------------------------
-- 3) processar_transicoes_estado_contato — remove SET data_cliente
--    Quando bloco 5a vira contato em em_fechamento+ja_comprou pra cliente:
--    se primeira_venda_em já existe (e existe, porque ja_comprou=true vem
--    da trigger), o sync mantém data_cliente igual.
--    Se por algum motivo primeira_venda_em é NULL E ja_comprou=true (caso
--    raro de admin), garantimos populando primeira_venda_em via subquery.
-- ----------------------------------------------------------------------------
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
  -- 1) ativacao 3+ tentativas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'ativacao_contatos'
    AND ativacao_tentativas >= 3
    AND data_ultimo_ativacao < NOW() - INTERVAL '3 days';
  GET DIAGNOSTICS v_ativacao_nunca_mais = ROW_COUNT;

  -- 2) start 24h → wait_follow_up (REP→suporte)
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up'
      END,
      suporte_motivo = CASE WHEN canal_atual IN ('REP', 'C-REP') THEN 'rep_start_timeout' ELSE suporte_motivo END,
      data_suporte   = CASE WHEN canal_atual IN ('REP', 'C-REP') THEN NOW() ELSE data_suporte END,
      data_wait_follow_up = CASE WHEN NOT ja_comprou AND canal_atual NOT IN ('REP', 'C-REP') THEN NOW() ELSE data_wait_follow_up END,
      updated_at = NOW()
  WHERE ultima_interacao = 'start' AND data_start < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_start_timeout = ROW_COUNT;

  -- 3) follow_up sem resposta 24h → wait_follow_up
  UPDATE public.contatos
  SET ultima_interacao = 'wait_follow_up', data_wait_follow_up = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'follow_up'
    AND data_ultimo_follow_up < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) wait_follow_up 3+ tentativas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'wait_follow_up' AND follow_up_tentativas >= 3;
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 5a) em_fechamento + ja_comprou OU com pedido → cliente IMEDIATO
  --     Sem escrever em data_cliente — trigger sync cuida via primeira_venda_em.
  --     Caso raro (sem primeira_venda_em populada): pega min(created_at)
  --     dos pedidos ativos do contato.
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
    AND (
      c.ja_comprou = true
      OR EXISTS (
        SELECT 1 FROM public.pedidos p
         WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'
      )
    );
  GET DIAGNOSTICS v_em_fechamento_pago = ROW_COUNT;

  -- 5b) em_fechamento parado 48h SEM venda → fallback
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE
        WHEN NOT ja_comprou AND canal_atual NOT IN ('REP', 'C-REP') THEN NOW()
        ELSE data_wait_follow_up END,
      data_em_fechamento = NULL,
      updated_at = NOW()
  WHERE ultima_interacao = 'em_fechamento'
    AND data_em_fechamento < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  -- 6) rmkt sem resposta 3 dias → cliente
  UPDATE public.contatos
  SET ultima_interacao = 'cliente',
      rmkt_consecutive_silenciosos = rmkt_consecutive_silenciosos + 1,
      updated_at = NOW()
  WHERE ultima_interacao = 'rmkt'
    AND data_ultimo_rmkt < NOW() - INTERVAL '3 days'
    AND rmkt_respondeu_em IS NULL;
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

  -- 7) suporte 48h sem msg → fallback
  UPDATE public.contatos
  SET ultima_interacao = CASE WHEN ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE WHEN NOT ja_comprou THEN NOW() ELSE data_wait_follow_up END,
      estado_antes_suporte = NULL, data_suporte = NULL, suporte_motivo = NULL,
      updated_at = NOW()
  WHERE ultima_interacao = 'suporte'
    AND data_suporte < NOW() - INTERVAL '48 hours'
    AND canal_atual NOT IN ('REP', 'C-REP');
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

NOTIFY pgrst, 'reload schema';

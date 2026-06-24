-- ============================================================================
-- RMKT v2 — granularidade por quantidade do último pedido + drop rmkt_respondeu_em.
--
-- ANTES:
--   - Gap único 'dias_inativo_min' (todo cliente espera o mesmo X dias)
--   - rmkt_respondeu_em (sempre NULL — ninguém escrevia)
--   - Cron incrementava rmkt_consecutive_silenciosos após 3 dias em RMKT
--
-- AGORA:
--   - Gap por FAIXA de qtd_ultimo_pedido (1-2 / 3-5 / 5+) — configurável
--   - rmkt_max_envios: limite de RMKTs por contato (default 3)
--   - rmkt_consecutive_silenciosos: incrementado AO ENVIAR o RMKT
--     (não mais por timeout) + ZERA na compra (já fazia)
--   - rmkt_respondeu_em: DROPADO (sempre NULL, sem escritor)
--
-- COLUNAS NOVAS em campanhas:
--   rmkt_gap_1_2_dias    (default 30)
--   rmkt_gap_3_5_dias    (default 45)
--   rmkt_gap_5_plus_dias (default 60)
--   rmkt_max_envios      (default 3)
-- COLUNA NOVA em contatos:
--   qtd_ultimo_pedido    (snapshot na hora da venda, via trigger)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Colunas novas em campanhas
-- ----------------------------------------------------------------------------
ALTER TABLE public.campanhas
  ADD COLUMN IF NOT EXISTS rmkt_gap_1_2_dias    integer NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS rmkt_gap_3_5_dias    integer NOT NULL DEFAULT 45,
  ADD COLUMN IF NOT EXISTS rmkt_gap_5_plus_dias integer NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS rmkt_max_envios      integer NOT NULL DEFAULT 3;

COMMENT ON COLUMN public.campanhas.rmkt_gap_1_2_dias    IS 'Dias mínimos desde última compra pra disparar RMKT (cliente comprou 1-2 produtos).';
COMMENT ON COLUMN public.campanhas.rmkt_gap_3_5_dias    IS 'Dias mínimos desde última compra (3-5 produtos).';
COMMENT ON COLUMN public.campanhas.rmkt_gap_5_plus_dias IS 'Dias mínimos desde última compra (6+ produtos).';
COMMENT ON COLUMN public.campanhas.rmkt_max_envios      IS 'Máximo de RMKTs por contato até a próxima compra. Contador rmkt_consecutive_silenciosos.';

-- ----------------------------------------------------------------------------
-- 2) Coluna nova em contatos + backfill via pedidos
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS qtd_ultimo_pedido integer;

COMMENT ON COLUMN public.contatos.qtd_ultimo_pedido IS
  'Qtd de produtos do último pedido (snapshot). Define a faixa de gap pro RMKT.';

UPDATE public.contatos c
   SET qtd_ultimo_pedido = sub.qtd
  FROM (
    SELECT DISTINCT ON (p.contato_id)
           p.contato_id, p.quantidade AS qtd
      FROM public.pedidos p
     WHERE p.contato_id IS NOT NULL AND p.status_pedido != 'cancelado'
     ORDER BY p.contato_id, p.created_at DESC
  ) sub
 WHERE c.id = sub.contato_id
   AND c.qtd_ultimo_pedido IS NULL;

-- ----------------------------------------------------------------------------
-- 3) Trigger contato_virou_cliente: popula qtd_ultimo_pedido
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_contato_virou_cliente()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ts timestamptz := COALESCE(NEW.created_at, NOW());
  v_qtd integer := COALESCE(NEW.quantidade, 1);
BEGIN
  IF NEW.contato_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status_pedido = 'cancelado' THEN RETURN NEW; END IF;

  UPDATE public.contatos
     SET ja_comprou                   = true,
         ultima_interacao             = 'cliente',
         data_em_fechamento           = NULL,
         data_aguardando_pagamento    = NULL,
         primeira_venda_em            = LEAST(COALESCE(primeira_venda_em, v_ts), v_ts),
         ultima_venda_em              = GREATEST(COALESCE(ultima_venda_em, v_ts), v_ts),
         qtd_ultimo_pedido            = v_qtd,
         rmkt_consecutive_silenciosos = 0,   -- ZERA contador RMKT na compra
         updated_at                   = NOW()
   WHERE id = NEW.contato_id;
  RETURN NEW;
END $$;

-- ----------------------------------------------------------------------------
-- 4) DROP rmkt_respondeu_em (depois de recriar funções que ainda referenciam)
-- ----------------------------------------------------------------------------
-- Recria processar_transicoes_estado_contato sem o bloco 6 baseado em rmkt_respondeu_em.
-- Agora o incremento do contador acontece NO CLAIM (quando envia), não no timeout.
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
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'ativacao_contatos'
    AND ativacao_tentativas >= 3
    AND data_ultimo_ativacao < NOW() - INTERVAL '3 days';
  GET DIAGNOSTICS v_ativacao_nunca_mais = ROW_COUNT;

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

  UPDATE public.contatos
  SET ultima_interacao = 'wait_follow_up', data_wait_follow_up = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'follow_up'
    AND data_ultimo_follow_up < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'wait_follow_up' AND follow_up_tentativas >= 3;
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
                     WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'));
  GET DIAGNOSTICS v_em_fechamento_pago = ROW_COUNT;

  -- 5b) em_fechamento 48h sem venda → fallback
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

  -- 6) rmkt: simplificado. Após 3 dias em RMKT → volta pra 'cliente'.
  --    Contador rmkt_consecutive_silenciosos NÃO é mais incrementado aqui.
  --    Incremento acontece no CLAIM (ao enviar). Zera na compra (trigger).
  UPDATE public.contatos
  SET ultima_interacao = 'cliente',
      updated_at = NOW()
  WHERE ultima_interacao = 'rmkt'
    AND data_ultimo_rmkt < NOW() - INTERVAL '3 days';
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

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

-- Agora pode DROP da coluna
ALTER TABLE public.contatos DROP COLUMN IF EXISTS rmkt_respondeu_em;

-- ----------------------------------------------------------------------------
-- 5) claim_proximo_lead_rmkt — NOVA lógica: gap por faixa + max envios
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_rmkt(uuid, integer);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id uuid,
  p_dias_gap integer DEFAULT NULL  -- legado: ignorado se config da campanha existe
)
RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_camp        record;
  v_dias_gap    integer;
  v_gap_1_2     integer;
  v_gap_3_5     integer;
  v_gap_5_plus  integer;
  v_max_envios  integer;
BEGIN
  SELECT c.intervalo_minutos, c.dias_sem_envio,
         c.rmkt_gap_1_2_dias, c.rmkt_gap_3_5_dias, c.rmkt_gap_5_plus_dias,
         c.rmkt_max_envios
    INTO v_camp
  FROM public.campanhas c
  WHERE c.tipo = 'rmkt' AND c.ativa = true AND c.pausa_global = false
  ORDER BY c.created_at ASC LIMIT 1;

  v_dias_gap   := COALESCE(v_camp.dias_sem_envio,    p_dias_gap, 30);
  v_gap_1_2    := COALESCE(v_camp.rmkt_gap_1_2_dias,    30);
  v_gap_3_5    := COALESCE(v_camp.rmkt_gap_3_5_dias,    45);
  v_gap_5_plus := COALESCE(v_camp.rmkt_gap_5_plus_dias, 60);
  v_max_envios := COALESCE(v_camp.rmkt_max_envios,       3);

  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao             = 'rmkt',
      data_ultimo_rmkt             = NOW(),
      rmkt_consecutive_silenciosos = COALESCE(rmkt_consecutive_silenciosos, 0) + 1,
      instancia_id                 = p_instancia_id,
      updated_at                   = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ja_comprou = true
      AND c2.ultima_interacao = 'cliente'
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      -- LIMITE DE ENVIOS POR CONTATO (zera na compra)
      AND COALESCE(c2.rmkt_consecutive_silenciosos, 0) < v_max_envios
      -- GAP entre RMKTs (não recebeu RMKT recentemente)
      AND (c2.data_ultimo_rmkt IS NULL
           OR c2.data_ultimo_rmkt < NOW() - (v_dias_gap || ' days')::INTERVAL)
      -- GAP por FAIXA de quantidade do último pedido
      AND c2.ultima_venda_em < NOW() - (
        CASE
          WHEN COALESCE(c2.qtd_ultimo_pedido, 1) BETWEEN 1 AND 2 THEN v_gap_1_2
          WHEN COALESCE(c2.qtd_ultimo_pedido, 1) BETWEEN 3 AND 5 THEN v_gap_3_5
          ELSE                                                       v_gap_5_plus
        END || ' days'
      )::INTERVAL
      -- Interlock com marketing
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
    ORDER BY c2.ultima_venda_em ASC NULLS LAST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(uuid, integer)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

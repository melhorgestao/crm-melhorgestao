-- ============================================================================
-- Botão X no Kanban: PARAR F-UP / PARAR RMKT de um contato.
--
-- Dois bloqueios DISTINTOS e independentes:
--   followup_bloqueado  -> "nunca mais F-UP"  (permanente)
--   rmkt_bloqueado      -> "nunca mais RMKT"  (até a próxima compra, que zera)
--
-- Comportamento:
--   parar_followup_contato(id)  -> ultima_interacao='start' + followup_bloqueado
--       (MESMA lógica de quando o contato estoura 3 F-UP sem comprar: hoje o
--        cron mandava pra NUNCA_MAIS global; agora vai pra 'start' bloqueado).
--   parar_rmkt_contato(id)      -> ultima_interacao='cliente' + rmkt_bloqueado
--       Fica fora do RMKT até fazer nova compra. O trigger de venda zera o
--       rmkt_bloqueado (e o contador), devolvendo elegibilidade pro próximo RMKT.
--
-- Este arquivo recria as funções que precisam respeitar os novos flags:
--   - cron processar_transicoes_estado_contato (2 mudanças)
--   - claim_proximo_lead_followup      (exclui followup_bloqueado)
--   - claim_proximo_lead_rmkt (reserva)(exclui rmkt_bloqueado)
--   - v_kanban_rmkt_wait               (exclui rmkt_bloqueado)
--   - trigger_contato_virou_cliente    (zera rmkt_bloqueado na compra)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Colunas de bloqueio
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS followup_bloqueado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS rmkt_bloqueado     boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.contatos.followup_bloqueado IS
  'Nunca-mais F-UP. Contato não recebe mais campanha de follow-up (X no Kanban ou 3 tentativas esgotadas). Independente de rmkt_bloqueado.';
COMMENT ON COLUMN public.contatos.rmkt_bloqueado IS
  'Nunca-mais RMKT até a próxima compra. Setado pelo X no Kanban RMKT; zerado no trigger de venda. Independente de followup_bloqueado.';

-- ----------------------------------------------------------------------------
-- 1) RPC parar_followup_contato -> volta pra 'start' com nunca-mais F-UP
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parar_followup_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado text;
BEGIN
  SELECT ultima_interacao INTO v_estado FROM public.contatos WHERE id = p_contato_id;
  IF v_estado IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  UPDATE public.contatos
     SET ultima_interacao       = 'start',
         followup_bloqueado     = true,
         data_start             = NOW(),
         follow_up_tentativas   = 0,
         follow_up_reservado_ate = NULL,
         updated_at             = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'parar_followup', v_estado, 'start',
            jsonb_build_object('via', 'ui_kanban', 'followup_bloqueado', true));
  EXCEPTION WHEN undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'estado_para', 'start', 'followup_bloqueado', true);
END $$;

GRANT EXECUTE ON FUNCTION public.parar_followup_contato(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 2) RPC parar_rmkt_contato -> volta pra 'cliente' com nunca-mais RMKT
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parar_rmkt_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado text;
BEGIN
  SELECT ultima_interacao INTO v_estado FROM public.contatos WHERE id = p_contato_id;
  IF v_estado IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  UPDATE public.contatos
     SET ultima_interacao   = 'cliente',
         rmkt_bloqueado     = true,
         rmkt_reservado_ate = NULL,
         updated_at         = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'parar_rmkt', v_estado, 'cliente',
            jsonb_build_object('via', 'ui_kanban', 'rmkt_bloqueado', true));
  EXCEPTION WHEN undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'estado_para', 'cliente', 'rmkt_bloqueado', true);
END $$;

GRANT EXECUTE ON FUNCTION public.parar_rmkt_contato(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 3) Cron processar_transicoes_estado_contato — 2 mudanças:
--    (a) start→wait: NÃO transita contato com followup_bloqueado (fica em start)
--    (b) wait_follow_up c/ 3 tentativas: NÃO vai mais pra NUNCA_MAIS global.
--        Vai pra 'start' + followup_bloqueado (mesma lógica do botão X).
--    Resto idêntico ao 20260710.
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
  --    NÃO transita contatos com followup_bloqueado — ficam parados em 'start'
  --    (nunca-mais F-UP). REP/C-REP caem pra 'suporte'.
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

  -- 3) follow_up sem resposta 24h → wait_follow_up (REP/C-REP fica parado)
  UPDATE public.contatos c
  SET ultima_interacao = 'wait_follow_up', data_wait_follow_up = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'follow_up'
    AND c.data_ultimo_follow_up < NOW() - INTERVAL '24 hours'
    AND c.canal_atual NOT IN ('REP', 'C-REP')
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) wait_follow_up esgotou 3 tentativas → 'start' + nunca-mais F-UP
  --    (ANTES: NUNCA_MAIS global). Mesma lógica do botão X de parar F-UP.
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

  -- 5b) em_fechamento 48h sem venda → wait_follow_up / cliente / suporte
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

  -- 7) Suporte 48h sem ação → estado anterior (REP/C-REP fica)
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
-- 4) claim_proximo_lead_followup — exclui followup_bloqueado
--    (recria versão 20260725 + guard)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_followup(uuid);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup(p_instancia_id uuid)
RETURNS TABLE (id uuid, nome text, telefone text, subcategoria text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET follow_up_reservado_ate = NOW() + INTERVAL '5 minutes',
      instancia_id            = p_instancia_id,
      updated_at              = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ultima_interacao = 'wait_follow_up'
      AND c2.ja_comprou = false
      AND c2.telefone IS NOT NULL
      AND NOT COALESCE(c2.followup_bloqueado, false)
      AND COALESCE(c2.ativacao_tentativas, 0) = 0
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.follow_up_tentativas < 3
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
      AND (c2.data_wait_follow_up < NOW() - INTERVAL '24 hours' OR c2.data_wait_follow_up IS NULL)
      AND (c2.follow_up_reservado_ate IS NULL OR c2.follow_up_reservado_ate < NOW())
    ORDER BY c2.data_wait_follow_up ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone,
            CASE (COALESCE(c.follow_up_tentativas,0) + 1)
              WHEN 1 THEN '24h' WHEN 2 THEN '3d' ELSE '7d'
            END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 5) claim_proximo_lead_rmkt (reserva, versão 20260722) — exclui rmkt_bloqueado
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_rmkt(uuid, integer);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id uuid,
  p_dias_gap integer DEFAULT NULL
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
  SET rmkt_reservado_ate = NOW() + INTERVAL '5 minutes',
      instancia_id       = p_instancia_id,
      updated_at         = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ja_comprou = true
      AND c2.ultima_interacao = 'cliente'
      AND c2.telefone IS NOT NULL
      AND NOT COALESCE(c2.rmkt_bloqueado, false)
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND COALESCE(c2.rmkt_consecutive_silenciosos, 0) < v_max_envios
      AND (c2.data_ultimo_rmkt IS NULL
           OR c2.data_ultimo_rmkt < NOW() - (v_dias_gap || ' days')::INTERVAL)
      AND c2.ultima_venda_em < NOW() - (
        CASE
          WHEN COALESCE(c2.qtd_ultimo_pedido, 1) BETWEEN 1 AND 2 THEN v_gap_1_2
          WHEN COALESCE(c2.qtd_ultimo_pedido, 1) BETWEEN 3 AND 5 THEN v_gap_3_5
          ELSE                                                       v_gap_5_plus
        END || ' days'
      )::INTERVAL
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
      AND (c2.rmkt_reservado_ate IS NULL OR c2.rmkt_reservado_ate < NOW())
    ORDER BY c2.ultima_venda_em ASC NULLS LAST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(uuid, integer)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 6) v_kanban_rmkt_wait — exclui rmkt_bloqueado (recria 20260726 + guard)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.v_kanban_rmkt_wait;

CREATE VIEW public.v_kanban_rmkt_wait AS
WITH camp AS (
  SELECT rmkt_gap_1_2_dias    AS g12,
         rmkt_gap_3_5_dias    AS g35,
         rmkt_gap_5_plus_dias AS g5p,
         rmkt_max_envios      AS maxe,
         dias_sem_envio       AS gap
  FROM public.campanhas
  WHERE tipo = 'rmkt' AND ativa = true AND pausa_global = false
  ORDER BY created_at ASC
  LIMIT 1
),
ult_pedido AS (
  SELECT DISTINCT ON (p.contato_id)
         p.contato_id, p.id AS pedido_id, p.order_number
  FROM public.pedidos p
  WHERE p.status_pedido != 'cancelado'
  ORDER BY p.contato_id, p.created_at DESC
)
SELECT
  c.id,
  c.nome,
  c.telefone,
  c.canal_origem,
  c.canal_atual,
  c.instancia_id,
  c.created_at,
  c.updated_at,
  c.tag_kanban,
  c.tag_kanban_ate,
  c.ultima_interacao,
  c.ja_comprou,
  c.follow_up_tentativas,
  c.ativacao_tentativas,
  c.data_start,
  c.data_wait_follow_up,
  c.data_ultimo_follow_up,
  c.data_em_fechamento,
  c.data_ultimo_rmkt,
  c.data_suporte,
  c.suporte_motivo,
  c.bot_pausado_ate,
  c.ultima_venda_em,
  c.qtd_ultimo_pedido,
  c.rmkt_consecutive_silenciosos,
  i.nome   AS inst_nome,
  i.numero AS inst_numero,
  up.pedido_id     AS ultimo_pedido_id,
  up.order_number  AS ultimo_pedido_order,
  (c.ultima_venda_em + (
     CASE
       WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 1 AND 2 THEN COALESCE(camp.g12,30)
       WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 3 AND 5 THEN COALESCE(camp.g35,45)
       ELSE                                                       COALESCE(camp.g5p,60)
     END || ' days')::interval
  ) AS proxima_rmkt_em
FROM public.contatos c
CROSS JOIN camp
LEFT JOIN public.instancias i ON i.id = c.instancia_id
LEFT JOIN ult_pedido up       ON up.contato_id = c.id
WHERE c.ja_comprou = true
  AND c.ultima_interacao = 'cliente'
  AND c.telefone IS NOT NULL
  AND c.ultima_venda_em IS NOT NULL
  AND NOT COALESCE(c.rmkt_bloqueado, false)
  AND COALESCE(c.rmkt_consecutive_silenciosos, 0) < COALESCE(camp.maxe, 3)
  AND (
      -- Elegível AGORA (nunca disparou ou passou gap por qtd) → WAIT "pronto"
      (
        COALESCE(c.rmkt_consecutive_silenciosos, 0) = 0
        AND c.ultima_venda_em < NOW() - (
           CASE
             WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 1 AND 2 THEN COALESCE(camp.g12,30)
             WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 3 AND 5 THEN COALESCE(camp.g35,45)
             ELSE                                                       COALESCE(camp.g5p,60)
           END || ' days')::interval
        AND (c.data_ultimo_rmkt IS NULL
             OR c.data_ultimo_rmkt < NOW() - (COALESCE(camp.gap,30) || ' days')::interval)
        AND (c.marketing_cooldown_ate IS NULL OR c.marketing_cooldown_ate < NOW())
      )
      -- OU já em ciclo (disparou pelo menos 1x, contador entre 1 e max-1)
      OR (
        COALESCE(c.rmkt_consecutive_silenciosos, 0) >= 1
        AND COALESCE(c.rmkt_consecutive_silenciosos, 0) < COALESCE(camp.maxe, 3)
      )
  );

GRANT SELECT ON public.v_kanban_rmkt_wait TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 7) trigger_contato_virou_cliente — nova compra ZERA rmkt_bloqueado
--    (recria 20260708 + rmkt_bloqueado = false)
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
         rmkt_consecutive_silenciosos = 0,     -- ZERA contador RMKT na compra
         rmkt_bloqueado               = false, -- nova compra reativa RMKT (nunca-mais zerado)
         updated_at                   = NOW()
   WHERE id = NEW.contato_id;
  RETURN NEW;
END $$;

NOTIFY pgrst, 'reload schema';

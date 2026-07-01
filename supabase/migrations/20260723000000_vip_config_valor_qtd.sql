-- ============================================================================
-- VIP configurável: tag VIP por valor total gasto E/OU quantidade de pedidos.
--
-- Antes: VIP hardcoded = 3+ pedidos pagos.
-- Agora: 2 thresholds em configuracoes, editáveis pelo modal em Pedidos>Ranking:
--   vip_min_pedidos  (default 3)  — nº mínimo de pedidos pagos
--   vip_min_valor    (default 0)  — R$ mínimo gasto (0 = critério desligado)
-- Regra: VIP se (pedidos >= vip_min_pedidos) OU (vip_min_valor>0 E gasto>=vip_min_valor).
-- ============================================================================

INSERT INTO public.configuracoes (chave, valor) VALUES
  ('vip_min_pedidos', '3'),
  ('vip_min_valor',   '0')
ON CONFLICT (chave) DO NOTHING;

-- ----------------------------------------------------------------------------
-- compute_tag_kanban: +p_total_valor, lê thresholds da config (STABLE agora).
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.compute_tag_kanban(text, text, boolean, bigint, timestamptz);

CREATE OR REPLACE FUNCTION public.compute_tag_kanban(
  p_ultima_interacao TEXT,
  p_canal_origem     TEXT,
  p_ja_comprou       BOOLEAN,
  p_total_pedidos    BIGINT,
  p_created_at       TIMESTAMPTZ,
  p_total_valor      NUMERIC DEFAULT 0
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_min_pedidos INTEGER;
  v_min_valor   NUMERIC;
BEGIN
  SELECT COALESCE(NULLIF(valor,'')::int, 3)     INTO v_min_pedidos FROM public.configuracoes WHERE chave = 'vip_min_pedidos';
  SELECT COALESCE(NULLIF(valor,'')::numeric, 0) INTO v_min_valor   FROM public.configuracoes WHERE chave = 'vip_min_valor';
  v_min_pedidos := COALESCE(v_min_pedidos, 3);
  v_min_valor   := COALESCE(v_min_valor, 0);

  -- VIP: por quantidade OU por valor gasto (se o critério de valor estiver ligado)
  IF (v_min_pedidos > 0 AND p_total_pedidos >= v_min_pedidos)
     OR (v_min_valor > 0 AND COALESCE(p_total_valor, 0) >= v_min_valor) THEN
    RETURN 'VIP';
  END IF;

  IF p_ja_comprou = true THEN
    RETURN 'BUYER';
  END IF;

  IF p_canal_origem IN ('REP', 'C-REP') THEN
    RETURN 'REP';
  END IF;

  IF p_canal_origem = 'ADS' THEN
    RETURN 'ADS';
  END IF;

  IF (p_ultima_interacao IS NULL OR p_ultima_interacao = 'start')
     AND p_created_at > NOW() - INTERVAL '48 hours' THEN
    RETURN 'NEW';
  END IF;

  RETURN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- Trigger sync: agora também soma o valor pago pra passar p_total_valor
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_sync_tag_kanban()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_pedidos BIGINT;
  v_total_valor   NUMERIC;
  v_nova_tag      TEXT;
  v_tag_ate       TIMESTAMPTZ;
BEGIN
  SELECT COUNT(*), COALESCE(SUM(valor), 0)
    INTO v_total_pedidos, v_total_valor
  FROM public.pedidos
  WHERE contato_id = NEW.id
    AND status_pagamento = 'pago';

  v_nova_tag := public.compute_tag_kanban(
    NEW.ultima_interacao, NEW.canal_origem, NEW.ja_comprou,
    COALESCE(v_total_pedidos, 0), NEW.created_at, COALESCE(v_total_valor, 0)
  );

  v_tag_ate := CASE WHEN v_nova_tag = 'NEW' THEN NEW.created_at + INTERVAL '48 hours' ELSE NULL END;

  IF NEW.tag_kanban IS DISTINCT FROM v_nova_tag
     OR NEW.tag_kanban_ate IS DISTINCT FROM v_tag_ate THEN
    NEW.tag_kanban     := v_nova_tag;
    NEW.tag_kanban_ate := v_tag_ate;
  END IF;

  RETURN NEW;
END $$;

-- ----------------------------------------------------------------------------
-- RPC de recálculo total — chamada pelo modal após salvar os thresholds.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recalcular_tags_vip()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_alterados INTEGER;
BEGIN
  UPDATE public.contatos c
  SET tag_kanban = sub.nova_tag,
      tag_kanban_ate = CASE WHEN sub.nova_tag = 'NEW' THEN c.created_at + INTERVAL '48 hours' ELSE NULL END,
      updated_at = NOW()
  FROM (
    SELECT c2.id,
           public.compute_tag_kanban(
             c2.ultima_interacao, c2.canal_origem, c2.ja_comprou,
             COALESCE(p.total_pedidos, 0), c2.created_at, COALESCE(p.total_valor, 0)
           ) AS nova_tag
    FROM public.contatos c2
    LEFT JOIN (
      SELECT contato_id, COUNT(*) AS total_pedidos, COALESCE(SUM(valor),0) AS total_valor
      FROM public.pedidos WHERE status_pagamento = 'pago'
      GROUP BY contato_id
    ) p ON p.contato_id = c2.id
  ) sub
  WHERE c.id = sub.id
    AND c.tag_kanban IS DISTINCT FROM sub.nova_tag;
  GET DIAGNOSTICS v_alterados = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'alterados', v_alterados);
END $$;

GRANT EXECUTE ON FUNCTION public.recalcular_tags_vip() TO authenticated, anon, service_role;

-- Recalc inicial pra aplicar a config nova
SELECT public.recalcular_tags_vip();

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Paridade RMKT: tag RMKT só com disparo CONFIRMADO (reserva → confirma).
--
-- Mesmo bug do followup: claim_proximo_lead_rmkt marcava ultima_interacao=
-- 'rmkt' + incrementava rmkt_consecutive_silenciosos ANTES do envio. Se o
-- fluxo saía sem enviar, o lead ficava em rmkt com o contador furado.
--
-- FIX:
--   1) claim RMKT RESERVA (rmkt_reservado_ate = NOW()+5min), devolve o lead
--      SEM mudar estado nem contador.
--   2) confirmar_envio_lead (UNIFICADO followup + rmkt) — chamada após envio
--      OK — detecta qual reserva está ativa e efetiva o estado correto.
--   3) Sem envio: nada muda, reserva expira em 5min.
--
-- Substitui confirmar_envio_followup pelo confirmar_envio_lead unificado no
-- workflow (nó CONFIRMA).
-- ============================================================================

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS rmkt_reservado_ate timestamptz;

-- ----------------------------------------------------------------------------
-- 1) claim RMKT = RESERVA (não muda estado nem contador)
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
-- 2) confirmar_envio_lead UNIFICADO — detecta a reserva ativa e efetiva
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirmar_envio_lead(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hit boolean;
BEGIN
  -- followup
  UPDATE public.contatos
     SET ultima_interacao        = 'follow_up',
         follow_up_tentativas     = follow_up_tentativas + 1,
         data_ultimo_follow_up    = NOW(),
         follow_up_reservado_ate  = NULL,
         updated_at               = NOW()
   WHERE id = p_contato_id
     AND follow_up_reservado_ate IS NOT NULL;
  GET DIAGNOSTICS v_hit = ROW_COUNT;
  IF v_hit THEN RETURN jsonb_build_object('ok', true, 'tipo', 'followup'); END IF;

  -- rmkt
  UPDATE public.contatos
     SET ultima_interacao             = 'rmkt',
         data_ultimo_rmkt             = NOW(),
         rmkt_consecutive_silenciosos = COALESCE(rmkt_consecutive_silenciosos, 0) + 1,
         rmkt_reservado_ate           = NULL,
         updated_at                   = NOW()
   WHERE id = p_contato_id
     AND rmkt_reservado_ate IS NOT NULL;
  GET DIAGNOSTICS v_hit = ROW_COUNT;
  IF v_hit THEN RETURN jsonb_build_object('ok', true, 'tipo', 'rmkt'); END IF;

  RETURN jsonb_build_object('ok', true, 'tipo', 'none');
END $$;

GRANT EXECUTE ON FUNCTION public.confirmar_envio_lead(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 3) CLEANUP RMKT: leads em rmkt sem envio confirmado desde a última compra.
--    Heurística: rmkt sem nenhum campanha_envios → volta pra cliente e zera
--    o contador (não recebeu de verdade).
-- ----------------------------------------------------------------------------
UPDATE public.contatos c
   SET ultima_interacao             = 'cliente',
       rmkt_consecutive_silenciosos = GREATEST(COALESCE(rmkt_consecutive_silenciosos, 1) - 1, 0),
       rmkt_reservado_ate           = NULL,
       updated_at                   = NOW()
 WHERE c.ultima_interacao = 'rmkt'
   AND NOT EXISTS (
     SELECT 1 FROM public.campanha_envios ce WHERE ce.contato_id = c.id
   );

NOTIFY pgrst, 'reload schema';

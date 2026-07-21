-- ============================================================================
-- claim_proximo_lead_rmkt v4 — alinha o DISPARO com a fila do Kanban (view v3).
--
-- PROBLEMA 1 (importados nunca recebiam): o claim exigia
--   AND c2.ultima_venda_em < NOW() - (gap)::interval
-- Cliente antigo importado tem ultima_venda_em NULL → a comparação vira NULL
-- → linha descartada. Ele aparecia na fila do Kanban (view v3) mas o cron
-- NUNCA o entregava. Também exigia ultima_interacao='cliente', excluindo o
-- importado que nunca interagiu (estado NULL).
-- FIX: mesma regra da view — sem venda registrada qualifica IMEDIATAMENTE, e
-- aceita estado 'cliente' OU NULL.
--
-- PROBLEMA 2 (risco de disparo com campanha desligada): se não existe campanha
-- rmkt ativa, v_camp ficava vazio, os COALESCE aplicavam defaults e a função
-- SEGUIA entregando leads. Com os importados agora elegíveis em massa, isso
-- poderia disparar remarketing com a campanha OFF.
-- FIX: sem campanha ativa/não-pausada → não entrega nada (a fila continua
-- visível no Kanban, mas nada sai). Desligar a campanha volta a ser garantia.
--
-- Ordem da fila: COALESCE(ultima_venda_em, created_at) — importados entram na
-- ordem em que foram cadastrados, sem furar fila de quem comprou há mais tempo.
-- ============================================================================

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

  -- SEM campanha ativa → NÃO dispara nada (a fila segue visível no Kanban).
  IF NOT FOUND THEN
    RETURN;
  END IF;

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
      -- 'cliente' OU importado que nunca interagiu (estado NULL)
      AND (c2.ultima_interacao = 'cliente' OR c2.ultima_interacao IS NULL)
      AND c2.telefone IS NOT NULL
      AND NOT COALESCE(c2.rmkt_bloqueado, false)
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND COALESCE(c2.rmkt_consecutive_silenciosos, 0) < v_max_envios
      AND (c2.data_ultimo_rmkt IS NULL
           OR c2.data_ultimo_rmkt < NOW() - (v_dias_gap || ' days')::INTERVAL)
      -- IMPORTADO (sem venda registrada) qualifica imediatamente; quem tem
      -- venda espera o gap por quantidade do último pedido.
      AND (
        c2.ultima_venda_em IS NULL
        OR c2.ultima_venda_em < NOW() - (
          CASE
            WHEN COALESCE(c2.qtd_ultimo_pedido, 1) BETWEEN 1 AND 2 THEN v_gap_1_2
            WHEN COALESCE(c2.qtd_ultimo_pedido, 1) BETWEEN 3 AND 5 THEN v_gap_3_5
            ELSE                                                       v_gap_5_plus
          END || ' days'
        )::INTERVAL
      )
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
      AND (c2.rmkt_reservado_ate IS NULL OR c2.rmkt_reservado_ate < NOW())
    ORDER BY COALESCE(c2.ultima_venda_em, c2.created_at) ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(uuid, integer)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

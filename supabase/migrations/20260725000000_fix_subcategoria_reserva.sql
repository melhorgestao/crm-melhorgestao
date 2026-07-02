-- ============================================================================
-- FIX: subcategoria do followup com reserva→confirma.
--
-- Bug: o claim reserva SEM incrementar follow_up_tentativas (o incremento
-- passou pro confirmar_envio_lead). Mas o RETURNING calculava a subcategoria
-- com CASE follow_up_tentativas (valor ANTIGO). Lead novo (tentativas=0) caía
-- no ELSE → '7d' em vez de '24h'. Followup do 1º disparo pegava template errado.
--
-- FIX: subcategoria baseada em (follow_up_tentativas + 1) = a tentativa que
-- ESTE disparo representa (o confirm vai incrementar pra esse valor).
-- ============================================================================

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

NOTIFY pgrst, 'reload schema';

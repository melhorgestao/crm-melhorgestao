-- ============================================================================
-- Rename da 1ª tentativa de follow-up: subcategoria '24h' -> '4h'.
--
-- A 1ª tentativa agora dispara em ~4h (silêncio), não 24h. O label ficava
-- mentindo ('24h'). Renomeia os templates E o claim juntos — o match é por
-- subcategoria, então os dois lados mudam na mesma migration e nada quebra
-- (o campanha_id dos templates é por id, não por subcategoria).
-- ============================================================================

UPDATE public.templates_msg
   SET subcategoria = '4h', updated_at = now()
 WHERE categoria = 'followup' AND subcategoria = '24h';

-- Claim: idêntico ao 20260819, só muda o label retornado '24h' -> '4h'.
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
      AND COALESCE(c2.data_ultimo_follow_up, c2.data_wait_follow_up, NOW() - INTERVAL '999 days') <
          NOW() - CASE (COALESCE(c2.follow_up_tentativas, 0) + 1)
                    WHEN 1 THEN INTERVAL '0'
                    WHEN 2 THEN INTERVAL '3 days'
                    ELSE     INTERVAL '7 days'
                  END
      AND (c2.follow_up_reservado_ate IS NULL OR c2.follow_up_reservado_ate < NOW())
    ORDER BY COALESCE(c2.data_ultimo_follow_up, c2.data_wait_follow_up) ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone,
            CASE (c.follow_up_tentativas + 1) WHEN 1 THEN '4h' WHEN 2 THEN '3d' ELSE '7d' END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

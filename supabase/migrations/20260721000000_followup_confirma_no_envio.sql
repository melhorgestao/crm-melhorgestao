-- ============================================================================
-- FIX DEFINITIVO: tag F-UP só aparece com disparo CONFIRMADO.
--
-- Bug: claim_proximo_lead_followup marcava ultima_interacao='follow_up' +
-- tentativa++ ANTES do envio. Se o fluxo saía sem enviar (escolhe_template
-- retorna NULL → "Template liberado?"=false, que não tem revert), o lead
-- ficava preso em follow_up sem ter recebido nada ("Enviados 0").
--
-- Solução (reserva → confirma):
--   1) claim RESERVA o lead (follow_up_reservado_ate = NOW()+5min) e devolve
--      dados, SEM mudar ultima_interacao/tentativa. Lock atômico (SKIP LOCKED)
--      evita reivindicação dupla. Leads reservados recentemente são pulados.
--   2) confirmar_envio_followup (chamada SÓ após envio OK) seta
--      ultima_interacao='follow_up' + tentativa++ + limpa a reserva.
--   3) Se o envio não acontece (template null, falha), o estado NUNCA mudou
--      → nada pra reverter, sem flicker. A reserva expira em 5min e o lead
--      volta a ser elegível.
--
-- subcategoria continua correta: CASE (tentativa + 1) → 24h/3d/7d.
-- ============================================================================

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS follow_up_reservado_ate timestamptz;

-- ----------------------------------------------------------------------------
-- 1) claim = RESERVA (não muda estado)
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
            CASE (c.follow_up_tentativas + 1) WHEN 1 THEN '24h' WHEN 2 THEN '3d' ELSE '7d' END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 2) confirmar_envio_followup = seta follow_up SÓ após envio confirmado
--    (no-op pra leads que não foram reservados, ex: rmkt)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirmar_envio_followup(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_novo text;
BEGIN
  UPDATE public.contatos
     SET ultima_interacao        = 'follow_up',
         follow_up_tentativas     = follow_up_tentativas + 1,
         data_ultimo_follow_up    = NOW(),
         follow_up_reservado_ate  = NULL,
         updated_at               = NOW()
   WHERE id = p_contato_id
     AND follow_up_reservado_ate IS NOT NULL
   RETURNING ultima_interacao INTO v_novo;

  RETURN jsonb_build_object('ok', true, 'confirmado', v_novo IS NOT NULL);
END $$;

GRANT EXECUTE ON FUNCTION public.confirmar_envio_followup(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 3) CLEANUP: leads presos em follow_up sem NENHUM envio confirmado
--    (marcados pelo bug antigo) → voltam pra wait_follow_up, tentativa--.
--    Reverte Elielson e demais que "marcaram F-UP sem disparar".
-- ----------------------------------------------------------------------------
UPDATE public.contatos c
   SET ultima_interacao      = 'wait_follow_up',
       follow_up_tentativas  = GREATEST(COALESCE(follow_up_tentativas, 1) - 1, 0),
       data_ultimo_follow_up = NULL,
       follow_up_reservado_ate = NULL,
       updated_at            = NOW()
 WHERE c.ultima_interacao = 'follow_up'
   AND NOT EXISTS (
     SELECT 1 FROM public.campanha_envios ce WHERE ce.contato_id = c.id
   );

NOTIFY pgrst, 'reload schema';

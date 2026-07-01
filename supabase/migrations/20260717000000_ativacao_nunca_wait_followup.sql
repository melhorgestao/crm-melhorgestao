-- ============================================================================
-- REGRA: lead que veio de ATIVAÇÃO (ativacao_tentativas > 0) NUNCA pode ficar
-- em wait_follow_up nem follow_up.
--
-- Como chegava lá: lead em ativacao_contatos responde → agent apresenta →
-- vira 'start' → cron start-timeout manda pra wait_follow_up → claim pega pra
-- follow_up. Sonaira/Lucia caíram nisso.
--
-- Enforcement em 3 camadas:
--   1) TRIGGER invariante (path-independent): qualquer escrita que tente pôr
--      um lead de ativação (ativacao_tentativas>0, não-cliente) em
--      wait_follow_up/follow_up é redirecionada pra 'ativacao_contatos'.
--   2) claim_proximo_lead_followup: exclui ativacao_tentativas>0 (não reivindica).
--   3) CLEANUP: os que já estão presos voltam pra ativacao_contatos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Trigger invariante
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.forca_ativacao_fora_followup()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.ultima_interacao IN ('wait_follow_up', 'follow_up')
     AND COALESCE(NEW.ativacao_tentativas, 0) > 0
     AND COALESCE(NEW.ja_comprou, false) = false THEN
    NEW.ultima_interacao       := 'ativacao_contatos';
    NEW.data_wait_follow_up    := NULL;
    NEW.data_ultimo_follow_up  := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ativacao_fora_followup ON public.contatos;
CREATE TRIGGER trg_ativacao_fora_followup
  BEFORE INSERT OR UPDATE OF ultima_interacao
  ON public.contatos
  FOR EACH ROW
  EXECUTE FUNCTION public.forca_ativacao_fora_followup();

-- ----------------------------------------------------------------------------
-- 2) claim_proximo_lead_followup: exclui leads de ativação
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_followup(uuid);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup(p_instancia_id uuid)
RETURNS TABLE (id uuid, nome text, telefone text, subcategoria text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao = 'follow_up',
      data_ultimo_follow_up = NOW(),
      follow_up_tentativas = follow_up_tentativas + 1,
      instancia_id = p_instancia_id,
      updated_at = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ultima_interacao = 'wait_follow_up'
      AND c2.ja_comprou = false
      AND c2.telefone IS NOT NULL
      AND COALESCE(c2.ativacao_tentativas, 0) = 0   -- NÃO reivindica leads de ativação
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.follow_up_tentativas < 3
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
      AND (c2.data_wait_follow_up < NOW() - INTERVAL '24 hours' OR c2.data_wait_follow_up IS NULL)
    ORDER BY c2.data_wait_follow_up ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone,
            CASE c.follow_up_tentativas WHEN 1 THEN '24h' WHEN 2 THEN '3d' ELSE '7d' END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 3) CLEANUP: leads de ativação presos em wait/follow_up → ativacao_contatos
-- ----------------------------------------------------------------------------
UPDATE public.contatos
   SET ultima_interacao      = 'ativacao_contatos',
       data_wait_follow_up   = NULL,
       data_ultimo_follow_up = NULL,
       follow_up_tentativas  = 0,
       updated_at            = NOW()
 WHERE ultima_interacao IN ('wait_follow_up', 'follow_up')
   AND COALESCE(ativacao_tentativas, 0) > 0
   AND COALESCE(ja_comprou, false) = false;

NOTIFY pgrst, 'reload schema';

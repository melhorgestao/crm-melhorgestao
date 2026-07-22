-- ============================================================================
-- AGENTE MUDO tem que valer TAMBÉM para campanhas (follow-up, rmkt, marketing,
-- ativação). FURO ENCONTRADO:
--
-- Os workflows de campanha buscam as instâncias em
--   /rest/v1/instancias?ativo=eq.true&status=eq.ativo
-- e NÃO filtram agente_mudo. Ou seja: com o toggle mudo ligado, o chip
-- restrito continuava sendo escolhido e continuava DISPARANDO follow-up/rmkt.
-- Cada tentativa dessas com o número restrito pela Meta é risco de agravar a
-- restrição — exatamente o que o toggle existe pra evitar.
--
-- A correção é feita no BANCO (não no n8n) de propósito: assim vale mesmo com
-- os workflows antigos já importados, sem depender de reimportar nada. Se a
-- instância está muda, nenhum lead é reservado pra ela — o claim volta vazio e
-- o workflow simplesmente não tem o que enviar.
--
-- COMO: renomeia cada claim_* existente para *_raw (sem tocar no corpo, que
-- continua sendo a versão vigente) e cria um wrapper com o nome original que
-- checa agente_mudo antes de delegar. Idempotente: se o _raw já existe, o
-- rename é pulado.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.instancia_esta_muda(p_instancia_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT i.agente_mudo FROM public.instancias i WHERE i.id = p_instancia_id), false)
$$;

COMMENT ON FUNCTION public.instancia_esta_muda(uuid) IS
  'true quando a instância está em MODO MUDO — nenhum envio automático pode sair por ela.';

-- helper de rename idempotente ------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN (
         'claim_proximo_lead_followup',
         'claim_proximo_lead_rmkt',
         'claim_proximo_lead_marketing',
         'claim_proximo_lead_ativacao'
       )
  LOOP
    -- só renomeia se ainda não existe o _raw correspondente
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p2
        JOIN pg_namespace n2 ON n2.oid = p2.pronamespace
       WHERE n2.nspname = 'public'
         AND p2.proname = r.proname || '_raw'
         AND pg_get_function_identity_arguments(p2.oid) = r.args
    ) THEN
      EXECUTE format('ALTER FUNCTION %s RENAME TO %I', r.sig, r.proname || '_raw');
      RAISE NOTICE 'renomeado: % -> %_raw', r.sig, r.proname;
    END IF;
  END LOOP;
END $$;

-- wrappers com a trava de modo mudo -------------------------------------------

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup(p_instancia_id uuid)
RETURNS TABLE (id uuid, nome text, telefone text, subcategoria text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.instancia_esta_muda(p_instancia_id) THEN RETURN; END IF;
  RETURN QUERY SELECT * FROM public.claim_proximo_lead_followup_raw(p_instancia_id);
END $$;

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id uuid,
  p_dias_gap     integer DEFAULT NULL
)
RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.instancia_esta_muda(p_instancia_id) THEN RETURN; END IF;
  RETURN QUERY SELECT * FROM public.claim_proximo_lead_rmkt_raw(p_instancia_id, p_dias_gap);
END $$;

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_marketing(
  p_instancia_id uuid,
  p_campanha_id  uuid
)
RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.instancia_esta_muda(p_instancia_id) THEN RETURN; END IF;
  RETURN QUERY SELECT * FROM public.claim_proximo_lead_marketing_raw(p_instancia_id, p_campanha_id);
END $$;

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_ativacao(
  p_instancia_id uuid,
  p_campanha     text DEFAULT NULL,
  p_dias_gap     integer DEFAULT 30
)
RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.instancia_esta_muda(p_instancia_id) THEN RETURN; END IF;
  RETURN QUERY SELECT * FROM public.claim_proximo_lead_ativacao_raw(p_instancia_id, p_campanha, p_dias_gap);
END $$;

GRANT EXECUTE ON FUNCTION public.instancia_esta_muda(uuid)                          TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(uuid)                  TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(uuid, integer)             TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_marketing(uuid, uuid)           TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_ativacao(uuid, text, integer)   TO authenticated, anon, service_role;

-- conferência: quais instâncias estão mudas agora
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT nome, agente_mudo FROM public.instancias WHERE agente_mudo LOOP
    RAISE NOTICE 'MODO MUDO ativo: instancia % — nenhum envio automatico sai por ela.', r.nome;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

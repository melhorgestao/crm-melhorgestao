-- ============================================================================
-- Invariante de schema: contatos INTERNO SEMPRE têm ultima_interacao = NULL.
--
-- Garantia em DOIS níveis:
--
-- 1) Trigger BEFORE INSERT OR UPDATE em public.contatos: zera o campo
--    sempre que canal_origem='INTERNO' OU canal_atual='INTERNO',
--    independente de QUEM esteja escrevendo (Edge Function, RPC, cron,
--    UI, agent — qualquer fonte). Imune a regressões futuras.
--
-- 2) CHECK constraint declarativa: torna o invariante explícito no schema
--    e bloqueia commit de qualquer estado inconsistente caso o trigger
--    seja desativado (fail-safe).
--
-- Também limpa state legado: qualquer INTERNO atualmente com
-- ultima_interacao != NULL é normalizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Normaliza legado ANTES de adicionar o CHECK (senão constraint quebra)
-- ----------------------------------------------------------------------------
UPDATE public.contatos
   SET ultima_interacao = NULL,
       estado_antes_suporte = NULL,
       updated_at = NOW()
 WHERE (canal_origem = 'INTERNO' OR canal_atual = 'INTERNO')
   AND ultima_interacao IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 1) Trigger BEFORE — força invariante na escrita
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.forca_interno_ultima_interacao_null()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.canal_origem = 'INTERNO' OR NEW.canal_atual = 'INTERNO' THEN
    NEW.ultima_interacao := NULL;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_forca_interno_ultima_interacao_null ON public.contatos;
CREATE TRIGGER trg_forca_interno_ultima_interacao_null
  BEFORE INSERT OR UPDATE
  ON public.contatos
  FOR EACH ROW
  EXECUTE FUNCTION public.forca_interno_ultima_interacao_null();

-- ----------------------------------------------------------------------------
-- 2) CHECK constraint — invariante declarativo
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_interno_sem_estado;
ALTER TABLE public.contatos ADD CONSTRAINT contatos_interno_sem_estado
  CHECK (
    (canal_origem != 'INTERNO' AND canal_atual != 'INTERNO')
    OR ultima_interacao IS NULL
  );

NOTIFY pgrst, 'reload schema';

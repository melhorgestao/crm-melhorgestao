-- ============================================================================
-- Garante canal_atual sempre populado.
-- UI passa a filtrar por canal_atual (estado real do contato),
-- não mais por canal_origem (que é histórico imutável).
-- ============================================================================

-- Backfill: copia canal_origem pra canal_atual onde tá NULL/vazio
UPDATE public.contatos
   SET canal_atual = canal_origem
 WHERE (canal_atual IS NULL OR canal_atual = '')
   AND canal_origem IS NOT NULL;

-- Garante que novos contatos nunca tenham canal_atual vazio se canal_origem existir
CREATE OR REPLACE FUNCTION public.trigger_canal_atual_default()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.canal_atual IS NULL OR NEW.canal_atual = '') AND NEW.canal_origem IS NOT NULL THEN
    NEW.canal_atual := NEW.canal_origem;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_canal_atual_default ON public.contatos;
CREATE TRIGGER trg_canal_atual_default
  BEFORE INSERT OR UPDATE OF canal_origem, canal_atual ON public.contatos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_canal_atual_default();

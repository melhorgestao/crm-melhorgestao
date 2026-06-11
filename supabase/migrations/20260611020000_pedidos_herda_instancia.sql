-- ============================================================================
-- Trigger: pedidos sem instancia_id herdam automaticamente do contato no INSERT.
-- Garante que workflows de rastreio/follow-up sempre encontrem o chip correto.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.pedidos_herda_instancia_contato()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.instancia_id IS NULL AND NEW.contato_id IS NOT NULL THEN
    SELECT instancia_id INTO NEW.instancia_id
      FROM public.contatos
     WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pedidos_herda_instancia ON public.pedidos;
CREATE TRIGGER trg_pedidos_herda_instancia
  BEFORE INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.pedidos_herda_instancia_contato();

NOTIFY pgrst, 'reload schema';

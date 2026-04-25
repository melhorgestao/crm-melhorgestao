-- Quando a UF de postagem é preenchida pela primeira vez, abater usando
-- processar_pedido_estoque_trigger (pedido_itens), em vez do JSON legado em pedidos.produto.

CREATE OR REPLACE FUNCTION public.trigger_uf_postagem_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uf_new text;
  v_uf_old text;
BEGIN
  v_uf_new := NULLIF(trim(COALESCE(NEW.uf_postagem, '')), '');
  v_uf_old := NULLIF(trim(COALESCE(OLD.uf_postagem, '')), '');

  IF NEW.representante_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF v_uf_new IS NOT NULL
     AND (v_uf_old IS NULL OR v_uf_old = '')
     AND NEW.estoque_processado = false
  THEN
    PERFORM public.processar_pedido_estoque_trigger(NEW.id, v_uf_new);
  END IF;

  RETURN NEW;
END;
$$;

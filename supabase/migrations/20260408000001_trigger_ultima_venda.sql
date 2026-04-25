-- Create trigger function to update ultima_venda_em on lancamentos_socios insert (VENDA only)
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = CURRENT_DATE WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;

CREATE TRIGGER trigger_update_ultima_venda
AFTER INSERT ON public.lancamentos_socios
FOR EACH ROW
EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- Create trigger to update ultima_venda_em when a pedido is created
-- Uses MAX(created_at) to always get the most recent order date
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_last_order_date date;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    -- Get the most recent order date for this contact
    SELECT MAX(created_at)::date INTO v_last_order_date 
    FROM pedidos WHERE contato_id = NEW.contato_id;
    
    UPDATE contatos SET ultima_venda_em = v_last_order_date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;

CREATE TRIGGER trigger_update_ultima_venda_pedido
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

NOTIFY pgrst, 'reload schema';
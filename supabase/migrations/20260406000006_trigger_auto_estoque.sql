-- Trigger automatico: todo novo pedido abate estoque automaticamente
-- Chama o RPC processar_pedido_estoque apos INSERT em pedidos

-- 1. Funcao de trigger
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM public.processar_pedido_estoque(NEW.id);
  RETURN NEW;
END;
$$;

-- 2. Remove trigger antiga se existir
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;

-- 3. Cria trigger automatica
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_processar_pedido_estoque();

NOTIFY pgrst, 'reload schema';

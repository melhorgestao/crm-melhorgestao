-- Parte 1: atualiza trigger existente
DROP TRIGGER IF EXISTS trg_uf_postagem_update ON public.pedidos;

-- Trigger recriado vai detectar mudança de qualquer UF
CREATE TRIGGER trg_uf_postagem_update 
AFTER UPDATE OF uf_postagem ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.trigger_uf_postagem_update();

SELECT 'Trigger ativado' as msg;
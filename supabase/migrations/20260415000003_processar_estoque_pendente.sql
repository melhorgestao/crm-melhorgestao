-- Processar estoque de pedidos pendentes (que ainda nao abateu)
-- Executar no Supabase SQL Editor

BEGIN;

-- Para cada pedido que tem itens e ainda nao processou estoque, rodar o abatimento
SELECT 
  p.id as pedido_id,
  p.uf_postagem,
  COUNT(pi.id) as total_itens,
  p.estoque_processado
FROM public.pedidos p
LEFT JOIN public.pedido_itens pi ON pi.pedido_id = p.id
WHERE p.estoque_processado IS NULL OR p.estoque_processado = false
GROUP BY p.id, p.uf_postagem, p.estoque_processado
ORDER BY p.created_at DESC
LIMIT 50;

COMMIT;

-- Para executar o abate em um pedido especifico:
-- SELECT processar_pedido_estoque_trigger('UUID_DO_PEDIDO', 'SP');

-- Para processar todos pendentes em loop:
-- CREATE OR REPLACE FUNCTION public.processar_todos_estoque_pendente()
-- RETURNS void
-- LANGUAGE plpgsql
-- AS $$
-- DECLARE
--   v_pedido record;
-- BEGIN
--   FOR v_pedido IN
--     SELECT id, uf_postagem FROM public.pedidos
--     WHERE (estoque_processado IS NULL OR estoque_processado = false)
--     AND EXISTS (SELECT 1 FROM pedido_itens WHERE pedido_id = pedidos.id)
--   LOOP
--     PERFORM public.processar_pedido_estoque_trigger(v_pedido.id, v_pedido.uf_postagem);
--   END LOOP;
-- END;
-- $$;
-- SELECT processar_todos_estoque_pendente();
-- Garante remoção do trigger legado que inseria saídas no INSERT (duplicava com criar_pedido/processar).
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque() CASCADE;

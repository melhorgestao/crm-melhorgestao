-- Add 'entregue' to status_pedido CHECK constraint
ALTER TABLE public.pedidos DROP CONSTRAINT IF EXISTS pedidos_status_pedido_check;
ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_status_pedido_check CHECK (status_pedido IN ('aguardando_rastreio', 'postado', 'entregue'));
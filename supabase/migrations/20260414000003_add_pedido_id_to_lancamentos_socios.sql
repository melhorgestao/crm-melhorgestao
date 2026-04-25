-- Adicionar coluna pedido_id em lancamentos_socios
-- Execute no Supabase SQL Editor

ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

CREATE INDEX IF NOT EXISTS idx_lancamentos_pedido ON public.lancamentos_socios(pedido_id) WHERE pedido_id IS NOT NULL;

-- Adiciona coluna representante_id à tabela pedidos
-- Rode no Supabase SQL Editor

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_pedidos_representante ON public.pedidos(representante_id) WHERE representante_id IS NOT NULL;

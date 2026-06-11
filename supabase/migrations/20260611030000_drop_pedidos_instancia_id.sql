-- ============================================================================
-- Remove pedidos.instancia_id — fonte de verdade é contatos.instancia_id.
-- Coluna foi adicionada em 20260406...fase1_schema mas nunca foi consumida
-- pela UI nem workflows (exceto o rastreio multi-instância recém criado,
-- que agora lê direto de contatos.instancia_id).
-- ============================================================================

-- Drop trigger que herdava instância do contato (não faz mais sentido)
DROP TRIGGER IF EXISTS trg_pedidos_herda_instancia ON public.pedidos;
DROP FUNCTION IF EXISTS public.pedidos_herda_instancia_contato();

-- Drop FK + coluna
ALTER TABLE public.pedidos DROP CONSTRAINT IF EXISTS pedidos_instancia_id_fkey;
ALTER TABLE public.pedidos DROP COLUMN IF EXISTS instancia_id;

NOTIFY pgrst, 'reload schema';

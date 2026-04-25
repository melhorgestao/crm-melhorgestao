-- Drop the incomplete criar_pedido_v2 function
DROP FUNCTION IF EXISTS public.criar_pedido_v2(uuid, text, numeric, text, text, text, text, text, jsonb);

-- Drop any conflicting INSERT triggers on pedidos that cause duplicate stock processing
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
DROP TRIGGER IF EXISTS trg_abate_estoque_pedido ON public.pedidos;
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;

-- Drop their associated functions if they exist
DROP FUNCTION IF EXISTS public.trigger_processar_pedido_estoque() CASCADE;
DROP FUNCTION IF EXISTS public.trigger_abate_estoque_pedido() CASCADE;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque() CASCADE;

-- Confirm only the safe triggers remain
SELECT 'Migration complete. Remaining triggers on pedidos:' as status;
SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.pedidos'::regclass AND NOT tgisinternal;
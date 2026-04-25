-- ==============================================================================
-- FIX: Remover funcoes criar_pedido duplicadas, manter apenas criar_pedido_v2
-- Execute no Supabase SQL Editor
-- ==============================================================================

BEGIN;

-- Drop todas as versoes antigas de criar_pedido (mantem argumentos diferentes)
DROP FUNCTION IF EXISTS public.criar_pedido(uuid, text, numeric, text, text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.criar_pedido(uuid, text, numeric, text, text, text, text, text, jsonb, uuid);
DROP FUNCTION IF EXISTS public.criar_pedido();

-- Verificar se criar_pedido_v2 existe
SELECT proname, pronargs 
FROM pg_proc 
WHERE proname = 'criar_pedido_v2';

COMMIT;
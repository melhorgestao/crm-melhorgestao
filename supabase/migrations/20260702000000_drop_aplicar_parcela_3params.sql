-- ============================================================================
-- Drop versão antiga de aplicar_parcela_pedido com 3 params (sem p_valor_caixa).
-- A versão de 4 params (com p_valor_caixa DEFAULT NULL) cobre todos os casos,
-- e PostgreSQL não conseguia escolher entre as duas:
--   ERROR: Could not choose the best candidate function between:
--          aplicar_parcela_pedido(uuid, numeric, text),
--          aplicar_parcela_pedido(uuid, numeric, text, numeric)
--
-- A versão de 4 params (mig 20260618030000) é a oficial:
--   - p_valor:       valor BRUTO da parcela (abate dívida)
--   - p_valor_caixa: opcional, lançamento na caixa (default = p_valor)
-- ============================================================================

DROP FUNCTION IF EXISTS public.aplicar_parcela_pedido(uuid, numeric, text);

-- Confirma que a versão de 4 params está acessível
GRANT EXECUTE ON FUNCTION public.aplicar_parcela_pedido(uuid, numeric, text, numeric)
  TO service_role, authenticated;

NOTIFY pgrst, 'reload schema';

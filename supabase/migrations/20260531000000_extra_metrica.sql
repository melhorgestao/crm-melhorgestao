-- ============================================================================
-- Feature: EXTRA_METRICA — lançamento sócio sem afetar métricas/custos
-- Usado para investimentos em maquinário, escritório, etc. que debitam saldo
-- do sócio mas NÃO afetam produção, logística, material, ADS — controle puro
-- de saldo financeiro.
-- ============================================================================

ALTER TABLE public.lancamentos_socios DROP CONSTRAINT IF EXISTS lancamentos_socios_tipo_check;
ALTER TABLE public.lancamentos_socios ADD CONSTRAINT lancamentos_socios_tipo_check
  CHECK (tipo IN (
    'VENDA', 'ADS', 'ETIQUETA', 'MATERIAL', 'LOGISTICA',
    'TRANSFERENCIA', 'LUCRO', 'CAPITAL_INICIAL', 'PARCELA_VENDA',
    'EXTRA_METRICA'
  ));

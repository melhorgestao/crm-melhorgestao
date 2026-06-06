-- ============================================================================
-- Feature: novos tipos de lançamento INFLUENCER e INFRAESTRUTURA
--
-- São custos REAIS que:
--   ✅ Aumentam custo total
--   ✅ Reduzem lucro
--   ❌ NÃO entram em custo de produção (só material)
--   ❌ NÃO entram em custo operacional (só logística + etiqueta)
--
-- Diferente do EXTRA_METRICA (que não afeta nenhuma métrica).
-- ============================================================================

ALTER TABLE public.lancamentos_socios DROP CONSTRAINT IF EXISTS lancamentos_socios_tipo_check;
ALTER TABLE public.lancamentos_socios ADD CONSTRAINT lancamentos_socios_tipo_check
  CHECK (tipo IN (
    'VENDA', 'ADS', 'ETIQUETA', 'MATERIAL', 'LOGISTICA',
    'TRANSFERENCIA', 'LUCRO', 'CAPITAL_INICIAL', 'PARCELA_VENDA',
    'EXTRA_METRICA', 'INFLUENCER', 'INFRAESTRUTURA'
  ));

-- ============================================================================
-- Bug fix: financeiro.categoria CHECK constraint não aceitava
-- 'influencer' e 'infraestrutura' → INSERT falhava silenciosamente,
-- valores ficavam só em lancamentos_socios mas não entravam em métricas.
-- ============================================================================

-- 1. Amplia CHECK constraint pra incluir as novas categorias
ALTER TABLE public.financeiro DROP CONSTRAINT IF EXISTS financeiro_categoria_check;
ALTER TABLE public.financeiro ADD CONSTRAINT financeiro_categoria_check
  CHECK (categoria IN ('ads', 'etiqueta', 'logistica', 'material', 'influencer', 'infraestrutura'));

-- 2. Backfill: lançamentos INFRAESTRUTURA/INFLUENCER que existem em
-- lancamentos_socios mas não em financeiro (devido ao bug acima)
INSERT INTO public.financeiro (tipo, valor, categoria, data, created_at)
SELECT
  'despesa',
  ABS(ls.valor),         -- lancamentos_socios armazena negativo; financeiro armazena positivo
  LOWER(ls.tipo),
  ls.data,
  ls.created_at
FROM public.lancamentos_socios ls
WHERE ls.tipo IN ('INFRAESTRUTURA', 'INFLUENCER')
  AND NOT EXISTS (
    SELECT 1 FROM public.financeiro f
    WHERE f.categoria = LOWER(ls.tipo)
      AND f.data = ls.data
      AND f.valor = ABS(ls.valor)
      AND f.tipo = 'despesa'
  );

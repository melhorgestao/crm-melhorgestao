
-- Remove os 3 lotes fantasma do Gummy criados em 2026-04-10
DELETE FROM public.lotes 
WHERE id IN (
  'c7376476-ee77-4115-a32a-07879806b49b',
  'ad2ad234-9f0c-44eb-871a-69fcf5bdba9c',
  'fb28a5bd-d9fa-421d-bbf1-fafb81676e55'
);

-- Recalcula estoque_atual do Gummy: soma entradas - soma saídas das movimentações
UPDATE public.produtos 
SET estoque_atual = (
  SELECT COALESCE(SUM(CASE WHEN tipo = 'entrada' THEN quantidade ELSE -quantidade END), 0)
  FROM public.estoque_movimentacoes 
  WHERE produto_id = '64482cf8-cc5c-4964-bc67-62fde991d06d'
)
WHERE id = '64482cf8-cc5c-4964-bc67-62fde991d06d';

-- Atualiza snapshot
SELECT public.atualizar_estoque_snapshot();

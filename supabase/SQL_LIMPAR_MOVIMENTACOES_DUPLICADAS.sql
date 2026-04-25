-- =============================================================================
-- RODAR NO Supabase → SQL Editor → New query → colar → Run
-- Limpa movimentações de saída duplicadas e recria corretamente a partir dos pedidos
-- =============================================================================

-- PASSO 1: Apagar TODAS as movimentações de saída (estão infladas/duplicadas)
DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida';

-- PASSO 2: Recriar movimentações limpas a partir dos PEDIDOS (fonte da verdade)
-- 2a) Pedidos com produto JSON array
INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, data)
SELECT
  (elem->>'produto_id')::uuid,
  (elem->>'quantidade')::int,
  'saida',
  'Venda',
  LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2),
  p.id,
  'Pedido #' || p.order_number::text,
  p.data
FROM public.pedidos p
CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
WHERE p.produto LIKE '[%'
  AND (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido') OR p.status_pedido IS NULL)
  AND (elem->>'produto_id') IS NOT NULL
  AND (elem->>'quantidade')::int > 0;

-- 2b) Pedidos com produto_id direto (não JSON)
INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, data)
SELECT
  p.produto_id,
  COALESCE(p.quantidade, 1),
  'saida',
  'Venda',
  LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2),
  p.id,
  'Pedido #' || p.order_number::text,
  p.data
FROM public.pedidos p
WHERE p.produto_id IS NOT NULL
  AND (p.produto IS NULL OR p.produto NOT LIKE '[%')
  AND (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido') OR p.status_pedido IS NULL);

-- PASSO 3: Atualizar snapshot de estoque
SELECT public.atualizar_estoque_snapshot();

-- PASSO 4: Verificação
SELECT 'MOVIMENTAÇÕES LIMPAS:' as info, COUNT(*) as total_saidas, SUM(quantidade) as total_unidades
FROM public.estoque_movimentacoes WHERE tipo = 'saida';

SELECT p.nome_oficial, COUNT(*) as movs, SUM(em.quantidade) as qty
FROM public.estoque_movimentacoes em
JOIN public.produtos p ON p.id = em.produto_id
WHERE em.tipo = 'saida'
GROUP BY p.nome_oficial
ORDER BY p.nome_oficial;

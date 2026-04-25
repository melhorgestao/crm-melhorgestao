-- ESTOQUE COM SNAPSHOT - DEBUGANDO O PROBLEMA
-- Executar no Supabase SQL Editor para entender o que acontece

BEGIN;

-- 1. Ver TODOS os pedido_itens
SELECT 
  pi.id,
  pi.pedido_id,
  pi.produto_id,
  pi.quantidade,
  p.status_pagamento,
  p.uf_postagem,
  pr.nome_oficial
FROM public.pedido_itens pi
INNER JOIN public.pedidos p ON p.id = pi.pedido_id
LEFT JOIN public.produtos pr ON pr.id = pi.produto_id
ORDER BY pi.created_at DESC
LIMIT 30;

-- 2. Ver quantos pedidos tem pedido_itens
SELECT 
  COUNT(DISTINCT pi.pedido_id) as pedidos_com_itens,
  COUNT(pi.id) as total_itens
FROM public.pedido_itens pi;

-- 3. Ver a soma exata de um produto especifico
SELECT 
  pi.produto_id,
  pr.nome_oficial,
  SUM(pi.quantidade) as total
FROM public.pedido_itens pi
INNER JOIN public.pedidos p ON p.id = pi.pedido_id
INNER JOIN public.produtos pr ON pr.id = pi.produto_id
WHERE p.status_pagamento IS NOT NULL
GROUP BY pi.produto_id, pr.nome_oficial
ORDER BY total DESC
LIMIT 10;

-- 4. Ver todos os pedidos SEM pedido_itens (que tem produto na coluna)
SELECT id, produto, quantidade, uf_postagem, status_pagamento FROM pedidos 
WHERE produto IS NOT NULL AND produto != 'geral'
ORDER BY created_at DESC
LIMIT 10;

COMMIT;
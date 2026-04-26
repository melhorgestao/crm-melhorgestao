-- Calcular estoque negativo baseado em PEDIDOS ANTIGOS (sem stock processado)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Ver quantos pedidos tem itens e NAO tem estoque_processado
SELECT 
  COUNT(*) as total_pedidos_pendentes,
  SUM(pi.quantidade) as total_itens,
  COUNT(DISTINCT uf_postagem) as ufs_distintas
FROM public.pedidos p
JOIN public.pedido_itens pi ON pi.pedido_id = p.id
WHERE p.status_pagamento = 'pago'
AND (p.estoque_processado IS NULL OR p.estoque_processado = false);

-- 2. Atualizar snapshot incluindo TODOS os pedidos (não apenas pendentes)
-- Isso vai mostrar o estoque NEGATIVO baseado nos pedidos ja feitos

-- Primeiro, verificar o que temos nos pedidos
SELECT 
  p.uf_postagem,
  pi.produto_id,
  pr.nome_oficial,
  SUM(pi.quantidade) as quantidade_pedida
FROM public.pedidos p
JOIN public.pedido_itens pi ON pi.pedido_id = p.id
JOIN public.produtos pr ON pr.id = pi.produto_id
WHERE p.status_pagamento = 'pago'
AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
GROUP BY p.uf_postagem, pi.produto_id, pr.nome_oficial
ORDER BY pr.nome_oficial, p.uf_postagem;

-- 3. Criar visualizacao direta do estoque com negativos (sem usar snapshot)
SELECT 
  pr.nome_oficial as produto,
  l.uf,
  COALESCE(SUM(l.quantidade_atual), 0) as entradas_lotes,
  COALESCE((
    SELECT SUM(pi.quantidade)
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    AND pi.produto_id = pr.id
    AND p.uf_postagem = l.uf
  ), 0) as saidas_pedidos_pendentes,
  COALESCE(SUM(l.quantidade_atual), 0) - COALESCE((
    SELECT SUM(pi.quantidade)
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    AND pi.produto_id = pr.id
    AND p.uf_postagem = l.uf
  ), 0) as saldo_estoque
FROM public.produtos pr
LEFT JOIN public.lotes l ON l.produto_id = pr.id
GROUP BY pr.id, pr.nome_oficial, l.uf
ORDER BY pr.nome_oficial, l.uf;

-- 4. TOTAL POR PRODUTO (soma de todas as UFs)
SELECT 
  pr.nome_oficial as produto,
  COALESCE(SUM(l.quantidade_atual), 0) as total_entradas,
  COALESCE((
    SELECT SUM(pi.quantidade)
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    AND pi.produto_id = pr.id
  ), 0) as total_saidas_pedidos,
  COALESCE(SUM(l.quantidade_atual), 0) - COALESCE((
    SELECT SUM(pi.quantidade)
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    AND pi.produto_id = pr.id
  ), 0) as saldo_total
FROM public.produtos pr
LEFT JOIN public.lotes l ON l.produto_id = pr.id
GROUP BY pr.id, pr.nome_oficial
ORDER BY pr.nome_oficial;

COMMIT;
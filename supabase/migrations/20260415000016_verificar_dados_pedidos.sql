-- VERIFICAR DADOS DOS PEDIDOS
-- Execute no Supabase SQL Editor para ver o que tem

-- Ver total de pedidos
SELECT 'pedidos' as tabela, COUNT(*) as total FROM pedidos
UNION ALL
SELECT 'pedido_itens', COUNT(*) FROM pedido_itens
UNION ALL
SELECT 'pedidos com itens', COUNT(DISTINCT p.id) FROM pedidos p JOIN pedido_itens pi ON pi.pedido_id = p.id;

-- Ver pedidos que tem itens
SELECT p.id, p.status_pagamento, p.uf_postagem, COUNT(pi.id) as itens
FROM pedidos p
LEFT JOIN pedido_itens pi ON pi.pedido_id = p.id
GROUP BY p.id, p.status_pagamento, p.uf_postagem
ORDER BY p.created_at DESC
LIMIT 20;

-- Ver se pedido_itens tem dados
SELECT * FROM pedido_itens LIMIT 10;
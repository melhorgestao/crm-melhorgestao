-- DEBUG: Ver exatamente quantos pedidos a query retorna
-- Execute no Supabase SQL Editor

-- Ver quantos pedidos tem produto preenchido
SELECT 
  COUNT(*) as total_pedidos_com_produto,
  SUM(CASE WHEN status_pagamento = 'pago' THEN 1 ELSE 0 END) as pagos,
  SUM(CASE WHEN status_pagamento != 'pago' THEN 1 ELSE 0 END) as pendentes
FROM pedidos 
WHERE produto IS NOT NULL AND trim(produto) <> '';

-- Ver se uf_postagem tem valores
SELECT 
  COUNT(*) as com_uf_postagem,
  COUNT(*) as sem_uf_postagem
FROM pedidos 
WHERE produto IS NOT NULL;

-- Verificar pedido_itens
SELECT COUNT(*) as total_itens FROM pedido_itens;

-- Verificar primeiro pedido_itens
SELECT pi.*, p.uf_postagem, p.status_pagamento
FROM pedido_itens pi
JOIN pedidos p ON p.id = pi.pedido_id
LIMIT 10;
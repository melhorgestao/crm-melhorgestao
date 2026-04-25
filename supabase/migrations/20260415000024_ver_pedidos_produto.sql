-- VER TODOS OS PEDIDOS E SUA COLUNA PRODUTO
-- Execute no Supabase SQL Editor

SELECT id, produto, quantidade, uf_postagem, status_pagamento, created_at 
FROM pedidos 
WHERE produto IS NOT NULL 
ORDER BY created_at DESC 
LIMIT 30;
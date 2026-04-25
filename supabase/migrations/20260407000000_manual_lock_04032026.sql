-- Manual lock: lock all delivered orders and paid vendas from 03/04/2026 and before
-- Execute this to lock past data immediately

-- Lock all delivered orders from 03/04/2026 and before
UPDATE public.pedidos
SET locked_at = now()
WHERE status_pedido = 'entregue'
  AND locked_at IS NULL
  AND data <= '2026-04-03';

-- Lock all paid vendas (lancamentos_socios) from 03/04/2026 and before
UPDATE public.lancamentos_socios
SET locked_at = now()
WHERE tipo = 'VENDA'
  AND (status_pagamento = 'pago' OR status_pagamento IS NULL OR status_pagamento = '')
  AND locked_at IS NULL
  AND data <= '2026-04-03';

-- ESTOQUE NEGATIVO - TODOS OS PEDIDOS (SEM SNAPSHOT)
-- Executar no Supabase SQL Editor

BEGIN;

-- Limpar coluna estoque_processado para considerar todos os pedidos
UPDATE public.pedidos SET estoque_processado = NULL WHERE estoque_processado IS NOT NULL;

-- Função que calcula: lotes - TODOS pedidos pagos (sem exception)
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH 
  lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  todos_pedidos AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'  -- TODOS pedidos pagos!
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.pid, ped.pid) as produto_id,
    COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome,
    COALESCE(l.uff, ped.uff) as uf,
    COALESCE(l.total_lote, 0) as entradas,
    COALESCE(ped.total_pedido, 0) as saidas_pedidos,
    (COALESCE(l.total_lote, 0) - COALESCE(ped.total_pedido, 0)) as saldo
  FROM lotes_calc l
  FULL OUTER JOIN todos_pedidos ped ON ped.pid = l.pid AND ped.uff = l.uff
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.pid, ped.pid)
  WHERE l.total_lote > 0 OR ped.total_pedido > 0
  ORDER BY pr.nome_oficial, COALESCE(l.uff, ped.uff);
END;
$$;

-- Verificar total de pedidos pagos
SELECT COUNT(*), SUM(quantidade) as total_itens FROM pedidos WHERE status_pagamento = 'pago';

-- Verificar resultado
SELECT * FROM get_estoque_completo() ORDER BY produto_nome;

-- Atualizar estoque_atual nos produtos
UPDATE public.produtos p
SET estoque_atual = COALESCE((
  SELECT SUM(saldo) 
  FROM public.get_estoque_completo() 
  WHERE produto_id = p.id
), 0);

COMMIT;
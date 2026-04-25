-- ESTOQUE NEGATIVO via fetch RPC
-- Executar no Supabase SQL Editor

BEGIN;

-- Função principal
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
  pedidos_calc AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.pid, ped.pid) as produto_id,
    COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome,
    COALESCE(l.uff, ped.uff) as uf,
    COALESCE(l.total_lote, 0) as entradas,
    COALESCE(ped.total_pedido, 0) as saidas_pedidos,
    COALESCE(l.total_lote, 0) - COALESCE(ped.total_pedido, 0) as saldo
  FROM lotes_calc l
  FULL OUTER JOIN pedidos_calc ped ON ped.pid = l.pid AND ped.uff = l.uff
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.pid, ped.pid)
  WHERE l.total_lote > 0 OR ped.total_pedido > 0
  ORDER BY pr.nome_oficial, COALESCE(l.uff, ped.uff);
END;
$$;

COMMIT;

-- Testar
SELECT * FROM get_estoque_completo() ORDER BY produto_nome;
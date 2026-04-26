-- ESTOQUE USANDO COLUNA PRODUTO DO PEDIDO
-- Execute TODO este SQL de uma vez no Supabase SQL Editor

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH todos_pedidos AS (
    SELECT p.id as pedido_id, p.produto as produto_json, p.quantidade as qtd_total, p.uf_postagem as uf, p.status_pagamento as status
    FROM public.pedidos p
    WHERE p.produto IS NOT NULL AND p.produto <> 'geral' AND p.status_pagamento IS NOT NULL
  ),
  produtos_pedido AS (
    SELECT tp.pedido_id, tp.uf,
      CASE 
        WHEN tp.produto_json LIKE '[%' THEN 
          (SELECT (jsonb_array_elements(tp.produto_json::jsonb)->>'produto_id')::uuid)
        ELSE NULL
      END as prod_id,
      tp.qtd_total as qtd
    FROM todos_pedidos tp
  ),
  agg_pedidos AS (
    SELECT pp.prod_id, pp.uf, SUM(pp.qtd)::integer as total_saida
    FROM produtos_pedido pp WHERE pp.prod_id IS NOT NULL
    GROUP BY pp.prod_id, pp.uf
  ),
  lotes_agg AS (
    SELECT l.produto_id as pid, l.uf, SUM(l.quantidade_atual)::integer as total_entrada
    FROM public.lotes l WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, l.uf
  ),
  produtos AS (SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true)
  SELECT 
    COALESCE(la.pid, ap.prod_id, pr.pid) as prod_id,
    COALESCE(pr.pnome, 'Desconhecido') as prod_nome,
    COALESCE(la.uf, ap.uf, 'SP') as estado,
    COALESCE(la.total_entrada, 0)::integer as entrada,
    COALESCE(ap.total_saida, 0)::integer as saida,
    (COALESCE(la.total_entrada, 0) - COALESCE(ap.total_saida, 0))::integer as saldo
  FROM produtos pr
  LEFT JOIN lotes_agg la ON la.pid = pr.pid
  LEFT JOIN agg_pedidos ap ON ap.prod_id = pr.pid
  WHERE la.total_entrada > 0 OR ap.total_saida > 0
  ORDER BY pr.pnome, COALESCE(la.uf, ap.uf, 'SP');
END;
$$;

SELECT * FROM get_estoque_completo();

COMMIT;
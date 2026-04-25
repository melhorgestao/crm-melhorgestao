-- MOSTRAR TODOS produtos com entrada (mesmo sem venda)
DROP FUNCTION IF EXISTS public.get_estoque_completo();

CREATE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH entradas AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_atual)::int as qtd_ent
    FROM public.lotes l WHERE l.quantidade_atual > 0 GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(p.quantidade)::int as qtd_sai
    FROM public.pedidos p WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL
    GROUP BY p.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(e.pid, s.pid) as prod_id,
    pr.nome_oficial as prod_nome,
    COALESCE(e.uff, s.uff) as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM public.produtos pr
  LEFT JOIN entradas e ON e.pid = pr.id
  LEFT JOIN saidas s ON s.pid = pr.id
  WHERE COALESCE(e.qtd_ent, 0) > 0
  ORDER BY pr.nome_oficial;
END;
$$;

-- CORRIGIR get_estoque_completo para mostrar ATÉ mesmo produtos só com entrada
BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();

CREATE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_atual)::int as qtd_ent
    FROM public.lotes l 
    WHERE l.quantidade_atual > 0 
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas_produto_id AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, p.quantidade as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL
  ),
  itens_json AS (
    SELECT 
      (jsonb_array_elements(p.produto::jsonb)->>'produto_id')::uuid as pid,
      COALESCE(p.uf_postagem, 'SP') as uff,
      (jsonb_array_elements(p.produto::jsonb)->>'quantidade')::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto LIKE '[%'
  ),
  todas_saidas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM saidas_produto_id WHERE pid IS NOT NULL GROUP BY pid, uff
    UNION ALL
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM itens_json WHERE pid IS NOT NULL GROUP BY pid, uff
  ),
  saidas AS (
    SELECT pid, uff, SUM(qtd_sai)::int as qtd_sai FROM todas_saidas GROUP BY pid, uff
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    COALESCE(e.uff, 'SP') as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM produtos_ativos pr
  LEFT JOIN entradas e ON e.pid = pr.pid
  LEFT JOIN saidas s ON s.pid = pr.pid
  ORDER BY pr.pnome, COALESCE(e.uff, 'SP');
END;
$$;

SELECT * FROM get_estoque_completo() ORDER BY prod_nome, estado;
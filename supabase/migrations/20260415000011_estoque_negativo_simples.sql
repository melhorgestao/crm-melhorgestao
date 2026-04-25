-- Estoque negativo calculado no frontend
-- Executar NO SUPABASE SQL APENAS para criar função de suporte (se precisar)

-- Esta função calcula negativo: lotes - pedidos pagos
CREATE OR REPLACE FUNCTION public.get_estoque_negativo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  saldo integer
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH lotes_agg AS (
    SELECT l.produto_id, l.uf, SUM(l.quantidade_atual)::integer as entrada
    FROM public.lotes l
    GROUP BY l.produto_id, l.uf
  ),
  pedidos_agg AS (
    SELECT pi.produto_id, p.uf_postagem as uf, SUM(pi.quantidade)::integer as saida
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago' AND p.uf_postagem IS NOT NULL
    GROUP BY pi.produto_id, p.uf_postagem
  )
  SELECT 
    COALESCE(l.produto_id, pa.produto_id),
    COALESCE(pr.nome_oficial, '—'),
    COALESCE(l.uf, pa.uf),
    COALESCE(l.entrada, 0) - COALESCE(pa.saida, 0)
  FROM lotes_agg l
  FULL JOIN pedidos_agg pa ON pa.produto_id = l.produto_id AND pa.uf = l.uf
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.produto_id, pa.produto_id)
  WHERE l.entrada > 0 OR pa.saida > 0;
END;
$$;

-- Testar
SELECT * FROM get_estoque_negativo();
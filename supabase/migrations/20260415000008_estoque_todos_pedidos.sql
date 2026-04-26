-- ESTOQUE NEGATIVO BASEADO EM TODOS OS PEDIDOS PAGOS
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Função que considera TODOS os pedidos pagos (não apenas pendentes)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
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
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH base_lotes AS (
    SELECT l.produto_id, l.uf, SUM(l.quantidade_atual) as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, l.uf
  ),
  base_pedidos AS (
    SELECT 
      pi.produto_id,
      p.uf_postagem as uf,
      SUM(pi.quantidade) as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'  -- TODOS os pedidos pagos!
    GROUP BY pi.produto_id, p.uf_postagem
  )
  SELECT 
    COALESCE(l.produto_id, p.produto_id) as produto_id,
    COALESCE(pr.nome_oficial, '—') as produto_nome,
    COALESCE(l.uf, p.uf) as uf,
    COALESCE(l.total_lote, 0)::integer as entradas,
    COALESCE(p.total_pedido, 0)::integer as saidas_pedidos,
    (COALESCE(l.total_lote, 0) - COALESCE(p.total_pedido, 0))::integer as saldo
  FROM base_lotes l
  FULL OUTER JOIN base_pedidos p ON p.produto_id = l.produto_id AND p.uf = l.uf
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.produto_id, p.produto_id)
  WHERE l.total_lote IS NOT NULL OR p.total_pedido IS NOT NULL
  ORDER BY pr.nome_oficial, COALESCE(l.uf, p.uf);
END;
$$;

-- 2. RPC para frontend
CREATE OR REPLACE FUNCTION public.buscar_estoque_completo()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT produto_id, produto_nome, uf, entradas, saidas_pedidos, saldo 
    FROM public.get_estoque_completo()
  ) t;
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 3. Testar para ver os dados
SELECT * FROM public.get_estoque_completo() ORDER BY produto_nome, uf;

-- 4. Atualizar estoque_atual na tabela produtos
UPDATE public.produtos p
SET estoque_atual = COALESCE((
  SELECT SUM(saldo) 
  FROM public.get_estoque_completo() 
  WHERE produto_id = p.id
), 0);

COMMIT;
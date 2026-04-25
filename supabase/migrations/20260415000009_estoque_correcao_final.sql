-- ESTOQUE NEGATIVO - CORRECAO FINAL
-- Executar no Supabase SQL Editor - TODO DE UMA VEZ

BEGIN;

-- 1. Limpar qualquer dado existente
DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida';
UPDATE public.pedidos SET estoque_processado = NULL;

-- 2. Criar funcao de estoque considerando TODOS os pedidos pagos
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
  WITH lotess AS (
    SELECT produto_id, uf, COALESCE(SUM(quantidade_atual), 0) as total_lote
    FROM public.lotes
    GROUP BY produto_id, uf
  ),
  pedidoss AS (
    SELECT 
      pi.produto_id,
      COALESCE(p.uf_postagem, 'SP') as uf,
      SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.produto_id, p.produto_id) as produto_id,
    COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome,
    COALESCE(l.uf, p.uf) as uf,
    l.total_lote as entradas,
    p.total_pedido as saidas_pedidos,
    (l.total_lote - p.total_pedido) as saldo
  FROM lotess l
  FULL OUTER JOIN pedidoss p ON p.produto_id = l.produto_id AND p.uf = l.uf
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.produto_id, p.produto_id)
  WHERE l.total_lote > 0 OR p.total_pedido > 0
  ORDER BY pr.nome_oficial, COALESCE(l.uf, p.uf);
END;
$$;

-- 3. Criar RPC wrapper
CREATE OR REPLACE FUNCTION public.buscar_estoque_completo()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT produto_id, produto_nome, uf, entradas, saidas_pedidos, saldo 
    FROM public.get_estoque_completo()
    ORDER BY produto_nome, uf
  ) t;
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 4. Verificar o resultado
SELECT * FROM public.get_estoque_completo() LIMIT 20;

COMMIT;
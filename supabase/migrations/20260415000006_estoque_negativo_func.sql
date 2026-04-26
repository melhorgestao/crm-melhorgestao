-- ESTOQUE COMPLETO COM NEGATIVO (lotes - pedidos pendentes)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Criar funcao que retorna estoque com negativo dinamico
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
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, l.uf
  ),
  base_pedidos AS (
    SELECT 
      pi.produto_id,
      p.uf_postagem as uf,
      SUM(pi.quantidade) as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
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

-- 2. Criar funcao para atualizar estoque_atual nos produtos (com negativo)
CREATE OR REPLACE FUNCTION public.atualizar_estoque_produtos()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reg record;
BEGIN
  FOR v_reg IN
    SELECT produto_id, SUM(saldo) as saldo_total
    FROM public.get_estoque_completo()
    GROUP BY produto_id
  LOOP
    UPDATE public.produtos
    SET estoque_atual = v_reg.saldo_total
    WHERE id = v_reg.produto_id;
  END LOOP;
END;
$$;

-- 3. Executar atualizacao imediatamente
SELECT public.atualizar_estoque_produtos();

COMMIT;

-- Verificar estoque negativo:
-- SELECT * FROM get_estoque_completo();
-- ESTOQUE - CONSIDERA TODOS OS PEDIDOS (sem依赖 de pedido_itens)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Dropar e recriar tabela snapshot
DROP TABLE IF EXISTS public.estoque_snapshot;

CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id uuid,
  uf text,
  entradas integer DEFAULT 0,
  saidas_pedidos integer DEFAULT 0,
  saldo_calculado integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 2. Função que calcula: lotes - TODOS os pedidos (usa coluna produto do pedido)
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(produto_id uuid, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  -- Entradas dos lotes
  WITH lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  -- Saidas: soma quantidade de TODOS os pedidos com produto
  pedidos_calc AS (
    SELECT 
      p.id as pedido_id,
      p.uf_postagem,
      CASE 
        WHEN p.produto IS NOT NULL AND p.produto LIKE '[%' THEN  -- JSON array
          (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p.produto::jsonb) x WHERE x->>'produto_id' IS NOT NULL)
        WHEN p.produto IS NOT NULL AND p.produto LIKE '%{%' THEN  -- nested JSON
          (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p.produto::jsonb->0->'produtos') x)
        ELSE 
          COALESCE(p.quantidade, 1)  -- fallback
      END as quantidade_total
    FROM public.pedidos p
    WHERE p.produto IS NOT NULL AND trim(p.produto) <> ''
  ),
  pedidos_agg AS (
    SELECT 
      COALESCE(p.uf_postagem, 'SP') as uff,
      SUM(p.quantidade_total)::integer as total_pedido
    FROM pedidos_calc p
    GROUP BY COALESCE(p.uf_postagem, 'SP')
  )
  -- Por agora, vou somar apenas o total sem distinção de produto
  SELECT 
    l.pid,
    l.uff,
    COALESCE(l.total_lote, 0) as entradas,
    COALESCE((SELECT SUM(quantidade_total) FROM pedidos_calc), 0) as saidas_pedidos,
    COALESCE(l.total_lote, 0) - COALESCE((SELECT SUM(quantidade_total) FROM pedidos_calc), 0) as saldo
  FROM lotes_calc l;
END;
$$;

-- 3. Simpler version - apenas soma todos os pedidos
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(produto_id uuid, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  -- Primeiro: ver quanto temos em lotes por UF
  WITH lotes_por_uf AS (
    SELECT l.produto_id, l.uf, SUM(l.quantidade_atual) as qtd_lote
    FROM public.lotes l
    GROUP BY l.produto_id, l.uf
  ),
  -- Segundo: somar TODOS os pedidos (qualquer status)
  todos_pedidos AS (
    SELECT 
      SUM(
        CASE 
          WHEN p.produto IS NOT NULL AND p.produto LIKE '[%' THEN
            COALESCE((SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p.produto::jsonb) x), p.quantidade)
          ELSE COALESCE(p.quantidade, 1)
        END
      )::integer as total_geral
    FROM public.pedidos p
    WHERE p.produto IS NOT NULL AND p.status_pagamento IS NOT NULL
  )
  -- Por UF, retorna entradas = lotes, saidas = soma de todos os pedidos
  SELECT 
    NULL::uuid as produto_id,
    'SP'::text as uf,
    COALESCE((SELECT SUM(qtd_lote) FROM lotes_por_uf), 0) as entradas,
    COALESCE((SELECT total_geral FROM todos_pedidos), 0) as saidas_pedidos,
    COALESCE((SELECT SUM(qtd_lote) FROM lotes_por_uf), 0) - COALESCE((SELECT total_geral FROM todos_pedidos), 0) as saldo;
END;
$$;

-- 4. Ver quantos pedidos temos
SELECT COUNT(*) as total_pedidos FROM pedidos WHERE produto IS NOT NULL;
SELECT SUM(quantidade) as total_itens_pedidos FROM pedidos WHERE produto IS NOT NULL;

-- 5. Testar função
SELECT * FROM calcular_estoque();

COMMIT;
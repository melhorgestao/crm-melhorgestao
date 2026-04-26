-- ESTOQUE COM SNAPSHOT - TODOS OS PEDIDOS (PAGOS + PENDENTES)
-- Executar no Supabase SQL Editor - TODO DE UMA VEZ

BEGIN;

-- 1. Dropar tabela snapshot se existir e recriar com colunas corretas
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

-- 2. Função que calcula: lotes - TODOS os pedidos (pagos + pendentes)
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(produto_id uuid, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  todos_pedidos AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT COALESCE(l.pid, ped.pid) as produto_id, COALESCE(l.uff, ped.uff) as uf,
    COALESCE(l.total_lote, 0) as entradas, COALESCE(ped.total_pedido, 0) as saidas_pedidos,
    (COALESCE(l.total_lote, 0) - COALESCE(ped.total_pedido, 0)) as saldo
  FROM lotes_calc l
  FULL OUTER JOIN todos_pedidos ped ON ped.pid = l.pid AND ped.uff = l.uff
  WHERE l.total_lote > 0 OR ped.total_pedido > 0;
END;
$$;

-- 3. Função para atualizar snapshot
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  INSERT INTO public.estoque_snapshot (produto_id, uf, entradas, saidas_pedidos, saldo_calculado, atualizado_em)
  SELECT produto_id, uf, entradas, saidas_pedidos, saldo, now() FROM public.calcular_estoque();
  UPDATE public.produtos p SET estoque_atual = COALESCE((SELECT SUM(saldo_calculado) FROM public.estoque_snapshot WHERE produto_id = p.id), 0);
END;
$$;

-- 4. Função RPC que busca do snapshot (frontend usa fetch)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(produto_id uuid, produto_nome text, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT es.produto_id, COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome, es.uf, es.entradas, es.saidas_pedidos, es.saldo_calculado
  FROM public.estoque_snapshot es
  LEFT JOIN public.produtos pr ON pr.id = es.produto_id
  ORDER BY pr.nome_oficial, es.uf;
END;
$$;

-- 5. Atualizar snapshot agora!
SELECT public.atualizar_estoque_snapshot();

-- 6. Verificar
SELECT * FROM public.get_estoque_completo() ORDER BY produto_nome;

COMMIT;
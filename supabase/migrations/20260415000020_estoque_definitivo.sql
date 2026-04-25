-- ESTOQUE FINAL - TODOS OS PEDIDOS, TODOS OS PRODUTOS
-- Executar no Supabase SQL Editor - TODO DE UMA VEZ

BEGIN;

-- 0. Primeiro: permitir nulo na coluna estoque_processado
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado DROP NOT NULL;
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado SET DEFAULT false;

-- 1. Criar/atualizar tabela snapshot
DROP TABLE IF EXISTS public.estoque_snapshot;

CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada integer DEFAULT 0,
  saida integer DEFAULT 0,
  saldo integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 2. Função principal: lotes - TODOS os pedidos
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH todos_produtos AS (
    SELECT id as pid, nome_oficial as nome FROM public.produtos WHERE ativo = true
  ),
  todos_lotes AS (
    SELECT l.produto_id as l_pid, COALESCE(l.uf, 'SP') as l_est, SUM(l.quantidade_atual)::integer as l_qtd
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  todos_pedidos AS (
    SELECT pi.produto_id as p_pid, COALESCE(p.uf_postagem, 'SP') as p_est, SUM(pi.quantidade)::integer as p_qtd
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(tl.l_pid, tp_est.p_pid, tp.pid) as prod_id,
    tp.nome as prod_nome,
    COALESCE(tl.l_est, tp_est.p_est, 'SP') as estado,
    COALESCE(tl.l_qtd, 0)::integer as entrada,
    COALESCE(tp_est.p_qtd, 0)::integer as saida,
    (COALESCE(tl.l_qtd, 0) - COALESCE(tp_est.p_qtd, 0))::integer as saldo
  FROM todos_produtos tp
  LEFT JOIN todos_lotes tl ON tl.l_pid = tp.pid
  LEFT JOIN todos_pedidos tp_est ON tp_est.p_pid = tp.pid
  ORDER BY tp.nome, COALESCE(tl.l_est, tp_est.p_est, 'SP');
END;
$$;

-- 3. Função atualizar snapshot
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, atualizado_em)
  SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now() FROM public.calcular_estoque();
  UPDATE public.produtos p SET estoque_atual = COALESCE((SELECT SUM(saldo) FROM public.estoque_snapshot WHERE prod_id = p.id), 0) WHERE p.id IS NOT NULL;
END;
$$;

-- 4. Função RPC para frontend
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT es.prod_id, es.prod_nome, es.estado, es.entrada, es.saida, es.saldo
  FROM public.estoque_snapshot es
  WHERE es.entrada > 0 OR es.saida > 0 OR es.saldo != 0
  ORDER BY es.prod_nome, es.estado;
END;
$$;

-- 5. Atualizar snapshot AGORA!
SELECT public.atualizar_estoque_snapshot();

-- 6. Verificar: mostrar todos os produtos com pedidos
SELECT prod_nome, estado, entrada, saida, saldo FROM public.estoque_snapshot ORDER BY prod_nome, estado;

COMMIT;
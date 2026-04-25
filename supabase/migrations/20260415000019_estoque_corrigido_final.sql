-- ESTOQUE CORRIGIDO - Fix ambiguous column
-- Executar no Supabase SQL Editor

BEGIN;

-- 0. Dropar funções existentes
DROP FUNCTION IF EXISTS public.get_estoque_completo();
DROP FUNCTION IF EXISTS public.atualizar_estoque_snapshot();
DROP FUNCTION IF EXISTS public.calcular_estoque();

-- 1. Criar tabela snapshot
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

-- 2. calcular_estoque()
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as nome FROM public.produtos WHERE ativo = true
  ),
  lotes_por_produto AS (
    SELECT l.produto_id as pid, l.uf as estado, SUM(l.quantidade_atual) as qtd_lote
    FROM public.lotes l
    GROUP BY l.produto_id, l.uf
  ),
  pedidos_por_produto AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as estado, SUM(pi.quantidade)::integer as qtd_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.pid, ped.pid, pa.pid) as prod_id,
    COALESCE(pa.nome, 'Desconhecido') as prod_nome,
    COALESCE(l.estado, ped.estado, 'SP') as estado,
    COALESCE(l.qtd_lote, 0)::integer as entrada,
    COALESCE(ped.qtd_pedido, 0)::integer as saida,
    (COALESCE(l.qtd_lote, 0) - COALESCE(ped.qtd_pedido, 0))::integer as saldo
  FROM produtos_ativos pa
  LEFT JOIN lotes_por_produto l ON l.pid = pa.pid
  LEFT JOIN pedidos_por_produto ped ON ped.pid = pa.pid
  WHERE COALESCE(l.qtd_lote, 0) > 0 OR COALESCE(ped.qtd_pedido, 0) > 0
  ORDER BY pa.nome, COALESCE(l.estado, ped.estado, 'SP');
END;
$$;

-- 3. atualizar_estoque_snapshot()
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
  UPDATE public.produtos p SET estoque_atual = COALESCE((SELECT SUM(saldo) FROM public.estoque_snapshot WHERE prod_id = p.id), 0);
END;
$$;

-- 4. get_estoque_completo() - busca do snapshot
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
  ORDER BY es.prod_nome, es.estado;
END;
$$;

-- 5. Atualizar snapshot
SELECT public.atualizar_estoque_snapshot();

-- Verificar
SELECT * FROM public.get_estoque_completo();

COMMIT;
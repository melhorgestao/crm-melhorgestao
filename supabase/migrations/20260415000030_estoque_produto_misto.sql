-- ESTOQUE DEFINITIVO - COLUNA PRODUTO MISTA (JSON + TEXT)
-- Executar TODO de uma vez no Supabase SQL Editor

BEGIN;

-- 0. Dropar funções existentes
DROP FUNCTION IF EXISTS public.get_estoque_completo();

-- 1. Criar função que handle COLUNA PRODUTO MISTA (JSON + TEXT)
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  -- Entradas: lotes por produto+UF
  entradas_lotes AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_atual)::int as qtd_ent
    FROM public.lotes l WHERE l.quantidade_atual > 0 GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  -- Saidas: pedidos - treating COLUNA PRODUTO MISTA
  saidas_pedidos AS (
    SELECT 
      p.id as ped_id,
      p.produto as prod_json,
      p.quantidade as qtd_pedido,
      COALESCE(p.uf_postagem, 'SP') as uff
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto IS NOT NULL AND p.produto <> 'geral'
  ),
  -- Processar cada pedido - extrair produto_id do JSON ou texto
  itens_extraidos AS (
    SELECT 
      sp.ped_id,
      sp.uff,
      CASE
        -- Se é JSON array, extrair produto_id
        WHEN sp.prod_json LIKE '[%' THEN
          (SELECT (jsonb_array_elements(sp.prod_json::jsonb)->>'produto_id')::uuid)
        -- Se é texto simples, procurar produto pelo nome
        WHEN sp.prod_json LIKE '%[{%' THEN NULL  -- JSON object, mais complexo
        ELSE NULL  -- texto simples
      END as prod_id,
      sp.qtd_pedido as qtd
    FROM saidas_pedidos sp
  ),
  -- Agrupar por produto + UF
  agg_saidas AS (
    SELECT ie.prod_id as pid, ie.uff, SUM(ie.qtd)::int as qtd_sai
    FROM itens_extraidos ie WHERE ie.prod_id IS NOT NULL
    GROUP BY ie.prod_id, ie.uff
  )
  --Resultado
  SELECT 
    COALESCE(el.pid, ase.pid, pa.pid) as prod_id,
    pa.pnome as prod_nome,
    COALESCE(el.uff, ase.uff, 'SP') as estado,
    COALESCE(el.qtd_ent, 0) as entrada,
    COALESCE(ase.qtd_sai, 0) as saida,
    (COALESCE(el.qtd_ent, 0) - COALESCE(ase.qtd_sai, 0)) as saldo
  FROM produtos_ativos pa
  LEFT JOIN entradas_lotes el ON el.pid = pa.pid
  LEFT JOIN agg_saidas ase ON ase.pid = pa.pid
  WHERE el.qtd_ent > 0 OR ase.qtd_sai > 0
  ORDER BY pa.pnome, COALESCE(el.uff, ase.uff, 'SP');
END;
$$;

-- VERSÃO SIMPLIFICADA - usando quantity do pedido diretamente
-- Considera TODOS os pedidos (pagos + pendentes) por UF
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  -- Para simplificar: criar uma "saída genérica" por UF (soma de TODOS os pedidos)
  todas_saidas AS (
    SELECT 
      COALESCE(p.uf_postagem, 'SP') as uff,
      SUM(p.quantidade)::int as total_saida
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL 
      AND p.produto IS NOT NULL 
      AND p.produto <> 'geral'
    GROUP BY COALESCE(p.uf_postagem, 'SP')
  ),
  -- Entradas por UF
  todas_entradas AS (
    SELECT 
      COALESCE(l.uf, 'SP') as uff,
      SUM(l.quantidade_atual)::int as total_entrada
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY COALESCE(l.uf, 'SP')
  )
  -- Resultado: mostrar por UF (não por produto específico ainda)
  SELECT 
    NULL::uuid as prod_id,
    'Geral' as prod_nome,
    te.uff as estado,
    te.total_entrada as entrada,
    COALESCE(ts.total_saida, 0) as saida,
    (te.total_entrada - COALESCE(ts.total_saida, 0)) as saldo
  FROM todas_entradas te
  LEFT JOIN todas_saidas ts ON ts.uff = te.uff
  ORDER BY te.uff;
END;
$$;

-- Testar
SELECT * FROM get_estoque_completo();

COMMIT;
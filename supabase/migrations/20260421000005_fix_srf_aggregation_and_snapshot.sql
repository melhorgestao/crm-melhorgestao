-- FIX: ERROR 0A000 - get_estoque_completo AND Snapshot logic
-- Esta migração corrige o erro de agregação com funções de conjunto (jsonb_array_elements)
-- e garante que o snapshot use a tabela correta sem duplicidades.

BEGIN;

-- 1. Corrige get_estoque_completo() usando LATERAL JOIN para expandir o JSON com segurança
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas_diretas AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, p.uf_cliente, 'SP') as uff, SUM(p.quantidade)::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL 
      AND p.status_pedido <> 'cancelado'
    GROUP BY p.produto_id, uff
  ),
  -- Correção aqui: expandir primeiro com LATERAL, depois agrupar e somar
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      COALESCE(p.uf_postagem, p.uf_cliente, 'SP') as uff,
      (elem->>'quantidade')::int as qtd
    FROM public.pedidos p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN p.produto LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE p.status_pagamento IS NOT NULL 
      AND p.produto LIKE '[%'
      AND p.status_pedido <> 'cancelado'
  ),
  saidas_json_grouped AS (
    SELECT pid, uff, SUM(qtd)::int as qtd FROM saidas_json_expanded GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json_grouped
    ) s2
    GROUP BY pid, uff
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    COALESCE(e.uff, s.uff, 'SP') as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM produtos_ativos pr
  LEFT JOIN entradas e ON e.pid = pr.pid
  LEFT JOIN saidas_consolidadas s ON s.pid = pr.pid
  WHERE COALESCE(e.qtd_ent, 0) > 0 OR COALESCE(s.qtd_sai, 0) > 0
  ORDER BY pr.pnome, estado;
END;
$$;

-- 2. Garante que atualizar_estoque_snapshot() aponte para a tabela correta (estoque_snapshot)
-- Nota: se a tabela já existia, o 'INSERT' apenas povoará ela.
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Limpa o snapshot atual
    DELETE FROM public.estoque_snapshot;

    -- Insere os dados atualizados selecionando explicitamente os nomes das colunas para evitar erros de ordem
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now()
    FROM public.get_estoque_completo();
END;
$$;

-- Executa a sincronização para validar
SELECT public.atualizar_estoque_snapshot();

COMMIT;

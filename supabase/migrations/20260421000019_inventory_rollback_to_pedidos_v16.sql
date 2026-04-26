-- INVENTORY ROLLBACK V16 - RESTAURAÇÃO DA FONTE DA VERDADE (PEDIDOS)
-- Reverte a loucura da V15: Cards voltam a ler de Pedidos.
-- Fix definitivo para as 7 unidades de CBD capturadas no JSON e Texto.

BEGIN;

-- 1. RESTAURAÇÃO DOS CARDS (Lendo de Pedidos, ignorando a tabela de movimentações)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome, tag as ptag FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      LEFT(UPPER(TRIM(COALESCE(l.uf, 'SP'))), 2) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    -- Fonte da Verdade: Tabela Pedidos ativa ou com status nulo
    SELECT 
      p.id as pedido_id, p.produto_id, p.quantidade, p.produto, p.observacao,
      LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
    FROM public.pedidos p
    WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido') OR p.status_pedido IS NULL)
  ),
  saidas_json AS (
    -- Extrai quantidades corretas do JSON (Ex: Ricardo 2, Vanderleia 2)
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN COALESCE(p.produto, '') LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%' 
    GROUP BY pid, p.uff
  ),
  saidas_diretas AS (
    -- Fallback para pedidos manuais/texto (Ex: Maria 1, Douglas 1)
    SELECT 
        sub.pid, sub.uff, SUM(sub.qtd)::int as qtd
    FROM (
        SELECT 
          COALESCE(
            p.produto_id, 
            (SELECT pr.id FROM produtos pr 
             WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%'))
                OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
                LIMIT 1)
          ) as pid,
          COALESCE(p.quantidade, 0) as qtd,
          p.uff
        FROM pedidos_base p
        WHERE COALESCE(p.produto, '') NOT LIKE '[%' 
    ) sub
    WHERE sub.pid IS NOT NULL
    GROUP BY sub.pid, sub.uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0)::int as entrada,
    COALESCE(s.qtd_sai, 0)::int as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0))::int as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- 2. LIMPEZA E SINCRONIZAÇÃO DA LISTA (A lista agora obedece rigorosamente aos pedidos)
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Limpa TUDO que for venda ou sincronizado anteriormente para tirar os "fantasmas"
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%' OR observacao ILIKE 'V1%');

    -- Insere do JSON
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2), p.id, 'V16 (JSON)', p.created_at
    FROM public.pedidos p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%'
      AND (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado') OR p.status_pedido IS NULL);

    -- Insere do Direto
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT sub.pid, sub.qtd, 'saida', 'Venda', sub.uff, sub.pedido_id, 'V16 (Direto)', sub.created_at
    FROM (
        SELECT 
          COALESCE(p.produto_id, (SELECT pr.id FROM produtos pr WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%')) OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%') LIMIT 1)) as pid,
          p.quantidade as qtd, LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff, p.id as pedido_id, p.created_at
        FROM public.pedidos p
        WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado') OR p.status_pedido IS NULL)
          AND COALESCE(p.produto, '') NOT LIKE '[%'
    ) sub
    WHERE sub.pid IS NOT NULL;

    RETURN jsonb_build_object('status', 'ok', 'note', 'Rollback V16 completo');
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;

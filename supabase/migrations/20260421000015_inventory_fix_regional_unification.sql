-- INVENTORY FIX V12 - UNIFICAÇÃO REGIONAL E PARIDADE TOTAL (O 7º CBD)
-- Unifica SC1, RS1, SP1 nas UFs base SC, RS, SP e blinda o status contra nulos.

BEGIN;

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
    -- Normaliza a UF para 2 dígitos (SC1 -> SC)
    SELECT 
      l.produto_id as pid, 
      LEFT(UPPER(TRIM(COALESCE(l.uf, 'SP'))), 2) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    -- Blinda status contra NULL e normalization da UF
    SELECT 
      p.id as pedido_id,
      p.produto_id,
      p.quantidade,
      p.produto,
      p.observacao,
      LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
    FROM public.pedidos p
    WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido')) OR p.status_pedido IS NULL
  ),
  saidas_itens_tabela AS (
    SELECT pi.produto_id as pid, pb.uff, SUM(pi.quantidade)::int as qtd, pi.pedido_id
    FROM public.pedido_itens pi
    JOIN pedidos_base pb ON pb.pedido_id = pi.pedido_id
    GROUP BY pi.produto_id, pb.uff, pi.pedido_id
  ),
  saidas_json AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN COALESCE(p.produto, '') LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_diretas AS (
    -- FIX V12: Omni-Match + UF Unification
    SELECT 
      COALESCE(
        p.produto_id, 
        (SELECT pr.id FROM produtos pr 
         WHERE (COALESCE(p.produto, '') <> '' AND (
                p.produto = pr.nome_oficial 
                OR p.produto ILIKE '%' || pr.tag || '%' 
                OR p.produto ILIKE '%' || pr.nome_oficial || '%'
                OR pr.nome_oficial ILIKE '%' || p.produto || '%'
               ))
            OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
            LIMIT 1
        )
      ) as pid,
      p.uff,
      SUM(COALESCE(p.quantidade, 0))::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    WHERE COALESCE(p.produto, '') NOT LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_itens_tabela
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    WHERE pid IS NOT NULL
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
    COALESCE(SUM(e.qtd_ent), 0)::int as entrada,
    COALESCE(SUM(s.qtd_sai), 0)::int as saida,
    (COALESCE(SUM(e.qtd_ent), 0) - COALESCE(SUM(s.qtd_sai), 0))::int as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  GROUP BY pr.pid, pr.pnome, tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V12: Unificação de UF nas Movimentações Históricas
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%');
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN SELECT id, uff FROM (
        SELECT p.id, LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
        FROM public.pedidos p
        WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado')) OR p.status_pedido IS NULL
    ) p2 LOOP
        
        IF EXISTS (SELECT 1 FROM public.pedido_itens WHERE pedido_id = v_pedido.id) THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT produto_id, quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V12 (Itens)', (SELECT created_at FROM pedidos WHERE id = v_pedido.id)
            FROM public.pedido_itens WHERE pedido_id = v_pedido.id;
        ELSIF EXISTS (SELECT 1 FROM public.pedidos WHERE id = v_pedido.id AND COALESCE(produto, '') LIKE '[%') THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V12 (JSON)', p.created_at
            FROM public.pedidos p
            CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
            WHERE p.id = v_pedido.id;
        ELSE
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                COALESCE(
                    p.produto_id, 
                    (SELECT pr.id FROM produtos pr 
                     WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%'))
                        OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
                        LIMIT 1)
                ),
                COALESCE(p.quantidade, 0), 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V12 (Omni-Match)', p.created_at
            FROM public.pedidos p
            WHERE p.id = v_pedido.id;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'note', 'UFs normalizadas para 2 digitos (V12)');
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;

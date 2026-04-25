-- INVENTORY FIX V8 - BUSCA FLEXÍVEL POR NOME E TAG
-- Garante que o CBD seja capturado mesmo que o nome no pedido seja curto (Ex: 'CBD' vs 'Óleo CBD').

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
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_normalizados AS (
    -- FIX: Busca flexível por ID, Nome Oficial ou TAG
    SELECT 
      p.id as pedido_id,
      COALESCE(
        p.produto_id, 
        (SELECT pr.id FROM produtos pr 
         WHERE p.produto = pr.nome_oficial 
            OR UPPER(TRIM(p.produto)) = UPPER(TRIM(pr.tag))
            OR pr.nome_oficial ILIKE '%' || p.produto || '%'
         LIMIT 1)
      ) as pid,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff,
      (p.produto LIKE '[%') as is_json
    FROM public.pedidos p
    WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
  ),
  saidas_diretas AS (
    SELECT p.pid, p.uff, SUM(p.quantidade)::int as qtd
    FROM pedidos_normalizados p
    WHERE NOT p.is_json AND p.pid IS NOT NULL 
    GROUP BY p.pid, p.uff
  ),
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      (elem->>'quantidade')::int as qtd
    FROM pedidos_normalizados p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE p.is_json
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
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V8: Mesma lógica de busca flexível
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item jsonb;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN 
        SELECT 
          p.id, 
          COALESCE(
            p.produto_id, 
            (SELECT pr.id FROM produtos pr 
             WHERE p.produto = pr.nome_oficial 
                OR UPPER(TRIM(p.produto)) = UPPER(TRIM(pr.tag))
                OR pr.nome_oficial ILIKE '%' || p.produto || '%'
             LIMIT 1)
          ) as final_pid, 
          p.produto, 
          p.quantidade, 
          UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uf, 
          p.created_at
        FROM public.pedidos p
        WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
    LOOP
        IF v_pedido.final_pid IS NOT NULL AND v_pedido.produto NOT LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.final_pid, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V8 (Flexível)', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V8 (JSON)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;

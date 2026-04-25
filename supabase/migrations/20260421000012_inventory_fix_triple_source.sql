-- INVENTORY FIX V9 - FONTE DE VERDADE TRIPLA (PARIDADE SEBASTIÃO)
-- Inclui a tabela pedido_itens como fonte primária para resolver discrepâncias.

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
    SELECT id as pid, nome_oficial as pnome FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    -- Normalização inicial dos pedidos ativos
    SELECT 
      p.id as pedido_id,
      p.produto_id,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff
    FROM public.pedidos p
    WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
  ),
  saidas_itens_tabela AS (
    -- Fator Sebastião: Buscar primeiro na tabela de itens detalhada
    SELECT pi.produto_id as pid, pb.uff, SUM(pi.quantidade)::int as qtd, pi.pedido_id
    FROM public.pedido_itens pi
    JOIN pedidos_base pb ON pb.pedido_id = pi.pedido_id
    GROUP BY pi.produto_id, pb.uff, pi.pedido_id
  ),
  saidas_json AS (
    -- Fallback 1: JSON (apenas se o pedido não estiver na tabela de itens)
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN p.produto LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE p.produto LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_diretas AS (
    -- Fallback 2: Coluna Unitária ou Nome (apenas se não houver registros nas fontes anteriores)
    SELECT 
      COALESCE(p.produto_id, (SELECT pr.id FROM produtos pr WHERE p.produto = pr.nome_oficial OR pr.nome_oficial ILIKE '%' || p.produto || '%' LIMIT 1)) as pid,
      p.uff,
      SUM(p.quantidade)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    WHERE p.produto NOT LIKE '[%' 
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

-- Sincronização V9: Também unificada
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item record;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    -- Usa a mesma lógica de prioridade tripla
    FOR v_pedido IN SELECT id, uff FROM (
        SELECT p.id, UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff
        FROM public.pedidos p
        WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
    ) p2 LOOP
        
        -- 1. Tenta pedido_itens
        IF EXISTS (SELECT 1 FROM public.pedido_itens WHERE pedido_id = v_pedido.id) THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
            SELECT produto_id, quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V9 (Itens)'
            FROM public.pedido_itens WHERE pedido_id = v_pedido.id;
            v_count_ins := v_count_ins + 1;
            
        -- 2. Tenta JSON
        ELSE
            -- Lógica simplificada para o loop de sincronização (reutiliza a lógica da get_estoque_completo)
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
            SELECT 
                (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V9 (JSON)'
            FROM public.pedidos p
            CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
            WHERE p.id = v_pedido.id AND p.produto LIKE '[%';
            
            IF FOUND THEN 
                v_count_ins := v_count_ins + 1;
            ELSE
                -- 3. Tenta Direto
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
                SELECT 
                    COALESCE(p.produto_id, (SELECT pr.id FROM produtos pr WHERE p.produto = pr.nome_oficial OR pr.nome_oficial ILIKE '%' || p.produto || '%' LIMIT 1)),
                    p.quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V9 (Direto)'
                FROM public.pedidos p
                WHERE p.id = v_pedido.id AND p.produto_id IS NOT NULL OR p.produto NOT LIKE '[%';
                
                v_count_ins := v_count_ins + 1;
            END IF;
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

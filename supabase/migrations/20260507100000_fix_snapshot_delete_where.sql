-- Fix: "DELETE requires a WHERE clause" ao criar pedido
-- A funcao atualizar_estoque_snapshot (redefinida em 20260421000023) tinha
-- DELETE FROM public.estoque_snapshot sem WHERE, e o Postgres / PostgREST
-- bloqueia DELETE sem WHERE. Trigger trg_snapshot_on_pedido_change dispara
-- essa funcao em INSERT/UPDATE/DELETE em pedidos.

CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM public.estoque_snapshot WHERE true;

    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    WITH
    entradas_lotes AS (
        SELECT
            produto_id,
            uf as estado,
            SUM(quantidade_inicial)::int as total_entrada
        FROM public.lotes
        GROUP BY produto_id, uf
    ),
    saidas_pedidos AS (
        SELECT
            p_id as produto_id,
            uff as estado,
            SUM(qty)::int as total_saida
        FROM (
            SELECT
                (elem->>'produto_id')::uuid as p_id,
                LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff,
                (elem->>'quantidade')::int as qty
            FROM public.pedidos p,
            LATERAL jsonb_array_elements(CASE WHEN p.produto ~ '^\[.*\]$' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
            WHERE p.status_pedido != 'cancelado'
              AND p.data >= '2026-04-01'
              AND p.produto ~ '^\[.*\]$'

            UNION ALL

            SELECT
                COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as p_id,
                LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff,
                p.quantidade as qty
            FROM public.pedidos p
            WHERE p.status_pedido != 'cancelado'
              AND p.data >= '2026-04-01'
              AND NOT (p.produto ~ '^\[.*\]$')
              AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
        ) sub
        WHERE p_id IS NOT NULL
        GROUP BY p_id, uff
    )
    SELECT
        COALESCE(e.produto_id, s.produto_id),
        (SELECT nome_oficial FROM public.produtos WHERE id = COALESCE(e.produto_id, s.produto_id)),
        COALESCE(e.estado, s.estado),
        COALESCE(e.total_entrada, 0),
        COALESCE(s.total_saida, 0),
        (COALESCE(e.total_entrada, 0) - COALESCE(s.total_saida, 0)),
        NOW()
    FROM entradas_lotes e
    FULL JOIN saidas_pedidos s ON e.produto_id = s.produto_id AND e.estado = s.estado;
END;
$$;

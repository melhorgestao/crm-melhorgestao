-- INVENTORY V19 - OMNI SOURCE OF TRUTH
-- Refatora o estoque para que a Dashboard seja alimentada 100% por Pedidos e Lotes reais.

BEGIN;

-- 1. FUNÇÃO PARA RECALCULAR O SNAPSHOT (FONTE: PEDIDOS + LOTES)
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM public.estoque_snapshot;
    
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    WITH 
    entradas_lotes AS (
        -- Soma de lotes registrados (Entrada Inicial)
        SELECT 
            produto_id, 
            uf as estado, 
            SUM(quantidade_inicial)::int as total_entrada
        FROM public.lotes
        GROUP BY produto_id, uf
    ),
    saidas_pedidos AS (
        -- Soma de pedidos ativos (Saída por Venda)
        -- Parsing robusto de JSON e Texto
        SELECT 
            p_id as produto_id,
            uff as estado,
            SUM(qty)::int as total_saida
        FROM (
            -- Caso A: JSON
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

            -- Caso B: Texto/Direto
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

-- 2. LIMPEZA E SINCRONIZAÇÃO DA LISTA DE MOVIMENTAÇÕES (AUDITORIA)
-- Removemos lançamentos fantasmas (Troca UF) e saídas orfãs
DELETE FROM public.estoque_movimentacoes 
WHERE (tipo = 'saida') 
   OR (tipo = 'entrada' AND observacao LIKE '%Troca UF%') 
   OR (tipo = 'entrada' AND observacao LIKE '%Devolução%');

-- Re-insere as saídas baseadas no estado atual dos pedidos
INSERT INTO public.estoque_movimentacoes (pedido_id, produto_id, quantidade, tipo, uf_origem, data, observacao)
SELECT 
    p_id_full.pedido_id,
    p_id_full.p_id,
    p_id_full.qty,
    'saida',
    p_id_full.uff,
    p_id_full.data_ped,
    'Sincronização V19'
FROM (
    SELECT 
        p.id as pedido_id,
        (elem->>'produto_id')::uuid as p_id,
        LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff,
        (elem->>'quantidade')::int as qty,
        p.data as data_ped
    FROM public.pedidos p,
    LATERAL jsonb_array_elements(CASE WHEN p.produto ~ '^\[.*\]$' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE p.status_pedido != 'cancelado' AND p.data >= '2026-04-01' AND p.produto ~ '^\[.*\]$'
    UNION ALL
    SELECT 
        p.id as pedido_id,
        COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as p_id,
        LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff,
        p.quantidade as qty,
        p.data as data_ped
    FROM public.pedidos p
    WHERE p.status_pedido != 'cancelado' AND p.data >= '2026-04-01' AND NOT (p.produto ~ '^\[.*\]$')
      AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
) p_id_full
WHERE p_id_full.p_id IS NOT NULL;

-- 3. GARANTIR QUE OS CARDS SEJAM ATUALIZADOS EM TEMPO REAL
DROP TRIGGER IF EXISTS trg_snapshot_on_pedido_change ON public.pedidos;
CREATE OR REPLACE FUNCTION public.fn_trigger_update_snapshot() 
RETURNS trigger AS $$ BEGIN PERFORM public.atualizar_estoque_snapshot(); RETURN NULL; END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_snapshot_on_pedido_change 
AFTER INSERT OR UPDATE OR DELETE ON public.pedidos
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trigger_update_snapshot();

DROP TRIGGER IF EXISTS trg_snapshot_on_lote_change ON public.lotes;
CREATE TRIGGER trg_snapshot_on_lote_change 
AFTER INSERT OR UPDATE OR DELETE ON public.lotes
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trigger_update_snapshot();

-- Executa uma vez
SELECT public.atualizar_estoque_snapshot();

COMMIT;

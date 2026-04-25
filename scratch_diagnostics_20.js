const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

const sql = `
-- INVENTORY V19 - OMNI SOURCE OF TRUTH
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM public.estoque_snapshot;
    
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    WITH 
    entradas_lotes AS (
        SELECT produto_id, uf as estado, SUM(quantidade_inicial)::int as total_entrada
        FROM public.lotes
        GROUP BY produto_id, uf
    ),
    saidas_pedidos AS (
        SELECT p_id as produto_id, uff as estado, SUM(qty)::int as total_saida
        FROM (
            SELECT (elem->>'produto_id')::uuid as p_id, LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff, (elem->>'quantidade')::int as qty
            FROM public.pedidos p, LATERAL jsonb_array_elements(CASE WHEN p.produto ~ '^\\[.*\\]$' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
            WHERE p.status_pedido != 'cancelado' AND p.data >= '2026-04-01' AND p.produto ~ '^\\[.*\\]$'
            UNION ALL
            SELECT COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as p_id, LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff, p.quantidade as qty
            FROM public.pedidos p
            WHERE p.status_pedido != 'cancelado' AND p.data >= '2026-04-01' AND NOT (p.produto ~ '^\\[.*\\]$')
              AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
        ) sub
        WHERE p_id IS NOT NULL
        GROUP BY p_id, uff
    )
    SELECT COALESCE(e.produto_id, s.produto_id), (SELECT nome_oficial FROM public.produtos WHERE id = COALESCE(e.produto_id, s.produto_id)), COALESCE(e.estado, s.estado), COALESCE(e.total_entrada, 0), COALESCE(s.total_saida, 0), (COALESCE(e.total_entrada, 0) - COALESCE(s.total_saida, 0)), NOW()
    FROM entradas_lotes e FULL JOIN saidas_pedidos s ON e.produto_id = s.produto_id AND e.estado = s.estado;
END;
$$;

DELETE FROM public.estoque_movimentacoes WHERE (tipo = 'saida') OR (tipo = 'entrada' AND observacao LIKE '%Troca UF%') OR (tipo = 'entrada' AND observacao LIKE '%Devolução%');

INSERT INTO public.estoque_movimentacoes (pedido_id, produto_id, quantidade, tipo, uf_origem, data, observacao)
SELECT p_id_full.pedido_id, p_id_full.p_id, p_id_full.qty, 'saida', p_id_full.uff, p_id_full.data_ped, 'Sincronização V19'
FROM (
    SELECT p.id as pedido_id, (elem->>'produto_id')::uuid as p_id, LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff, (elem->>'quantidade')::int as qty, p.data as data_ped FROM public.pedidos p, LATERAL jsonb_array_elements(CASE WHEN p.produto ~ '^\\[.*\\]$' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem WHERE p.status_pedido != 'cancelado' AND p.data >= '2026-04-01' AND p.produto ~ '^\\[.*\\]$'
    UNION ALL
    SELECT p.id as pedido_id, COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as p_id, LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff, p.quantidade as qty, p.data as data_ped FROM public.pedidos p WHERE p.status_pedido != 'cancelado' AND p.data >= '2026-04-01' AND NOT (p.produto ~ '^\\[.*\\]$') AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
) p_id_full WHERE p_id_full.p_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_snapshot_on_pedido_change ON public.pedidos;
CREATE OR REPLACE FUNCTION public.fn_trigger_update_snapshot() RETURNS trigger AS $$ BEGIN PERFORM public.atualizar_estoque_snapshot(); RETURN NULL; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_snapshot_on_pedido_change AFTER INSERT OR UPDATE OR DELETE ON public.pedidos FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trigger_update_snapshot();

DROP TRIGGER IF EXISTS trg_snapshot_on_lote_change ON public.lotes;
CREATE TRIGGER trg_snapshot_on_lote_change AFTER INSERT OR UPDATE OR DELETE ON public.lotes FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trigger_update_snapshot();

SELECT public.atualizar_estoque_snapshot();
`;

async function run() {
    // Note: This relies on a potential 'run_sql' RPC or similar. If not available, we'll have to ask the user to run it.
    // However, I'll try to use the REST API to call the functions after they are updated if possible.
    // Since I can't easily run arbitrary SQL via REST without an RPC, I will ask the user to run the migration in the Supabase Dashboard.
    console.log("MIGRATION SQL READY. PLEASE RUN IN SUPABASE SQL EDITOR.");
    console.log(sql);
}
run();

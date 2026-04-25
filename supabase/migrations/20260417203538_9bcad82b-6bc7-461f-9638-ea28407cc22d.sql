-- Fix: DELETE requires a WHERE clause (PostgREST safety)
-- Substitui DELETE puro por DELETE ... WHERE true em ambas as funcoes de snapshot

CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    DELETE FROM public.estoque_snapshot WHERE true;
    
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    WITH entradas AS (
        SELECT produto_id, uf as estado, SUM(quantidade_inicial)::int as entrada
        FROM public.lotes WHERE produto_id IS NOT NULL GROUP BY produto_id, uf
    ),
    saidas AS (
        SELECT produto_id, estado, SUM(quantidade)::int as saida FROM (
            SELECT 
                (elem->>'produto_id')::uuid as produto_id,
                LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as estado,
                (elem->>'quantidade')::int as quantidade
            FROM public.pedidos p,
            LATERAL jsonb_array_elements(
                CASE 
                    WHEN p.produto IS NOT NULL AND p.produto LIKE '[%' THEN p.produto::jsonb 
                    ELSE '[]'::jsonb 
                END
            ) AS elem
            WHERE p.status_pedido != 'cancelado' 
              AND p.data >= '2026-04-01'
              AND p.produto LIKE '[%'
              AND (p.observacao IS NULL OR (p.observacao NOT ILIKE '%Troca de UF%' AND p.observacao NOT ILIKE '%Devolução%'))
            
            UNION ALL
            
            SELECT 
                COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as produto_id,
                LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as estado,
                p.quantidade as quantidade
            FROM public.pedidos p
            WHERE p.status_pedido != 'cancelado'
              AND p.data >= '2026-04-01'
              AND (p.produto NOT LIKE '[%' OR p.produto IS NULL)
              AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
              AND (p.observacao IS NULL OR (p.observacao NOT ILIKE '%Troca de UF%' AND p.observacao NOT ILIKE '%Devolução%'))
        ) todas_saidas
        WHERE produto_id IS NOT NULL
        GROUP BY produto_id, estado
    )
    SELECT 
        COALESCE(e.produto_id, s.produto_id),
        (SELECT nome_oficial FROM public.produtos WHERE id = COALESCE(e.produto_id, s.produto_id)),
        COALESCE(e.estado, s.estado),
        COALESCE(e.entrada, 0),
        COALESCE(s.saida, 0),
        (COALESCE(e.entrada, 0) - COALESCE(s.saida, 0)),
        NOW()
    FROM entradas e
    FULL JOIN saidas s ON e.produto_id = s.produto_id AND e.estado = s.estado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.criar_estoque_snapshot()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_rec record;
BEGIN
  DELETE FROM public.estoque_snapshots WHERE true;
  FOR v_rec IN SELECT prod_id, estado, saldo FROM public.get_estoque_completo() LOOP
    INSERT INTO public.estoque_snapshots (produto_id, uf, saldo)
    VALUES (v_rec.prod_id::uuid, v_rec.estado, v_rec.saldo)
    ON CONFLICT (produto_id, uf) DO UPDATE SET saldo = v_rec.saldo, data_snapshot = now();
  END LOOP;
END;
$function$;
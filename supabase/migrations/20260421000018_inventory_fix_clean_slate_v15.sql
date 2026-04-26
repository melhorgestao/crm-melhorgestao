-- INVENTORY FIX V15 - CLEAN SLATE (O FIM DOS FANTASMAS)
-- Esta versão limpa o histórico de vendas e unifica os cards com a tabela de movimentações.
-- Garantia: Se está na lista (Tabela), está no total (Card).

BEGIN;

-- 1. LIMPEZA TOTAL DE SAÍDAS DE VENDA (Fantasmas/Duplicatas)
DELETE FROM public.estoque_movimentacoes 
WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%' OR observacao ILIKE '%Sincronizado%');

-- 2. RECONSTRUÇÃO DA LÓGICA DE SINCRONIZAÇÃO (O Motor de Verdade)
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_mov_count int := 0;
BEGIN
    -- Limpa apenas as vendas sincronizadas para evitar acúmulo
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (observacao ILIKE 'V1%');

    -- Iteramos por todos os pedidos não cancelados
    FOR v_pedido IN 
        SELECT 
            p.id, 
            p.produto, 
            p.quantidade, 
            p.produto_id, 
            p.observacao,
            p.created_at,
            LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
        FROM public.pedidos p
        WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido') OR p.status_pedido IS NULL)
    LOOP
        -- FONTE A: JSON (Prioridade Máxima)
        IF COALESCE(v_pedido.produto, '') LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                (elem->>'produto_id')::uuid, 
                (elem->>'quantidade')::int, 
                'saida', 'Venda', v_pedido.uff, v_pedido.id, 'V15 (JSON)', v_pedido.created_at
            FROM jsonb_array_elements(v_pedido.produto::jsonb) AS elem;
            v_mov_count := v_mov_count + 1;
            
        -- FONTE B: Texto (Fallback Case-Insensitive)
        ELSE
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                COALESCE(
                  v_pedido.produto_id, 
                  (SELECT pr.id FROM produtos pr 
                   WHERE (COALESCE(v_pedido.produto, '') <> '' AND (v_pedido.produto = pr.nome_oficial OR v_pedido.produto ILIKE '%' || pr.tag || '%' OR v_pedido.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || v_pedido.produto || '%'))
                      OR (v_pedido.observacao ILIKE '%' || pr.tag || '%' OR v_pedido.observacao ILIKE '%' || pr.nome_oficial || '%')
                      LIMIT 1)
                ),
                COALESCE(v_pedido.quantidade, 0), 
                'saida', 'Venda', v_pedido.uff, v_pedido.id, 'V15 (Direto)', v_pedido.created_at;
            v_mov_count := v_mov_count + 1;
        END IF;
    END LOOP;

    -- Atualiza snapshots se a função existir
    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'movimentos_processados', v_mov_count);
END;
$$;

-- 3. UNIFICAÇÃO DOS CARDS COM A TABELA (O Card lê a Tabela)
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
    SELECT id as pid, nome_oficial as pnome FROM public.produtos
  ),
  consolidado AS (
    -- Agrupamos TUDO o que está na tabela de movimentações (Entradas e Saídas)
    SELECT 
      m.produto_id as pid,
      LEFT(UPPER(TRIM(COALESCE(m.uf_origem, 'SP'))), 2) as uff,
      SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END)::int as qtd_ent,
      SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END)::int as qtd_sai
    FROM public.estoque_movimentacoes m
    GROUP BY m.produto_id, uff
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    c.uff as estado,
    c.qtd_ent as entrada,
    c.qtd_sai as saida,
    (c.qtd_ent - c.qtd_sai) as saldo
  FROM consolidado c
  JOIN produtos_base pr ON pr.pid = c.pid
  ORDER BY pr.pnome, estado;
END;
$$;

-- 4. EXECUÇÃO DA SINCRONIA INICIAL
SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;

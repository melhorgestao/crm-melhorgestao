-- INVENTORY FIX V18 - A VERDADE INQUESTIONÁVEL (FONTE: PEDIDOS)
-- Esta migration reconstrói o saldo baseado 100% na tabela de pedidos,
-- garantindo que o Pedido #13 (SC - 2 unidades) e o Pedido #12 (Vanderleia - 2 unidades) sejam contados.

BEGIN;

-- 1. LIMPAR MOVIMENTAÇÕES DE SAÍDA ANTIGAS PARA RECONSTRUIR DO ZERO
-- (Mantemos entradas de fornecedores, mas saídas de vendas serão sincronizadas com pedidos)
DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida';

-- 2. INSERIR SAÍDAS BASEADAS NO PARSING DE JSON E TEXTO DOS PEDIDOS
-- Esta CTE faz o "unpacking" de todos os itens de todos os pedidos ativos.
WITH pedidos_unpacked AS (
    -- Caso A: Pedidos com JSON (Array de produtos)
    SELECT 
        p.id as pedido_id,
        p.data as data_pedido,
        p.uf_postagem,
        (elem->>'quantidade')::int as qty,
        (elem->>'produto_id')::uuid as p_id,
        (elem->>'produto') as p_nome
    FROM public.pedidos p,
    LATERAL jsonb_array_elements(CASE WHEN p.produto ~ '^\[.*\]$' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE p.status_pedido != 'cancelado' 
      AND p.data >= '2026-04-01'
      AND p.produto ~ '^\[.*\]$'

    UNION ALL

    -- Caso B: Pedidos com texto simples ou produto_id direto (Não JSON)
    SELECT 
        p.id as pedido_id,
        p.data as data_pedido,
        p.uf_postagem,
        p.quantidade as qty,
        COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as p_id,
        p.produto as p_nome
    FROM public.pedidos p
    WHERE p.status_pedido != 'cancelado'
      AND p.data >= '2026-04-01'
      AND NOT (p.produto ~ '^\[.*\]$')
      AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
)
INSERT INTO public.estoque_movimentacoes (pedido_id, produto_id, quantidade, tipo, uf_origem, data, observacao)
SELECT 
    pedido_id,
    p_id,
    qty,
    'saida',
    COALESCE(uf_postagem, 'SP'),
    data_pedido,
    'Sincronização Automática V18'
FROM pedidos_unpacked
WHERE p_id IS NOT NULL;

-- 3. ATUALIZAR O SNAPSHOT (Baseado na lista agora reconstruída e perfeita)
SELECT public.atualizar_estoque_snapshot();

COMMIT;

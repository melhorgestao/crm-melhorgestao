-- INVENTORY FIX - SOURCE OF TRUTH (PEDIDOS)
-- Esse script centraliza o estoque baseado na tabela pedidos e resolve duplicidades.

BEGIN;

-- 1. Garante coluna uf_cliente em pedidos (conforme guia)
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

UPDATE public.pedidos p
SET uf_cliente = c.uf
FROM public.contatos c
WHERE p.contato_id = c.id AND p.uf_cliente IS NULL AND c.uf IS NOT NULL;

UPDATE public.pedidos p
SET uf_cliente = p.uf_postagem
WHERE p.uf_cliente IS NULL AND p.uf_postagem IS NOT NULL;

-- 2. Limpa e reconstrói GET_ESTOQUE_COMPLETO com lógica Dinâmica (Source of Truth)
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    -- Entradas fixas baseadas na quantidade inicial dos lotes
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  -- Saídas do campo single produto_id
  saidas_diretas AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, p.uf_cliente, 'SP') as uff, SUM(p.quantidade)::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL 
      AND p.status_pedido <> 'cancelado'
    GROUP BY p.produto_id, uff
  ),
  -- Saídas do campo JSON (Multi-produto)
  saidas_json AS (
    SELECT 
      (jsonb_array_elements(CASE WHEN p.produto LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END)->>'produto_id')::uuid as pid,
      COALESCE(p.uf_postagem, p.uf_cliente, 'SP') as uff,
      SUM((jsonb_array_elements(p.produto::jsonb)->>'quantidade')::int)::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL 
      AND p.produto LIKE '[%'
      AND p.status_pedido <> 'cancelado'
    GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json
    ) s2
    GROUP BY pid, uff
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    COALESCE(e.uff, s.uff, 'SP') as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM produtos_ativos pr
  LEFT JOIN entradas e ON e.pid = pr.pid
  LEFT JOIN saidas_consolidadas s ON s.pid = pr.pid
  WHERE COALESCE(e.qtd_ent, 0) > 0 OR COALESCE(s.qtd_sai, 0) > 0
  ORDER BY pr.pnome, estado;
END;
$$;

-- 3. Função de sincronização de movimentações (limpeza e reconstrução)
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
    -- Remove saídas de venda vinculadas a pedidos para evitar duplicatas
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    -- Reinsere a partir da verdade (pedidos)
    FOR v_pedido IN 
        SELECT id, produto_id, produto, quantidade, COALESCE(uf_postagem, uf_cliente, 'SP') as uf, created_at, status_pedido
        FROM public.pedidos 
        WHERE status_pagamento IS NOT NULL AND status_pedido <> 'cancelado'
    LOOP
        -- Caso single
        IF v_pedido.produto_id IS NOT NULL THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.produto_id, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado via Pedidos', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        -- Caso JSON
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado via Pedidos (JSON)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

-- 4. Corrige CRIAR_PEDIDO_V2 para NÃO descontar lote (Sincronia Automática via get_estoque_completo)
-- O log de movimentação continua para manter o histórico individual
CREATE OR REPLACE FUNCTION public.criar_pedido_v2(
  p_contato_id uuid,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido_id uuid;
  v_order_number integer;
  v_data_sp date;
  v_uf_cliente text;
  v_quantidade_total integer;
  v_produto_text text;
  v_item jsonb;
BEGIN
  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  -- UF do cliente
  BEGIN
    SELECT uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  -- Quantidade total e Texto do produto
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT SUM((item->>'quantidade')::integer) INTO v_quantidade_total FROM jsonb_array_elements(p_produtos) AS item;
    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := (p_produtos->0->>'produto');
    ELSE
      v_produto_text := p_produtos::text;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := 'geral';
  END IF;

  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem, uf_cliente,
    status_pedido, observacao, criado_por, order_number, data, estoque_processado,
    produto, quantidade, created_at
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, p_modalidade, p_uf_postagem, v_uf_cliente,
    'aguardando_rastreio', COALESCE(p_obs, ''), p_criado_por, v_order_number, v_data_sp, true,
    v_produto_text, v_quantidade_total, now()
  )
  RETURNING id INTO v_pedido_id;

  -- Insere itens e Movimentação (Histórico apenas, sem descontar lotes manual para evitar duplicidade)
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_item IN SELECT jsonb_array_elements(p_produtos) LOOP
        -- Movimentação
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
        VALUES ((v_item->>'produto_id')::uuid, (v_item->>'quantidade')::int, 'saida', 'Venda', COALESCE(p_uf_postagem, v_uf_cliente, 'SP'), v_pedido_id, 'Pedido automático RPC');
        
        -- Item
        INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco)
        VALUES (v_pedido_id, (v_item->>'produto_id')::uuid, (v_item->>'quantidade')::int, 0);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

-- 5. Remove o Trigger para evitar tripla contagem (RPC já insere no estoque_movimentacoes)
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque();

-- 6. Executa a sincronização inicial
SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;

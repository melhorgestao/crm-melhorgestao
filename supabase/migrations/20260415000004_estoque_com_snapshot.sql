-- ESTOQUE COM SNAPSHOT - Calculo dinamico via pedidos
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Garantir coluna estoque_processado nos pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean DEFAULT false;

-- 2. Criar tabela de snapshot do estoque (cache)
CREATE TABLE IF NOT EXISTS public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id uuid REFERENCES public.produtos(id),
  uf text,
  entradas integer DEFAULT 0,
  saidas_pedidos integer DEFAULT 0,
  saidas_movimentacoes integer DEFAULT 0,
  saldo_calculado integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 3. Criar funcao para calcular estoque dinamico (inclui pedidos pendentes)
CREATE OR REPLACE FUNCTION public.get_estoque_produto(p_produto_id uuid DEFAULT NULL, p_uf text DEFAULT NULL)
RETURNS TABLE(produto_id uuid, produto_nome text, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH entradas_lotes AS (
    SELECT produto_id, uf, SUM(quantidade_atual) as total
    FROM public.lotes
    WHERE p_produto_id IS NULL OR produto_id = p_produto_id
    AND (p_uf IS NULL OR uf = p_uf)
    GROUP BY produto_id, uf
  ),
  saidas_pedidos_pendentes AS (
    SELECT pi.produto_id, p.uf_postagem as uf, SUM(pi.quantidade) as total
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.estoque_processado IS NULL OR p.estoque_processado = false
    AND p.status_pagamento = 'pago'
    AND (p_produto_id IS NULL OR pi.produto_id = p_produto_id)
    GROUP BY pi.produto_id, p.uf_postagem
  ),
  saidas_movimentacoes AS (
    SELECT produto_id, uf_origem as uf, SUM(quantidade) as total
    FROM public.estoque_movimentacoes
    WHERE tipo = 'saida'
    AND (p_produto_id IS NULL OR produto_id = p_produto_id)
    AND (p_uf IS NULL OR uf_origem = p_uf)
    GROUP BY produto_id, uf_origem
  )
  SELECT 
    COALESCE(el.produto_id, sp.produto_id, sm.produto_id) as produto_id,
    COALESCE(pr.nome_oficial, 'Produto não encontrado') as produto_nome,
    COALESCE(el.uf, sp.uf, sm.uf) as uf,
    COALESCE(el.total, 0)::integer as entradas,
    COALESCE(sp.total, 0)::integer as saidas_pedidos,
    (COALESCE(el.total, 0) - COALESCE(sp.total, 0))::integer as saldo
  FROM entradas_lotes el
  FULL OUTER JOIN saidas_pedidos_pendentes sp ON sp.produto_id = el.produto_id AND sp.uf = el.uf
  FULL OUTER JOIN saidas_movimentacoes sm ON sm.produto_id = COALESCE(el.produto_id, sp.produto_id) AND sm.uf = COALESCE(el.uf, sp.uf)
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(el.produto_id, sp.produto_id, sm.produto_id)
  WHERE (el.total IS NOT NULL OR sp.total IS NOT NULL)
  ORDER BY pr.nome_oficial, COALESCE(el.uf, sp.uf, sm.uf);
END;
$$;

-- 4. Criar funcao para atualizar snapshot (executar quando necessario)
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Limpar snapshot antigo
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  
  -- Inserir novo calculo
  INSERT INTO public.estoque_snapshot (produto_id, uf, entradas, saidas_pedidos, saidas_movimentacoes, saldo_calculado, atualizado_em)
  SELECT 
    produto_id,
    uf,
    entradas,
    saidas_pedidos,
    0,
    (entradas - saidas_pedidos),
    now()
  FROM public.get_estoque_produto(NULL, NULL);
  
  -- Atualizar estoque_atual na tabela produtos (soma total por produto)
  UPDATE public.produtos p
  SET estoque_atual = COALESCE((
    SELECT SUM(saldo_calculado) 
    FROM public.estoque_snapshot 
    WHERE produto_id = p.id
  ), 0);
END;
$$;

-- 5. Criar funcao para abater estoque de pedido (para uso manual)
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(p_pedido_id uuid, p_uf_postagem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_total_items integer := 0;
  v_processed_items integer := 0;
BEGIN
  v_uf_cliente := p_uf_postagem;
  
  IF v_uf_cliente IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct, pedidos p WHERE p.id = p_pedido_id AND ct.id = p.contato_id;
  END IF;

  FOR v_item IN SELECT * FROM pedido_itens WHERE pedido_id = p_pedido_id LOOP
    v_total_items := v_total_items + 1;
    SELECT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id) INTO v_mov_exists;
    IF v_mov_exists THEN CONTINUE; END IF;

    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, created_at ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, pedido_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, p_pedido_id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;
    v_processed_items := v_processed_items + 1;
  END LOOP;

  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;
  
  -- Atualizar snapshot apos abate
  PERFORM public.atualizar_estoque_snapshot();
  
  RETURN jsonb_build_object('pedido_id', p_pedido_id::text, 'total_items', v_total_items, 'processed', v_processed_items);
END;
$$;

-- 6. Criar funcao para processar TODOS pedidos pendentes de uma vez
CREATE OR REPLACE FUNCTION public.processar_todos_estoque_pendente()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido record;
  v_total_processados integer := 0;
  v_result jsonb;
BEGIN
  FOR v_pedido IN
    SELECT id, uf_postagem FROM public.pedidos
    WHERE (estoque_processado IS NULL OR estoque_processado = false)
    AND status_pagamento = 'pago'
    AND EXISTS (SELECT 1 FROM pedido_itens WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    v_result := public.processar_pedido_estoque_trigger(v_pedido.id, v_pedido.uf_postagem);
    v_total_processados := v_total_processados + 1;
  END LOOP;

  RETURN jsonb_build_object('total_pedidos_processados', v_total_processados);
END;
$$;

COMMIT;

-- Para usar:
-- SELECT * FROM get_estoque_produto(); -- Ver estoque atual (com pedidos pendentes)
-- SELECT atualizar_estoque_snapshot(); -- Atualizar snapshot cache
-- SELECT processar_todos_estoque_pendente(); -- Abater todos os pedidos pendentes de uma vez
-- SELECT processar_pedido_estoque_trigger('UUID', 'SP'); -- Abater pedido especifico
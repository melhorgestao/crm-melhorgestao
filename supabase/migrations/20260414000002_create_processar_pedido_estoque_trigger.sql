-- Criar função processar_pedido_estoque_trigger que está faltando
-- Execute no Supabase SQL Editor

-- 1. Função para processar estoque do pedido (assinatura: uuid, text)
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(p_pedido_id uuid, p_uf_postagem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item record;
  v_produto record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_item_id uuid;
  v_total_items integer := 0;
  v_processed_items integer := 0;
  v_skipped_items integer := 0;
  v_result jsonb := '[]'::jsonb;
BEGIN
  -- Buscar UF do cliente (usa p_uf_postagem se fornecido, ou busca do contato)
  v_uf_cliente := p_uf_postagem;
  
  IF v_uf_cliente IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct
    WHERE ct.id = (SELECT contato_id FROM pedidos WHERE id = p_pedido_id);
  END IF;

  -- Loop nos itens do pedido
  FOR v_item IN
    SELECT * FROM pedido_itens WHERE pedido_id = p_pedido_id
  LOOP
    v_total_items := v_total_items + 1;

    -- IDEMPOTENCIA: verifica se ja existe movimentacao para este item
    SELECT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id
    ) INTO v_mov_exists;

    IF v_mov_exists THEN
      v_skipped_items := v_skipped_items + 1;
      CONTINUE;
    END IF;

    -- Buscar produto
    SELECT * INTO v_produto FROM produtos WHERE id = v_item.produto_id;
    IF v_produto IS NULL THEN CONTINUE; END IF;

    -- FIFO deduction from lotes
    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque do produto
    UPDATE produtos SET estoque_atual = estoque_atual - v_item.quantidade WHERE id = v_item.produto_id;

    v_processed_items := v_processed_items + 1;
  END LOOP;

  -- Marcar pedido como processado
  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'total_items', v_total_items,
    'processed', v_processed_items,
    'skipped', v_skipped_items
  );
END;
$$;

-- 2. Garantir que trigger_function trigger_processar_pedido_estoque existe
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uf_postagem text;
BEGIN
  -- Se uf_postagem foi definido no pedido, usa ele
  v_uf_postagem := NEW.uf_postagem;
  
  -- Só processa se tem uf_postagem e ainda não foi processado
  IF v_uf_postagem IS NOT NULL AND (NEW.estoque_processado IS NULL OR NEW.estoque_processado = false) THEN
    PERFORM public.processar_pedido_estoque_trigger(NEW.id, v_uf_postagem);
  END IF;
  
  RETURN NEW;
END;
$$;

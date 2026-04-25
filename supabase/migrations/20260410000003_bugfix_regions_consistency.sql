-- BUGFIX: CONSISTÊNCIA DE REGIONALIZAÇÃO E ESTOQUE
-- 1. Atualiza criar_regiao_uf para migrar remetentes
-- 2. Ajusta priorização de estoque para reconhecer prefixos de UF (RS matches RS1)

BEGIN;

-- 1. ATUALIZAÇÃO DA RPC DE CRIAÇÃO DE REGIÃO
CREATE OR REPLACE FUNCTION public.criar_regiao_uf(p_uf text, p_tag text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_seq integer;
  v_codigo text;
  v_regiao_id uuid;
  v_is_first boolean;
BEGIN
  -- 1. Descobrir o próximo sequencial
  SELECT COALESCE(MAX(sequencial), 0) + 1 INTO v_seq FROM uf_regioes WHERE uf = p_uf;
  v_codigo := p_uf || v_seq::text;
  v_is_first := (v_seq = 1);

  -- 2. Criar a região
  INSERT INTO uf_regioes (uf, tag, codigo, sequencial)
  VALUES (p_uf, p_tag, v_codigo, v_seq)
  RETURNING id INTO v_regiao_id;

  -- 3. Se for a primeira região, MIGRAR dados da UF base para UF1
  IF v_is_first THEN
    -- estoque_movimentacoes
    UPDATE estoque_movimentacoes SET uf_origem = v_codigo WHERE uf_origem = p_uf;
    UPDATE estoque_movimentacoes SET posse = v_codigo WHERE posse = p_uf;
    
    -- lotes
    UPDATE lotes SET uf = v_codigo WHERE uf = p_uf;
    
    -- pedidos
    UPDATE pedidos SET uf_postagem = v_codigo WHERE uf_postagem = p_uf;
    UPDATE pedidos SET uf_cliente = v_codigo WHERE uf_cliente = p_uf;

    -- remetentes_uf (IMPORTANTE PARA LOGÍSTICA)
    UPDATE remetentes_uf SET uf = v_codigo WHERE uf = p_uf;

    -- snapshot
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'estoque_snapshot') THEN
       UPDATE estoque_snapshot SET estado = v_codigo WHERE estado = p_uf;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'id', v_regiao_id,
    'codigo', v_codigo,
    'migrado', v_is_first
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- 2. ATUALIZAÇÃO DA PRIORIZAÇÃO DE ESTOQUE (RECONHECER REGIÕES)
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
  -- Tenta pegar a UF de postagem, se não tiver, pega a do cliente
  v_uf_cliente := p_uf_postagem;
  
  IF v_uf_cliente IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM public.contatos ct, public.pedidos p WHERE p.id = p_pedido_id AND ct.id = p.contato_id;
  END IF;

  -- Normalizar UF cliente para busca de prefixo (ex: 'RS' em 'RS1')
  -- Se o cliente for de 'RS' e não tivermos 'RS' exato, buscamos 'RS%'

  FOR v_item IN SELECT * FROM public.pedido_itens WHERE pedido_id = p_pedido_id LOOP
    v_total_items := v_total_items + 1;
    SELECT EXISTS (SELECT 1 FROM public.estoque_movimentacoes WHERE pedido_item_id = v_item.id) INTO v_mov_exists;
    IF v_mov_exists THEN CONTINUE; END IF;

    v_remaining := v_item.quantidade;
    
    -- Prioridade 1: Match Exato da UF (ex: 'RS1' == 'RS1')
    -- Prioridade 2: Match por Prefixo (ex: 'RS' match 'RS1', 'RS2')
    -- Prioridade 3: Resto (FIFO Global)
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM public.lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY 
        (uf = v_uf_cliente) DESC, -- Match exato primeiro
        (uf LIKE v_uf_cliente || '%') DESC, -- Região daquela UF depois
        created_at ASC -- FIFO Global por fim
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      
      UPDATE public.lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      
      INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, pedido_id, observacao, criado_por)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, p_pedido_id, 'Pedido #' || p_pedido_id::text, 'Sistema (Auto)');
      
      v_remaining := v_remaining - v_deduct;
    END LOOP;
    
    v_processed_items := v_processed_items + 1;
  END LOOP;

  UPDATE public.pedidos SET estoque_processado = true WHERE id = p_pedido_id;
  
  -- Sincronizar Snapshot
  IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
     PERFORM public.atualizar_estoque_snapshot();
  END IF;
  
  RETURN jsonb_build_object('pedido_id', p_pedido_id::text, 'total_items', v_total_items, 'processed', v_processed_items);
END;
$$;

COMMIT;

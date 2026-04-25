-- RPC criar_pedido: cria pedido + itens + abate estoque numa transacao
-- Padrao: bypass PostgREST, tudo via SQL direto no Supabase

CREATE OR REPLACE FUNCTION public.criar_pedido(
  p_contato_id uuid,
  p_canal text,
  p_valor numeric,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT NULL,
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido_id uuid;
  v_data_sp date;
  v_total_qty integer := 0;
  v_prod jsonb;
  v_prod_id uuid;
  v_prod_qty integer;
  v_prod_nome text;
  v_prod_preco numeric;
  v_produtos_array jsonb := '[]'::jsonb;
  v_remaining integer;
  v_lote_rec record;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_item_id uuid;
  v_has_large boolean := false;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  v_contato_endereco text;
  v_contato_numero text;
  v_order_number integer;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Buscar endereco do contato
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero
  FROM contatos WHERE id = p_contato_id;

  -- Buscar UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = p_contato_id;

  -- Processar produtos e abater estoque
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_nome := v_prod->>'nome_oficial';
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;
      v_total_qty := v_total_qty + v_prod_qty;

      IF lower(v_prod_nome) LIKE '%gummy%' OR lower(v_prod_nome) LIKE '%pomada%' OR lower(v_prod_nome) LIKE '%lub%' THEN
        v_has_large := true;
      END IF;

      v_produtos_array := v_produtos_array || jsonb_build_object(
        'produto', v_prod_nome,
        'produto_id', v_prod_id,
        'quantidade', v_prod_qty,
        'valor_unit', v_prod_preco
      );

      -- FIFO deduction from lotes
      v_remaining := v_prod_qty;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = v_prod_id AND quantidade_atual > 0
        ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
        VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, 'criar_pedido_pending');
        v_remaining := v_remaining - v_deduct;
      END LOOP;

      -- Decrementa estoque
      UPDATE produtos SET estoque_atual = estoque_atual - v_prod_qty WHERE id = v_prod_id;
    END LOOP;
  END IF;

  -- Calcular dimensoes da caixa
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF v_has_large OR v_total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  -- Criar pedido com estoque_processado=true
  INSERT INTO pedidos (
    contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento,
    criado_por, obs, endereco_entrega, data, estoque_processado
  ) VALUES (
    p_contato_id, v_produtos_array::text, v_total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento,
    p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END,
    v_data_sp, true
  ) RETURNING id, order_number INTO v_pedido_id, v_order_number;

  -- Vincular movimentacoes ao pedido
  UPDATE estoque_movimentacoes
  SET pedido_id = v_pedido_id, observacao = 'Pedido #' || v_pedido_id::text
  WHERE observacao = 'criar_pedido_pending' AND pedido_id IS NULL;

  -- Criar pedido_itens para cada produto
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;

      IF v_prod_id IS NOT NULL AND v_prod_qty IS NOT NULL THEN
        INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, valor_unit)
        VALUES (v_pedido_id, v_prod_id, v_prod_qty, v_prod_preco);
      END IF;
    END LOOP;
  END IF;

  -- Atualizar ultima_venda_em do contato
  UPDATE contatos SET ultima_venda_em = v_data_sp, status_kanban = 'Pagou', updated_at = now()
  WHERE id = p_contato_id;

  RETURN jsonb_build_object(
    'pedido_id', v_pedido_id::text,
    'order_number', v_order_number,
    'quantidade', v_total_qty,
    'status', 'ok'
  );
END;
$$;

NOTIFY pgrst, 'reload schema';

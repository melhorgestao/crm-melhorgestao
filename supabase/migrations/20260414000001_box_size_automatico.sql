-- Migration: Box Size automático por produto

-- 1. Adicionar coluna box_size na tabela produtos
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_size TEXT;

-- 2. Adicionar coluna box_size na tabela pedidos  
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS box_size TEXT;

-- 3. Atualizar RPC create_produto para incluir box_size
CREATE OR REPLACE FUNCTION create_produto(
  p_nome_oficial TEXT,
  p_tag TEXT,
  p_cor_card TEXT DEFAULT '#ffffff',
  p_cor_texto TEXT DEFAULT '#000000',
  p_limite_estoque INTEGER DEFAULT 0,
  p_grupo_id UUID DEFAULT NULL,
  p_box_size TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO produtos (nome_oficial, tag, cor_card, cor_texto, limite_estoque, grupo_id, box_size)
  VALUES (p_nome_oficial, p_tag, p_cor_card, p_cor_texto, p_limite_estoque, p_grupo_id, p_box_size)
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;

-- 4. Atualizar RPC update_produto para incluir box_size
CREATE OR REPLACE FUNCTION update_produto(
  p_id UUID,
  p_nome_oficial TEXT,
  p_tag TEXT,
  p_cor_card TEXT,
  p_cor_texto TEXT,
  p_limite_estoque INTEGER,
  p_grupo_id UUID,
  p_box_size TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE produtos 
  SET nome_oficial = p_nome_oficial,
      tag = p_tag,
      cor_card = p_cor_card,
      cor_texto = p_cor_texto,
      limite_estoque = p_limite_estoque,
      grupo_id = p_grupo_id,
      box_size = p_box_size,
      updated_at = now()
  WHERE id = p_id;
END;
$$;

-- 5. Atualizar RPC criar_pedido para calcular box_size automaticamente
CREATE OR REPLACE FUNCTION criar_pedido(
  p_contato_id UUID,
  p_produtos JSONB,
  p_valor NUMERIC,
  p_canal TEXT,
  p_modalidade TEXT,
  p_uf_postagem TEXT,
  p_status_pagamento TEXT,
  p_criado_por TEXT,
  p_obs TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_pedido_id UUID;
  v_order_number TEXT;
  v_total_qty INTEGER := 0;
  v_data_sp TIMESTAMPTZ;
  v_box_size TEXT;
  v_prod_box_rank INTEGER;
  v_prod JSONB;
  v_prod_id UUID;
  v_prod_qty INTEGER;
  v_prod_preco NUMERIC;
  v_peso INTEGER;
  v_altura INTEGER;
  v_largura INTEGER;
  v_comprimento INTEGER;
BEGIN
  v_data_sp := now() AT TIME ZONE 'America/Sao_Paulo';

  -- Determinar box_size automaticamente
  IF p_modalidade = 'mini' OR p_modalidade = 'entrega_maos' THEN
    v_box_size := 'MINI';
  ELSE
    -- Buscar maior box_size entre os produtos do pedido
    SELECT INTO v_box_size MAX(
      CASE p.box_size
        WHEN 'GG' THEN 5
        WHEN 'G' THEN 4
        WHEN 'M' THEN 3
        WHEN 'P' THEN 2
        WHEN 'MINI' THEN 1
        ELSE 1
      END
    )::TEXT
    FROM jsonb_array_elements(p_produtos) AS prod
    LEFT JOIN produtos p ON p.id = (prod->>'produto_id')::uuid
    WHERE prod->>'produto_id' IS NOT NULL AND p.box_size IS NOT NULL;
    
    v_box_size := CASE v_box_size
      WHEN '5' THEN 'GG'
      WHEN '4' THEN 'G'
      WHEN '3' THEN 'M'
      WHEN '2' THEN 'P'
      ELSE 'MINI'
    END;
  END IF;

  -- Dimensões por box_size
  v_box_size := COALESCE(v_box_size, 'MINI');
  CASE v_box_size
    WHEN 'MINI' THEN v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    WHEN 'P' THEN v_peso := 500; v_altura := 4; v_largura := 11; v_comprimento := 16;
    WHEN 'M' THEN v_peso := 800; v_altura := 6; v_largura := 15; v_comprimento := 20;
    WHEN 'G' THEN v_peso := 1200; v_altura := 8; v_largura := 20; v_comprimento := 25;
    WHEN 'GG' THEN v_peso := 2000; v_altura := 10; v_largura := 25; v_comprimento := 30;
    ELSE v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  END CASE;

  -- Processar produtos
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;
      v_total_qty := v_total_qty + v_prod_qty;

      IF v_prod_id IS NOT NULL THEN
        UPDATE produtos SET estoque_atual = estoque_atual - v_prod_qty WHERE id = v_prod_id;
      END IF;
    END LOOP;
  END IF;

  -- Criar pedido
  INSERT INTO pedidos (
    contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    box_size, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento,
    criado_por, obs, data, estoque_processado
  ) VALUES (
    p_contato_id, p_produtos::text, v_total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem,
    v_box_size, v_peso, v_altura, v_largura, v_comprimento,
    p_status_pagamento, p_criado_por, p_obs,
    v_data_sp, true
  ) RETURNING id, order_number INTO v_pedido_id, v_order_number;

  -- Criar pedido_itens
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

  -- Atualizar contato
  UPDATE contatos SET ultima_venda_em = v_data_sp, status_kanban = 'Pagou', updated_at = now()
  WHERE id = p_contato_id;

  RETURN jsonb_build_object('pedido_id', v_pedido_id::text, 'order_number', v_order_number, 'data', v_data_sp);
END;
$$;
-- Migration completa: Box Size com quantidade máxima

-- 1. Adicionar colunas na tabela produtos
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_size TEXT;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_qty_max INTEGER DEFAULT 10;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- 2. Adicionar coluna box_size na tabela pedidos  
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS box_size TEXT;

-- 3. Atualizar RPC create_produto para incluir box_size e box_qty_max
CREATE OR REPLACE FUNCTION create_produto(
  p_nome_oficial TEXT,
  p_tag TEXT,
  p_cor_card TEXT DEFAULT '#ffffff',
  p_cor_texto TEXT DEFAULT '#000000',
  p_limite_estoque INTEGER DEFAULT 0,
  p_grupo_id UUID DEFAULT NULL,
  p_box_size TEXT DEFAULT NULL,
  p_box_qty_max INTEGER DEFAULT 10
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO produtos (nome_oficial, tag, cor_card, cor_texto, limite_estoque, grupo_id, box_size, box_qty_max)
  VALUES (p_nome_oficial, p_tag, p_cor_card, p_cor_texto, p_limite_estoque, p_grupo_id, p_box_size, p_box_qty_max)
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;

-- 4. Atualizar RPC update_produto para incluir box_size e box_qty_max
CREATE OR REPLACE FUNCTION update_produto(
  p_id UUID,
  p_nome_oficial TEXT,
  p_tag TEXT,
  p_cor_card TEXT,
  p_cor_texto TEXT,
  p_limite_estoque INTEGER,
  p_grupo_id UUID,
  p_box_size TEXT DEFAULT NULL,
  p_box_qty_max INTEGER DEFAULT 10
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
      box_qty_max = p_box_qty_max,
      updated_at = now()
  WHERE id = p_id;
END;
$$;

-- 5. Atualizar RPC criar_pedido para calcular box_size com lógica de quantidade
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
  v_prod JSONB;
  v_prod_id UUID;
  v_prod_qty INTEGER;
  v_prod_preco NUMERIC;
  v_peso INTEGER;
  v_altura INTEGER;
  v_largura INTEGER;
  v_comprimento INTEGER;
  v_needed_rank INTEGER := 1;
  v_current_box_rank INTEGER;
  v_prod_box_size TEXT;
  v_prod_qty_max INTEGER;
  v_box_size_override TEXT := NULL;
BEGIN
  v_data_sp := now() AT TIME ZONE 'America/Sao_Paulo';

  -- Calcular total de itens no pedido
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
      v_total_qty := v_total_qty + v_prod_qty;
    END LOOP;
  END IF;

  -- Se modo MINI ou ENTREGA_MAOS: verificar se cabe na caixa definida do produto
  IF p_modalidade = 'mini' OR p_modalidade = 'entrega_maos' THEN
    -- Para cada produto no pedido, verificar se a qtd cabe no box_size definido
    IF p_produtos IS NOT NULL THEN
      FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
      LOOP
        v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
        v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
        
        SELECT p.box_size, COALESCE(p.box_qty_max, 10)
        INTO v_prod_box_size, v_prod_qty_max
        FROM produtos p WHERE p.id = v_prod_id;
        
        -- Se quantidade exceder o limite da caixa do produto
        IF v_prod_qty > v_prod_qty_max THEN
          v_box_size_override := 'EXCEDE_MINI';
        END IF;
      END LOOP;
    END IF;
  ELSE
    -- Para PAC/SEDEX: aplicar lógica de upgrade por quantidade
    v_needed_rank := 1;
    
    IF p_produtos IS NOT NULL THEN
      FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
      LOOP
        v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
        v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
        
        SELECT p.box_size, COALESCE(p.box_qty_max, 10)
        INTO v_prod_box_size, v_prod_qty_max
        FROM produtos p WHERE p.id = v_prod_id;
        
        v_current_box_rank := CASE v_prod_box_size
          WHEN 'GG' THEN 5
          WHEN 'G' THEN 4
          WHEN 'M' THEN 3
          WHEN 'P' THEN 2
          WHEN 'MINI' THEN 1
          ELSE 1
        END;
        
        -- Se quantidade exceder qty_max, fazer upgrade
        IF v_prod_qty > v_prod_qty_max THEN
          v_current_box_rank := LEAST(v_current_box_rank + 1, 5);
        END IF;
        
        IF v_current_box_rank > v_needed_rank THEN
          v_needed_rank := v_current_box_rank;
        END IF;
      END LOOP;
    END IF;
    
    v_box_size := CASE v_needed_rank
      WHEN 5 THEN 'GG'
      WHEN 4 THEN 'G'
      WHEN 3 THEN 'M'
      WHEN 2 THEN 'P'
      ELSE 'MINI'
    END;
  END IF;

  -- Se tem override (excedeu mini), usar tamanho maior
  IF v_box_size_override = 'EXCEDE_MINI' THEN
    v_box_size := 'P';
  ELSIF v_box_size IS NULL THEN
    v_box_size := 'MINI';
  END IF;

  -- Dimensões por box_size
  CASE COALESCE(v_box_size, 'MINI')
    WHEN 'MINI' THEN v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    WHEN 'P' THEN v_peso := 500; v_altura := 4; v_largura := 11; v_comprimento := 16;
    WHEN 'M' THEN v_peso := 800; v_altura := 6; v_largura := 15; v_comprimento := 20;
    WHEN 'G' THEN v_peso := 1200; v_altura := 8; v_largura := 20; v_comprimento := 25;
    WHEN 'GG' THEN v_peso := 2000; v_altura := 10; v_largura := 25; v_comprimento := 30;
    ELSE v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  END CASE;

  -- Processar produtos e decrementar estoque
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
      
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
      v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
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
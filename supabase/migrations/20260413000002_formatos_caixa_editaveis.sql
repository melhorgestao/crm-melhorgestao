-- Tabela de formatos de caixa editável no CRM
CREATE TABLE IF NOT EXISTS formatos_caixa (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome TEXT NOT NULL UNIQUE,
  descricao TEXT,
  peso_gramas INTEGER NOT NULL DEFAULT 300,
  altura_cm INTEGER NOT NULL DEFAULT 2,
  largura_cm INTEGER NOT NULL DEFAULT 11,
  comprimento_cm INTEGER NOT NULL DEFAULT 16,
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Inserir formatos padrão se não existirem
INSERT INTO formatos_caixa (nome, descricao, peso_gramas, altura_cm, largura_cm, comprimento_cm)
SELECT 'mini', 'Caixa para pedidos pequenos (1-5 itens)', 300, 2, 11, 16
WHERE NOT EXISTS (SELECT 1 FROM formatos_caixa WHERE nome = 'mini');

INSERT INTO formatos_caixa (nome, descricao, peso_gramas, altura_cm, largura_cm, comprimento_cm)
SELECT 'caixa_p', 'Caixa para pedidos maiores (mais de 5 itens ou produtos grandes)', 1000, 6, 11, 16
WHERE NOT EXISTS (SELECT 1 FROM formatos_caixa WHERE nome = 'caixa_p');

-- Atualizar RPC criar_pedido para usar a tabela de formatos
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
  v_produtos_array TEXT;
  v_total_qty INTEGER := 0;
  v_has_large BOOLEAN := false;
  v_prod JSONB;
  v_prod_id UUID;
  v_prod_qty INTEGER;
  v_prod_preco NUMERIC;
  v_contato_endereco TEXT;
  v_contato_numero TEXT;
  v_data_sp TIMESTAMPTZ;
  v_formato_caixa TEXT;
  v_peso INTEGER;
  v_altura INTEGER;
  v_largura INTEGER;
  v_comprimento INTEGER;
BEGIN
  -- Data SP
  v_data_sp := now() AT TIME ZONE 'America/Sao_Paulo';

  -- Processar produtos
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;

      v_total_qty := v_total_qty + v_prod_qty;

      IF v_prod_id IS NOT NULL THEN
        -- Verificar se tem produto grande
        SELECT INTO v_has_large EXISTS (
          SELECT 1 FROM produtos WHERE id = v_prod_id AND (altura_cm > 15 OR largura_cm > 15 OR comprimento_cm > 20)
        );
      END IF;
    END LOOP;
  END IF;

  -- Decrementa estoque
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;

      UPDATE produtos SET estoque_atual = estoque_atual - v_prod_qty WHERE id = v_prod_id;
    END LOOP;
  END IF;

  -- Buscar dimensoes da caixa da tabela de configurações
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    SELECT peso_gramas, altura_cm, largura_cm, comprimento_cm INTO v_peso, v_altura, v_largura, v_comprimento
    FROM formatos_caixa WHERE nome = 'mini' AND ativo = true LIMIT 1;
    v_formato_caixa := 'mini';
  ELSE
    IF v_has_large OR v_total_qty > 5 THEN
      SELECT nome, peso_gramas, altura_cm, largura_cm, comprimento_cm INTO v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento
      FROM formatos_caixa WHERE ativo = true ORDER BY peso_gramas DESC LIMIT 1;
    ELSE
      SELECT nome, peso_gramas, altura_cm, largura_cm, comprimento_cm INTO v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento
      FROM formatos_caixa WHERE nome = 'mini' AND ativo = true LIMIT 1;
    END IF;
  END IF;

  -- Criar pedido com estoque_processado=true
  INSERT INTO pedidos (
    contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento,
    criado_por, obs, endereco_entrega, data, estoque_processado
  ) VALUES (
    p_contato_id, p_produtos::text, v_total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento,
    p_status_pagamento, p_criado_por, p_obs,
    (SELECT endereco || COALESCE(', ' || numero, '') FROM contatos WHERE id = p_contato_id),
    v_data_sp, true
  ) RETURNING id, order_number INTO v_pedido_id, v_order_number;

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
    'data', v_data_sp
  );
END;
$$;
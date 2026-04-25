-- PART 1 & 7: Table changes and Foreign Keys

-- 1.1 Tabela pedidos — colunas
ALTER TABLE pedidos 
ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago' 
  CHECK (status_pagamento IN ('pago', 'pendente')),
ADD COLUMN IF NOT EXISTS complemento text,
ADD COLUMN IF NOT EXISTS criado_por text;

-- 1.2 Tabela lancamentos_socios — colunas
ALTER TABLE lancamentos_socios
ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago'
  CHECK (status_pagamento IN ('pago', 'pendente')),
ADD COLUMN IF NOT EXISTS criado_por text;

-- 1.2b Tabela perfis_usuario — colunas
ALTER TABLE perfis_usuario
ADD COLUMN IF NOT EXISTS pode_excluir_card boolean DEFAULT true;

-- 1.3 & 7: Foreign Keys and pedido_id
-- 1. pedidos → contatos
ALTER TABLE pedidos 
  DROP CONSTRAINT IF EXISTS pedidos_contato_id_fkey,
  ADD CONSTRAINT pedidos_contato_id_fkey 
    FOREIGN KEY (contato_id) REFERENCES contatos(id) ON DELETE SET NULL;

-- 2. lancamentos_socios → contatos
ALTER TABLE lancamentos_socios
  DROP CONSTRAINT IF EXISTS lancamentos_socios_contato_id_fkey,
  ADD CONSTRAINT lancamentos_socios_contato_id_fkey
    FOREIGN KEY (contato_id) REFERENCES contatos(id) ON DELETE SET NULL;

-- 3. lancamentos_socios → pedidos
ALTER TABLE lancamentos_socios
  ADD COLUMN IF NOT EXISTS pedido_id uuid;

ALTER TABLE lancamentos_socios
  DROP CONSTRAINT IF EXISTS lancamentos_socios_pedido_id_fkey,
  ADD CONSTRAINT lancamentos_socios_pedido_id_fkey
    FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE SET NULL;

-- 4. estoque_movimentacoes → lotes
ALTER TABLE estoque_movimentacoes
  DROP CONSTRAINT IF EXISTS estoque_movimentacoes_lote_id_fkey,
  ADD CONSTRAINT estoque_movimentacoes_lote_id_fkey
    FOREIGN KEY (lote_id) REFERENCES lotes(id) ON DELETE SET NULL;

-- 5. lotes → produtos
ALTER TABLE lotes
  DROP CONSTRAINT IF EXISTS lotes_produto_id_fkey,
  ADD CONSTRAINT lotes_produto_id_fkey
    FOREIGN KEY (produto_id) REFERENCES produtos(id) ON DELETE CASCADE;

-- 6. estoque_movimentacoes → produtos
ALTER TABLE estoque_movimentacoes
  DROP CONSTRAINT IF EXISTS estoque_movimentacoes_produto_id_fkey,
  ADD CONSTRAINT estoque_movimentacoes_produto_id_fkey
    FOREIGN KEY (produto_id) REFERENCES produtos(id) ON DELETE CASCADE;

-- 7. follow_up → contatos
ALTER TABLE follow_up
  DROP CONSTRAINT IF EXISTS follow_up_contato_id_fkey,
  ADD CONSTRAINT follow_up_contato_id_fkey
    FOREIGN KEY (contato_id) REFERENCES contatos(id) ON DELETE CASCADE;

-- 8. contatos → instancias
ALTER TABLE contatos
  DROP CONSTRAINT IF EXISTS contatos_instancia_id_fkey,
  ADD CONSTRAINT contatos_instancia_id_fkey
    FOREIGN KEY (instancia_id) REFERENCES instancias(id) ON DELETE SET NULL;

-- 9. financeiro — update check constraint for tipo
ALTER TABLE financeiro 
  DROP CONSTRAINT IF EXISTS financeiro_tipo_check,
  ADD CONSTRAINT financeiro_tipo_check 
    CHECK (tipo IN ('receita', 'despesa', 'receita_pendente'));

-- 10. Update process_venda RPC logic
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
BEGIN
  -- Get client UF
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build products array and deduct stoichiometry
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    -- FIFO deduction
    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  -- Always move Kanban to Pagou (Requirement Part 2.4 point 5)
  v_status_kanban := 'Pagou';

  -- Create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por)
  RETURNING id INTO v_pedido_id;

  -- Financeiro and Lancamentos logic
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);

    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  -- Update kanban
  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

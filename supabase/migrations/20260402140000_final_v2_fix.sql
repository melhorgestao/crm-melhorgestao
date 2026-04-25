-- 1. FIX TABLE COLUMNS
ALTER TABLE pedidos 
ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago' 
  CHECK (status_pagamento IN ('pago', 'pendente')),
ADD COLUMN IF NOT EXISTS complemento text,
ADD COLUMN IF NOT EXISTS criado_por text,
ADD COLUMN IF NOT EXISTS recebido_por text;

ALTER TABLE lancamentos_socios
ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago'
  CHECK (status_pagamento IN ('pago', 'pendente')),
ADD COLUMN IF NOT EXISTS criado_por text;

-- 2. UPDATE CONSTRAINTS
ALTER TABLE lancamentos_socios 
  DROP CONSTRAINT IF EXISTS lancamentos_socios_socio_check,
  ADD CONSTRAINT lancamentos_socios_socio_check 
    CHECK (socio IN ('V', 'A', 'P'));

ALTER TABLE financeiro 
  DROP CONSTRAINT IF EXISTS financeiro_tipo_check,
  ADD CONSTRAINT financeiro_tipo_check 
    CHECK (tipo IN ('receita', 'despesa', 'receita_pendente'));

-- 3. DROP AND RECREATE RPC
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text);

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
  v_recebido_por text;
BEGIN
  -- Determine receiver
  IF p_status_pagamento = 'pendente' THEN
    v_recebido_por := 'P';
  ELSE
    v_recebido_por := p_socio;
  END IF;

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

  -- Package dimensions
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

  v_status_kanban := 'Pagou';

  -- Create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, recebido_por)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, v_recebido_por)
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

NOTIFY pgrst, 'reload schema';

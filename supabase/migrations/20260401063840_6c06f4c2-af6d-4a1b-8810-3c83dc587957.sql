
-- 1. Create remetentes_uf table
CREATE TABLE public.remetentes_uf (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uf text UNIQUE NOT NULL,
  cep_origem text,
  cidade text,
  bairro text,
  endereco text,
  numero text,
  complemento text,
  nome_remetente text,
  contato_remetente text,
  cpf text,
  updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.remetentes_uf ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage remetentes_uf" ON public.remetentes_uf FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Pre-populate with 4 UFs
INSERT INTO public.remetentes_uf (uf) VALUES ('SC'), ('RS'), ('SP'), ('GO');

-- 2. Create configuracoes table for API keys
CREATE TABLE public.configuracoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chave text UNIQUE NOT NULL,
  valor text,
  updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage configuracoes" ON public.configuracoes FOR ALL TO authenticated USING (true) WITH CHECK (true);

INSERT INTO public.configuracoes (chave, valor) VALUES ('chave_api_superfrete', '');

-- 3. Add new columns to pedidos
ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS modalidade text,
  ADD COLUMN IF NOT EXISTS uf_postagem text,
  ADD COLUMN IF NOT EXISTS formato_caixa text,
  ADD COLUMN IF NOT EXISTS peso_envio integer,
  ADD COLUMN IF NOT EXISTS altura_caixa integer,
  ADD COLUMN IF NOT EXISTS largura_caixa integer,
  ADD COLUMN IF NOT EXISTS comprimento_caixa integer,
  ADD COLUMN IF NOT EXISTS etiqueta_url text,
  ADD COLUMN IF NOT EXISTS etiqueta_codigo text;

-- 4. Add new columns to lancamentos_socios
ALTER TABLE public.lancamentos_socios
  ADD COLUMN IF NOT EXISTS modalidade text,
  ADD COLUMN IF NOT EXISTS uf_postagem text;

-- 5. Update process_venda to handle FIFO lote deduction and new fields
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text, p_canal text, p_valor numeric, p_contato_id uuid, p_produtos jsonb,
  p_modalidade text DEFAULT 'mini', p_uf_postagem text DEFAULT NULL
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
  used_fallback boolean := false;
  fallback_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
BEGIN
  -- Get client UF from cidade_uf (last 2 chars)
  SELECT RIGHT(TRIM(cidade_uf), 2) INTO client_uf FROM contatos WHERE id = p_contato_id;

  -- Build the JSON array of products for the single pedido
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    -- Check if product is gummy, pomada, or lubrificante
    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_array(jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    ));

    -- FIFO lote deduction
    remaining := prod_qty;
    
    -- First try lotes matching client UF
    FOR lote_rec IN 
      SELECT id, quantidade_atual, uf FROM lotes 
      WHERE produto_id = prod_id AND quantidade_atual > 0 AND uf = COALESCE(client_uf, '')
      ORDER BY data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    -- Fallback: use oldest lote across ALL UFs
    IF remaining > 0 THEN
      FOR lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = prod_id AND quantidade_atual > 0
        ORDER BY data_producao ASC
      LOOP
        IF remaining <= 0 THEN EXIT; END IF;
        deduct := LEAST(remaining, lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
        VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
        remaining := remaining - deduct;
        used_fallback := true;
        fallback_uf := lote_rec.uf;
      END LOOP;
    END IF;

    -- Always deduct from produtos.estoque_atual
    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions based on modalidade
  IF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini';
    v_peso := 300;
    v_altura := 2;
    v_largura := 11;
    v_comprimento := 16;
  ELSE
    -- pac or sedex
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p';
      v_peso := 1000;
      v_altura := 6;
      v_largura := 11;
      v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini';
      v_peso := 300;
      v_altura := 2;
      v_largura := 11;
      v_comprimento := 16;
    END IF;
  END IF;

  -- 1 lancamento
  INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem)
  VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem);

  -- 1 single pedido with all products as JSON
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, produto_id, preco_unitario,
    modalidade, uf_postagem, formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', NULL, NULL,
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento);

  -- 1 financeiro
  INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);

  -- Update kanban
  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- Fix: Drop the orphaned 7-param process_venda that was never removed
-- This causes PostgREST ambiguity when calling the 8-param version
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text);

-- Also drop any leftover 5-param version just in case
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb);

-- Add separate cidade and uf columns to contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS cidade text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS uf text;

-- Backfill cidade and uf from cidade_uf
DO $$
BEGIN
  UPDATE public.contatos
  SET
    cidade = CASE
      WHEN cidade_uf IS NOT NULL AND cidade_uf LIKE '%/%' THEN TRIM(SPLIT_PART(cidade_uf, '/', 1))
      WHEN cidade_uf IS NOT NULL AND LENGTH(TRIM(cidade_uf)) > 2 THEN TRIM(LEFT(cidade_uf, LENGTH(cidade_uf) - 2))
      ELSE cidade_uf
    END,
    uf = CASE
      WHEN cidade_uf IS NOT NULL AND cidade_uf LIKE '%/%' THEN TRIM(SPLIT_PART(cidade_uf, '/', 2))
      WHEN cidade_uf IS NOT NULL AND LENGTH(TRIM(cidade_uf)) >= 2 THEN TRIM(RIGHT(cidade_uf, 2))
      ELSE NULL
    END
  WHERE cidade IS NULL AND cidade_uf IS NOT NULL;
END $$;

-- Recreate the definitive process_venda with 8 params (the only version)
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago'
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
  -- Get client UF from uf column first, fallback to cidade_uf
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build the JSON array of products
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

    produtos_array := produtos_array || jsonb_build_array(jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    ));

    -- FIFO lote deduction
    remaining := prod_qty;

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

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL;
    v_peso := NULL;
    v_altura := NULL;
    v_largura := NULL;
    v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini';
    v_peso := 300;
    v_altura := 2;
    v_largura := 11;
    v_comprimento := 16;
  ELSE
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

  -- Only create lancamento if pago
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem);

    INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);
  END IF;

  -- Always create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, produto_id, preco_unitario,
    modalidade, uf_postagem, formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', NULL, NULL,
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento);

  -- Update kanban
  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$$;

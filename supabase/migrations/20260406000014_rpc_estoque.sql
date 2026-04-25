-- RPC criar_lote_estoque: cria lote + atualiza estoque + registra movimentacao
-- Padrao: bypass PostgREST, tudo via SQL direto no Supabase

CREATE OR REPLACE FUNCTION public.criar_lote_estoque(
  p_produto_id uuid,
  p_uf text,
  p_quantidade integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_lote_id uuid;
  v_lote_codigo text;
  v_today text;
  v_seq integer;
  v_last text;
  v_prod record;
BEGIN
  -- Gerar codigo do lote
  v_today := to_char(now(), 'YYYYMMDD');
  SELECT COALESCE(MAX(lote_codigo), '') INTO v_last FROM lotes WHERE lote_codigo LIKE 'LOTE-' || v_today || '-%';
  IF v_last <> '' THEN
    v_seq := COALESCE(NULLIF(split_part(v_last, '-', 3), '')::integer, 0) + 1;
  ELSE
    v_seq := 1;
  END IF;
  v_lote_codigo := 'LOTE-' || v_today || '-' || lpad(v_seq::text, 3, '0');

  -- Buscar produto
  SELECT * INTO v_prod FROM produtos WHERE id = p_produto_id;
  IF v_prod IS NULL THEN
    RETURN jsonb_build_object('error', 'produto nao encontrado');
  END IF;

  -- Criar lote
  INSERT INTO lotes (produto_id, uf, quantidade_inicial, quantidade_atual, lote_codigo)
  VALUES (p_produto_id, p_uf, p_quantidade, p_quantidade, v_lote_codigo)
  RETURNING id INTO v_lote_id;

  -- Atualizar estoque
  UPDATE produtos SET estoque_atual = estoque_atual + p_quantidade WHERE id = p_produto_id;

  -- Registrar movimentacao
  INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, lote_id)
  VALUES (p_produto_id, p_quantidade, 'entrada', p_uf, p_uf, v_lote_id);

  RETURN jsonb_build_object('status', 'ok', 'lote_codigo', v_lote_codigo, 'lote_id', v_lote_id::text);
END;
$$;

-- RPC reprocessar_pedidos_estoque: reprocessa TODOS pedidos com uf_postagem
CREATE OR REPLACE FUNCTION public.reprocessar_pedidos_estoque()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ped record; v_item jsonb; v_prod_id uuid; v_qty integer; v_lote_rec record;
  v_remaining integer; v_deduct integer; v_produto record; v_produto_text text;
  v_ok integer := 0; v_err integer := 0; v_uf text;
BEGIN
  -- Reset todos
  UPDATE pedidos SET estoque_processado = false;
  DELETE FROM estoque_movimentacoes WHERE tipo = 'saida';

  -- Recalcular estoque com lotes
  DO $inner$
    DECLARE vp record; vt integer;
    BEGIN
      FOR vp IN SELECT id FROM produtos WHERE ativo = true LOOP
        SELECT COALESCE(SUM(quantidade_atual), 0)::integer INTO vt FROM lotes WHERE produto_id = vp.id;
        UPDATE produtos SET estoque_atual = vt WHERE id = vp.id;
      END LOOP;
    END $inner$;

  FOR v_ped IN
    SELECT * FROM pedidos
    WHERE (produto IS NOT NULL AND trim(produto) <> '')
      AND uf_postagem IS NOT NULL AND trim(uf_postagem) <> ''
    ORDER BY created_at ASC
  LOOP
    v_uf := v_ped.uf_postagem;
    v_produto_text := v_ped.produto;
    IF v_produto_text LIKE '[%' THEN
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb) LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qty := (v_item->>'quantidade')::integer;
          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1; END IF;
          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
          IF v_produto IS NULL THEN CONTINUE; END IF;
          v_remaining := v_qty;
          FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
            IF v_remaining <= 0 THEN EXIT; END IF;
            v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, v_ped.id, 'Pedido #' || v_ped.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;
          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
        v_ok := v_ok + 1;
      EXCEPTION WHEN OTHERS THEN v_err := v_err + 1; END;
    ELSE
      v_prod_id := v_ped.produto_id; v_qty := v_ped.quantidade;
      IF v_prod_id IS NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_produto_text)) LIMIT 1; END IF;
      IF v_prod_id IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      v_remaining := v_qty;
      FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, v_ped.id, 'Pedido #' || v_ped.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;
      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      v_ok := v_ok + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', v_ok, 'errors', v_err);
END;
$$;

NOTIFY pgrst, 'reload schema';

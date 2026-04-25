-- RPC definitivo: processar_pedido_estoque
-- Suporta pedidos com produto=text ou produto=json array
-- Idempotente: nao duplica movimentacoes
-- Nao altera estrutura da tabela pedidos

-- 1. Garantir coluna pedido_id em estoque_movimentacoes (ja existe observacao como fallback)
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

-- 2. Index para performance de idempotencia
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido_id ON public.estoque_movimentacoes(pedido_id);

-- 3. Funcao RPC principal
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque(p_pedido_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido record;
  v_produto_text text;
  v_produto_id uuid;
  v_quantidade integer;
  v_item jsonb;
  v_prod_record record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_result jsonb := '[]'::jsonb;
BEGIN
  -- Buscar dados do pedido
  SELECT * INTO v_pedido FROM pedidos WHERE id = p_pedido_id;

  IF v_pedido IS NULL THEN
    RETURN jsonb_build_object('error', 'pedido nao encontrado', 'pedido_id', p_pedido_id::text);
  END IF;

  -- Buscar UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = v_pedido.contato_id;

  -- IDEMPOTENCIA: verifica se pedido ja foi processado
  SELECT EXISTS (
    SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = p_pedido_id
  ) INTO v_mov_exists;

  IF v_mov_exists THEN
    RETURN jsonb_build_object('status', 'skipped', 'motivo', 'pedido ja processado', 'pedido_id', p_pedido_id::text);
  END IF;

  v_produto_text := v_pedido.produto;

  -- CASO 1: produto e JSON array (formato do process_venda)
  IF v_produto_text IS NOT NULL AND trim(v_produto_text) LIKE '[%' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
    LOOP
      v_produto_id := NULLIF(v_item->>'produto_id', '')::uuid;
      v_quantidade := (v_item->>'quantidade')::integer;

      -- Fallback: se nao tem produto_id no JSON, tenta buscar por nome
      IF v_produto_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
        SELECT id INTO v_produto_id FROM produtos
        WHERE lower(nome_oficial) = lower(trim(v_item->>'produto'))
        LIMIT 1;
      END IF;

      IF v_produto_id IS NULL OR v_quantidade IS NULL OR v_quantidade <= 0 THEN
        v_errors := v_errors || jsonb_build_object(
          'item', v_item,
          'motivo', 'produto_id ou quantidade invalido'
        );
        CONTINUE;
      END IF;

      -- Buscar produto para validar estoque
      SELECT * INTO v_prod_record FROM produtos WHERE id = v_produto_id;
      IF v_prod_record IS NULL THEN
        v_errors := v_errors || jsonb_build_object('produto_id', v_produto_id::text, 'motivo', 'produto nao existe');
        CONTINUE;
      END IF;

      -- FIFO deduction from lotes
      v_remaining := v_quantidade;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = v_produto_id AND quantidade_atual > 0
        ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
        VALUES (v_produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, p_pedido_id, 'Pedido #' || p_pedido_id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;

      -- Decrementa estoque
      UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;

      v_processed := v_processed + 1;
      v_result := v_result || jsonb_build_object('produto_id', v_produto_id::text, 'quantidade', v_quantidade, 'status', 'ok');
    END LOOP;

  -- CASO 2: produto e string simples (formato do FinanceiroPage)
  ELSIF v_produto_text IS NOT NULL AND trim(v_produto_text) <> '' THEN
    -- Tenta usar produto_id direto da coluna
    v_produto_id := v_pedido.produto_id;
    v_quantidade := v_pedido.quantidade;

    -- Fallback: buscar produto_id por nome
    IF v_produto_id IS NULL THEN
      -- Tenta extrair nome base (remove " xN" do final se existir)
      SELECT id INTO v_produto_id FROM produtos
      WHERE lower(nome_oficial) = lower(trim(v_produto_text))
         OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
      LIMIT 1;
    END IF;

    IF v_produto_id IS NULL THEN
      RETURN jsonb_build_object('error', 'produto nao encontrado', 'nome', v_produto_text, 'pedido_id', p_pedido_id::text);
    END IF;

    IF v_quantidade IS NULL OR v_quantidade <= 0 THEN
      v_quantidade := 1;
    END IF;

    -- Buscar produto para validar estoque
    SELECT * INTO v_prod_record FROM produtos WHERE id = v_produto_id;
    IF v_prod_record IS NULL THEN
      RETURN jsonb_build_object('error', 'produto nao existe', 'produto_id', v_produto_id::text);
    END IF;

    -- FIFO deduction from lotes
    v_remaining := v_quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
      VALUES (v_produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, p_pedido_id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque
    UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;

    v_processed := v_processed + 1;
    v_result := v_result || jsonb_build_object('produto_id', v_produto_id::text, 'quantidade', v_quantidade, 'status', 'ok');
  END IF;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'processed', v_processed,
    'skipped', v_skipped,
    'items', v_result,
    'errors', v_errors
  );
END;
$$;

-- 4. Funcao para reprocessar TODOS pedidos nao processados
CREATE OR REPLACE FUNCTION public.reprocessar_todos_pedidos_estoque()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ped record;
  v_result jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_ok integer := 0;
  v_err integer := 0;
  v_resp jsonb;
BEGIN
  FOR v_ped IN
    SELECT id FROM pedidos
    WHERE produto_id IS NOT NULL OR (produto IS NOT NULL AND trim(produto) <> '')
    ORDER BY created_at ASC
  LOOP
    v_total := v_total + 1;
    v_resp := public.processar_pedido_estoque(v_ped.id);

    IF v_resp ? 'error' THEN
      v_err := v_err + 1;
      v_result := v_result || jsonb_build_object('pedido_id', v_ped.id::text, 'status', 'error', 'detail', v_resp);
    ELSIF (v_resp->>'status') = 'skipped' THEN
      v_result := v_result || jsonb_build_object('pedido_id', v_ped.id::text, 'status', 'skipped');
    ELSE
      v_ok := v_ok + 1;
      v_result := v_result || jsonb_build_object('pedido_id', v_ped.id::text, 'status', 'ok', 'processed', v_resp->'processed');
    END IF;
  END LOOP;

  RETURN jsonb_build_object('total', v_total, 'ok', v_ok, 'errors', v_err, 'details', v_result);
END;
$$;

NOTIFY pgrst, 'reload schema';

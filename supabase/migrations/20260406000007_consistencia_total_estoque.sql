-- CONSISTENCIA TOTAL DE ESTOQUE
-- Adiciona flag anti-duplicacao, sync de estoque, e atualiza trigger

-- ============================================================
-- ETAPA 1: Coluna anti-duplicacao em pedidos
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_pedidos_estoque_processado ON public.pedidos(estoque_processado) WHERE estoque_processado = false;

-- ============================================================
-- ETAPA 2: Recriar processar_pedido_estoque com flag
-- ============================================================
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
  v_processed integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_result jsonb := '[]'::jsonb;
  v_cast_error text;
BEGIN
  -- Buscar dados do pedido
  SELECT * INTO v_pedido FROM pedidos WHERE id = p_pedido_id;

  IF v_pedido IS NULL THEN
    RETURN jsonb_build_object('error', 'pedido nao encontrado', 'pedido_id', p_pedido_id::text);
  END IF;

  -- ANTI-DUPLICACAO: se ja processado, ignora
  IF v_pedido.estoque_processado THEN
    RETURN jsonb_build_object('status', 'skipped', 'motivo', 'pedido ja processado', 'pedido_id', p_pedido_id::text);
  END IF;

  -- Buscar UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = v_pedido.contato_id;

  v_produto_text := v_pedido.produto;

  -- CASO 1: produto e JSON array
  IF v_produto_text IS NOT NULL AND trim(v_produto_text) LIKE '[%' THEN
    BEGIN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
      LOOP
        v_produto_id := NULLIF(v_item->>'produto_id', '')::uuid;
        v_quantidade := (v_item->>'quantidade')::integer;

        IF v_produto_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
          SELECT id INTO v_produto_id FROM produtos
          WHERE lower(nome_oficial) = lower(trim(v_item->>'produto'))
          LIMIT 1;
        END IF;

        IF v_produto_id IS NULL OR v_quantidade IS NULL OR v_quantidade <= 0 THEN
          v_errors := v_errors || jsonb_build_object('item', v_item, 'motivo', 'produto_id ou quantidade invalido');
          CONTINUE;
        END IF;

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

        UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;
        v_processed := v_processed + 1;
        v_result := v_result || jsonb_build_object('produto_id', v_produto_id::text, 'quantidade', v_quantidade, 'status', 'ok');
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_cast_error = MESSAGE_TEXT;
      v_errors := v_errors || jsonb_build_object('motivo', 'JSON invalido: ' || v_cast_error);
    END;

  -- CASO 2: produto e string simples
  ELSIF v_produto_text IS NOT NULL AND trim(v_produto_text) <> '' THEN
    v_produto_id := v_pedido.produto_id;
    v_quantidade := v_pedido.quantidade;

    IF v_produto_id IS NULL THEN
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

    SELECT * INTO v_prod_record FROM produtos WHERE id = v_produto_id;
    IF v_prod_record IS NULL THEN
      RETURN jsonb_build_object('error', 'produto nao existe', 'produto_id', v_produto_id::text);
    END IF;

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

    UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;
    v_processed := v_processed + 1;
    v_result := v_result || jsonb_build_object('produto_id', v_produto_id::text, 'quantidade', v_quantidade, 'status', 'ok');
  END IF;

  -- MARCA como processado (anti-duplicacao)
  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'processed', v_processed,
    'items', v_result,
    'errors', v_errors
  );
END;
$$;

-- ============================================================
-- ETAPA 3: Atualizar trigger para usar flag
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM public.processar_pedido_estoque(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_processar_pedido_estoque();

-- ============================================================
-- ETAPA 4: sync_estoque_total (recalcula estoque a partir de movimentacoes)
-- Uso: admin/debug quando necessario
-- ============================================================
CREATE OR REPLACE FUNCTION public.sync_estoque_total()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_prod record;
  v_entradas integer;
  v_saidas integer;
  v_novo_estoque integer;
  v_synced integer := 0;
BEGIN
  FOR v_prod IN SELECT id, nome_oficial, estoque_atual FROM produtos
  LOOP
    SELECT COALESCE(SUM(quantidade), 0)::integer INTO v_entradas
    FROM estoque_movimentacoes WHERE produto_id = v_prod.id AND tipo = 'entrada';

    SELECT COALESCE(SUM(quantidade), 0)::integer INTO v_saidas
    FROM estoque_movimentacoes WHERE produto_id = v_prod.id AND tipo = 'saida';

    v_novo_estoque := v_entradas - v_saidas;

    IF v_novo_estoque <> v_prod.estoque_atual THEN
      UPDATE produtos SET estoque_atual = v_novo_estoque WHERE id = v_prod.id;
      v_synced := v_synced + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('synced', v_synced, 'message', 'estoque sincronizado com base em movimentacoes');
END;
$$;

-- ============================================================
-- ETAPA 5: Reprocessar pedidos antigos nao processados
-- ============================================================
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM pedidos WHERE estoque_processado = false;
  RAISE NOTICE 'Reprocessando % pedidos nao processados...', v_count;
END $$;

-- Executa reprocessamento automatico
SELECT public.reprocessar_todos_pedidos_estoque();

NOTIFY pgrst, 'reload schema';

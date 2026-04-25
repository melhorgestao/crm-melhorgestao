-- ESTOQUE DEFINITIVO: reprocessa TODOS pedidos + trigger automatico
-- Esta migration deve ser executada UMA VEZ no Supabase SQL Editor

-- ============================================================
-- PASSO 1: Garantir estrutura necessaria
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

-- ============================================================
-- PASSO 2: Drop trigger antigo para recriar limpo
-- ============================================================
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
DROP TRIGGER IF EXISTS trigger_abate_estoque_pedido ON public.pedidos;

-- ============================================================
-- PASSO 3: Funcao de trigger limpa
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_abate_estoque_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_produto_text text;
BEGIN
  -- Pula se ja processado
  IF NEW.estoque_processado = true THEN
    RETURN NEW;
  END IF;

  -- Pula se ja tem movimentacao
  IF EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = NEW.id) THEN
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    RETURN NEW;
  END IF;

  v_produto_text := NEW.produto;
  IF v_produto_text IS NULL OR trim(v_produto_text) = '' THEN
    RETURN NEW;
  END IF;

  -- UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = NEW.contato_id;

  -- CASO JSON
  IF v_produto_text LIKE '[%' THEN
    BEGIN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
      LOOP
        v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
        v_qty := (v_item->>'quantidade')::integer;
        IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
          SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1;
        END IF;
        IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
        SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
        IF v_produto IS NULL THEN CONTINUE; END IF;

        v_remaining := v_qty;
        FOR v_lote_rec IN
          SELECT id, quantidade_atual, uf FROM lotes
          WHERE produto_id = v_prod_id AND quantidade_atual > 0
          ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
        LOOP
          IF v_remaining <= 0 THEN EXIT; END IF;
          v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
          UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
          INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
          VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, NEW.id, 'Pedido #' || NEW.id::text);
          v_remaining := v_remaining - v_deduct;
        END LOOP;
        UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      END LOOP;
      UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  -- CASO STRING
  ELSE
    v_prod_id := NEW.produto_id;
    v_qty := NEW.quantidade;
    IF v_prod_id IS NULL THEN
      SELECT id INTO v_prod_id FROM produtos
      WHERE lower(nome_oficial) = lower(trim(v_produto_text))
         OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
      LIMIT 1;
    END IF;
    IF v_prod_id IS NULL THEN RETURN NEW; END IF;
    IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
    SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
    IF v_produto IS NULL THEN RETURN NEW; END IF;

    v_remaining := v_qty;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
      VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, NEW.id, 'Pedido #' || NEW.id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;
    UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- PASSO 4: Criar trigger
-- ============================================================
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_abate_estoque_pedido();

-- ============================================================
-- PASSO 5: Reprocessar TODOS pedidos existentes
-- ============================================================
DO $$
DECLARE
  v_ped record;
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_produto_text text;
  v_ok integer := 0;
  v_err integer := 0;
BEGIN
  FOR v_ped IN
    SELECT * FROM pedidos
    WHERE (produto IS NOT NULL AND trim(produto) <> '')
      AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    v_produto_text := v_ped.produto;
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct WHERE ct.id = v_ped.contato_id;

    IF v_produto_text LIKE '[%' THEN
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
        LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qty := (v_item->>'quantidade')::integer;
          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
            SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1;
          END IF;
          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
          IF v_produto IS NULL THEN CONTINUE; END IF;

          v_remaining := v_qty;
          FOR v_lote_rec IN
            SELECT id, quantidade_atual, uf FROM lotes
            WHERE produto_id = v_prod_id AND quantidade_atual > 0
            ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
          LOOP
            IF v_remaining <= 0 THEN EXIT; END IF;
            v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
            VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;
          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
        v_ok := v_ok + 1;
      EXCEPTION WHEN OTHERS THEN
        v_err := v_err + 1;
      END;
    ELSE
      v_prod_id := v_ped.produto_id;
      v_qty := v_ped.quantidade;
      IF v_prod_id IS NULL THEN
        SELECT id INTO v_prod_id FROM produtos
        WHERE lower(nome_oficial) = lower(trim(v_produto_text))
           OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
        LIMIT 1;
      END IF;
      IF v_prod_id IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;

      v_remaining := v_qty;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = v_prod_id AND quantidade_atual > 0
        ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
        VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;
      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      v_ok := v_ok + 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'REPROCESSAMENTO: % pedidos processados, % erros', v_ok, v_err;
END $$;

-- ============================================================
-- PASSO 6: Verificar resultado
-- ============================================================
DO $$
DECLARE
  v_total_pedidos integer;
  v_total_movs integer;
  v_total_produtos integer;
BEGIN
  SELECT COUNT(*) INTO v_total_pedidos FROM pedidos;
  SELECT COUNT(*) INTO v_total_movs FROM estoque_movimentacoes WHERE tipo = 'saida';
  SELECT COUNT(*) INTO v_total_produtos FROM produtos;
  RAISE NOTICE '=== RESULTADO FINAL ===';
  RAISE NOTICE 'Total pedidos: %', v_total_pedidos;
  RAISE NOTICE 'Total saidas estoque: %', v_total_movs;
  RAISE NOTICE 'Total produtos: %', v_total_produtos;
END $$;

NOTIFY pgrst, 'reload schema';

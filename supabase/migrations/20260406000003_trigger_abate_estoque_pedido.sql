-- Trigger: abatimento automatico de estoque ao criar pedido
-- Resolve o problema de pedidos criados via insert direto (FinanceiroPage)
-- que nao passavam pelo process_venda e nao abatiam estoque

-- 1. Funcao de abatimento de estoque por pedido
CREATE OR REPLACE FUNCTION public.abate_estoque_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_produto_id uuid;
  v_quantidade integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
BEGIN
  -- So abate se tiver produto_id e quantidade
  IF NEW.produto_id IS NULL OR NEW.quantidade IS NULL OR NEW.quantidade <= 0 THEN
    RETURN NEW;
  END IF;

  v_produto_id := NEW.produto_id;
  v_quantidade := NEW.quantidade;

  -- IDEMPOTENCIA: verifica se ja existe movimentacao para este pedido
  SELECT EXISTS (
    SELECT 1 FROM estoque_movimentacoes WHERE observacao = 'Pedido #' || NEW.id::text
  ) INTO v_mov_exists;

  IF v_mov_exists THEN
    RETURN NEW;
  END IF;

  -- Get client UF for FIFO priority
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = NEW.contato_id;

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
    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
    VALUES (v_produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, 'Pedido #' || NEW.id::text);
    v_remaining := v_remaining - v_deduct;
  END LOOP;

  -- Decrementa estoque do produto
  UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;

  RETURN NEW;
END;
$$;

-- 2. Trigger em pedidos
DROP TRIGGER IF EXISTS trigger_abate_estoque_pedido ON public.pedidos;
CREATE TRIGGER trigger_abate_estoque_pedido
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.abate_estoque_pedido();

-- 3. Reprocessar pedidos existentes sem movimentacao
-- Gera movimentacoes faltantes SEM duplicar as existentes
DO $$
DECLARE
  v_ped record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
BEGIN
  FOR v_ped IN
    SELECT p.* FROM pedidos p
    WHERE p.produto_id IS NOT NULL
      AND p.quantidade IS NOT NULL
      AND p.quantidade > 0
      AND NOT EXISTS (
        SELECT 1 FROM estoque_movimentacoes WHERE observacao = 'Pedido #' || p.id::text
      )
    ORDER BY p.created_at ASC
  LOOP
    -- Get client UF
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct WHERE ct.id = v_ped.contato_id;

    v_remaining := v_ped.quantidade;

    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_ped.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
      VALUES (v_ped.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, 'Pedido #' || v_ped.id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque
    UPDATE produtos SET estoque_atual = estoque_atual - v_ped.quantidade WHERE id = v_ped.produto_id;

    RAISE NOTICE 'Reprocessado pedido %: produto %, quantidade %', v_ped.id, v_ped.produto_id, v_ped.quantidade;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

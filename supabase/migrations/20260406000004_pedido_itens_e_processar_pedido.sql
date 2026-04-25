-- 1. Criar tabela pedido_itens (itens individuais de cada pedido)
CREATE TABLE IF NOT EXISTS public.pedido_itens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id uuid NOT NULL REFERENCES public.pedidos(id),
  produto_id uuid NOT NULL REFERENCES public.produtos(id),
  quantidade integer NOT NULL,
  valor_unit numeric,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Adicionar coluna pedido_item_id em estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_item_id uuid REFERENCES public.pedido_itens(id);

-- 3. Constraint UNIQUE para idempotencia (um item = uma movimentacao)
ALTER TABLE public.estoque_movimentacoes ADD CONSTRAINT estoque_movimentacoes_pedido_item_id_key UNIQUE (pedido_item_id);

-- 4. RPC processar_pedido - abate estoque com idempotencia e validacao
CREATE OR REPLACE FUNCTION public.processar_pedido(p_pedido_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item record;
  v_produto record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_item_id uuid;
  v_total_items integer := 0;
  v_processed_items integer := 0;
  v_skipped_items integer := 0;
  v_result jsonb := '[]'::jsonb;
  v_erro text;
BEGIN
  -- Buscar UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct
  WHERE ct.id = (SELECT contato_id FROM pedidos WHERE id = p_pedido_id);

  -- Loop nos itens do pedido
  FOR v_item IN
    SELECT * FROM pedido_itens WHERE pedido_id = p_pedido_id
  LOOP
    v_total_items := v_total_items + 1;

    -- IDEMPOTENCIA: verifica se ja existe movimentacao para este item
    SELECT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id
    ) INTO v_mov_exists;

    IF v_mov_exists THEN
      v_skipped_items := v_skipped_items + 1;
      v_result := v_result || jsonb_build_object(
        'item_id', v_item.id::text,
        'produto_id', v_item.produto_id::text,
        'status', 'skipped',
        'motivo', 'ja processado'
      );
      CONTINUE;
    END IF;

    -- Buscar produto para validar estoque
    SELECT * INTO v_produto FROM produtos WHERE id = v_item.produto_id;

    IF v_produto IS NULL THEN
      v_result := v_result || jsonb_build_object(
        'item_id', v_item.id::text,
        'produto_id', v_item.produto_id::text,
        'status', 'error',
        'motivo', 'produto nao encontrado'
      );
      CONTINUE;
    END IF;

    -- VALIDACAO: nao permitir estoque negativo
    IF v_produto.estoque_atual - v_item.quantidade < 0 THEN
      v_result := v_result || jsonb_build_object(
        'item_id', v_item.id::text,
        'produto_id', v_item.produto_id::text,
        'status', 'error',
        'motivo', 'estoque insuficiente (atual: ' || v_produto.estoque_atual || ', necessario: ' || v_item.quantidade || ')'
      );
      CONTINUE;
    END IF;

    -- FIFO deduction from lotes
    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque do produto (COMMIT seguro: ja validou que nao fica negativo)
    UPDATE produtos SET estoque_atual = estoque_atual - v_item.quantidade WHERE id = v_item.produto_id;

    v_processed_items := v_processed_items + 1;
    v_result := v_result || jsonb_build_object(
      'item_id', v_item.id::text,
      'produto_id', v_item.produto_id::text,
      'status', 'processed',
      'quantidade', v_item.quantidade
    );
  END LOOP;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'total_items', v_total_items,
    'processed', v_processed_items,
    'skipped', v_skipped_items,
    'items', v_result
  );
END;
$$;

-- 5. Migrar dados existentes: criar pedido_itens a partir de pedidos com produto_id
INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, valor_unit)
SELECT p.id, p.produto_id, p.quantidade, p.preco_unitario
FROM pedidos p
WHERE p.produto_id IS NOT NULL
  AND p.quantidade IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM pedido_itens pi WHERE pi.pedido_id = p.id
  );

-- 6. Reprocessar estoque para pedidos existentes sem movimentacao
DO $$
DECLARE
  v_item record;
  v_produto record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
BEGIN
  FOR v_item IN
    SELECT pi.*, p.contato_id FROM pedido_itens pi
    JOIN pedidos p ON p.id = pi.pedido_id
    WHERE NOT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = pi.id
    )
    ORDER BY pi.created_at ASC
  LOOP
    -- Get client UF
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct WHERE ct.id = v_item.contato_id;

    -- Get product
    SELECT * INTO v_produto FROM produtos WHERE id = v_item.produto_id;
    IF v_produto IS NULL THEN CONTINUE; END IF;

    -- Skip if would go negative
    IF v_produto.estoque_atual - v_item.quantidade < 0 THEN
      RAISE NOTICE 'SKIP item %: estoque insuficiente (atual: %, necessario: %)', v_item.id, v_produto.estoque_atual, v_item.quantidade;
      CONTINUE;
    END IF;

    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, 'Pedido #' || v_item.pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - v_item.quantidade WHERE id = v_item.produto_id;
    RAISE NOTICE 'Reprocessado item %: produto %, quantidade %', v_item.id, v_item.produto_id, v_item.quantidade;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

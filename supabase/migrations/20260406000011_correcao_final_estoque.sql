-- CORRECAO DEFINITIVA DO ESTOQUE
-- 1. process_venda insere estoque_processado=true
-- 2. Trigger ignora pedidos ja processados
-- 3. Reprocessa TODOS pedidos existentes sem movimentacao

-- ============================================================
-- 1. Garantir colunas necessarias
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido_id ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

-- ============================================================
-- 2. Recriar process_venda com estoque_processado=true
-- ============================================================
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text, p_canal text, p_valor numeric, p_contato_id uuid,
  p_produtos jsonb, p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL, p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL, p_obs text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb; prod_id uuid; prod_qty integer; prod_nome text; prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb; total_qty integer := 0;
  remaining integer; lote_rec record; deduct integer; client_uf text;
  v_formato_caixa text; v_peso integer; v_altura integer; v_largura integer; v_comprimento integer;
  has_large_product boolean := false; v_status_kanban text; v_pedido_id uuid;
  v_canal_atual text; v_ultima_venda date; v_last_order_date date;
  v_contato_endereco text; v_contato_numero text; v_data_sp date;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  SELECT canal_origem, ultima_venda_em INTO v_canal_atual, v_ultima_venda FROM contatos WHERE id = p_contato_id;
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero FROM contatos WHERE id = p_contato_id;
  SELECT MAX(created_at)::date INTO v_last_order_date FROM pedidos WHERE contato_id = p_contato_id;
  UPDATE contatos SET ultima_venda_em = COALESCE(v_last_order_date, v_data_sp) WHERE id = p_contato_id;
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

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
    produtos_array := produtos_array || jsonb_build_object('produto', prod_nome, 'produto_id', prod_id, 'quantidade', prod_qty, 'valor_unit', prod_preco);

    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf, 'pv_pending_' || clock_timestamp()::text);
      remaining := remaining - deduct;
    END LOOP;
    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  v_status_kanban := 'Pagou';

  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, obs,
    endereco_entrega, data, estoque_processado)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END,
    v_data_sp, true)
  RETURNING id INTO v_pedido_id;

  UPDATE estoque_movimentacoes SET pedido_id = v_pedido_id, observacao = 'Pedido #' || v_pedido_id::text
  WHERE observacao LIKE 'pv_pending_%' AND pedido_id IS NULL;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- ============================================================
-- 3. Trigger: ignora se estoque_processado=true
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.estoque_processado = true THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = NEW.id) THEN
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    RETURN NEW;
  END IF;
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
-- 4. Reprocessar TODOS pedidos existentes sem movimentacao
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
  v_processed integer := 0;
  v_errors integer := 0;
  v_produto_text text;
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
        v_processed := v_processed + 1;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
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
      IF v_prod_id IS NULL THEN v_errors := v_errors + 1; CONTINUE; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN v_errors := v_errors + 1; CONTINUE; END IF;

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
      v_processed := v_processed + 1;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
    END IF;
  END LOOP;
  RAISE NOTICE 'Reprocessamento concluido: % processados, % erros', v_processed, v_errors;
END $$;

NOTIFY pgrst, 'reload schema';

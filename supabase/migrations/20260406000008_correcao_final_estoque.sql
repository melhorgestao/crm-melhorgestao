-- CORRECAO FINAL: process_venda + trigger sem duplicacao + fix dados existentes

-- ============================================================
-- 1. Atualizar process_venda para setar pedido_id e estoque_processado
-- ============================================================
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL,
  p_obs text DEFAULT NULL
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
  v_canal_atual text;
  v_ultima_venda date;
  v_last_order_date date;
  v_contato_endereco text;
  v_contato_numero text;
  v_data_sp date;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;

  SELECT canal_origem, ultima_venda_em INTO v_canal_atual, v_ultima_venda FROM contatos WHERE id = p_contato_id;
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero 
  FROM contatos WHERE id = p_contato_id;
  SELECT MAX(created_at)::date INTO v_last_order_date 
  FROM pedidos WHERE contato_id = p_contato_id;
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

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

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
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf, 'process_venda_pending');
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  v_status_kanban := 'Pagou';

  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, obs, 
    endereco_entrega, data)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END,
    v_data_sp)
  RETURNING id INTO v_pedido_id;

  -- FIX: atualizar estoque_movimentacoes com pedido_id e mark as processed
  UPDATE estoque_movimentacoes SET pedido_id = v_pedido_id, observacao = 'Pedido #' || v_pedido_id::text
  WHERE observacao = 'process_venda_pending' AND pedido_id IS NULL;

  -- FIX: marcar pedido como processado para o trigger nao duplicar
  UPDATE pedidos SET estoque_processado = true WHERE id = v_pedido_id;

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
-- 2. Atualizar trigger para verificar BOTH pedido_id AND observacao
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_already_processed boolean;
BEGIN
  -- Verifica se ja existe movimentacao para este pedido (por pedido_id ou observacao)
  SELECT EXISTS (
    SELECT 1 FROM estoque_movimentacoes 
    WHERE pedido_id = NEW.id OR observacao = 'Pedido #' || NEW.id::text
  ) INTO v_already_processed;

  IF v_already_processed THEN
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
-- 3. Corrigir dados existentes: vincular movimentacoes aos pedidos
-- ============================================================
-- Para pedidos criados por process_venda que tem produto como JSON
-- As movimentacoes foram criadas mas sem pedido_id
DO $$
DECLARE
  v_ped record;
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_mov_count integer;
  v_fixed integer := 0;
BEGIN
  FOR v_ped IN
    SELECT * FROM pedidos 
    WHERE produto IS NOT NULL 
      AND trim(produto) LIKE '[%'
      AND estoque_processado = false
      AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    -- Conta movimentacoes de saida criadas na mesma epoca do pedido (sem pedido_id)
    SELECT COUNT(*) INTO v_mov_count FROM estoque_movimentacoes
    WHERE pedido_id IS NULL AND tipo = 'saida'
      AND created_at >= v_ped.created_at - interval '1 second'
      AND created_at <= v_ped.created_at + interval '5 seconds';

    IF v_mov_count > 0 THEN
      -- Vincula as movimentacoes ao pedido
      UPDATE estoque_movimentacoes 
      SET pedido_id = v_ped.id, observacao = 'Pedido #' || v_ped.id::text
      WHERE pedido_id IS NULL AND tipo = 'saida'
        AND created_at >= v_ped.created_at - interval '1 second'
        AND created_at <= v_ped.created_at + interval '5 seconds';
      
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      v_fixed := v_fixed + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'Corrigidas % movimentacoes de pedidos process_venda', v_fixed;
END $$;

-- ============================================================
-- 4. Para pedidos SEM movimentacao (criados via insert direto)
--    Processa com a funcao existente
-- ============================================================
DO $$
DECLARE
  v_ped record;
  v_result jsonb;
  v_ok integer := 0;
  v_err integer := 0;
BEGIN
  FOR v_ped IN
    SELECT id FROM pedidos
    WHERE estoque_processado = false
      AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    BEGIN
      v_result := public.processar_pedido_estoque(v_ped.id);
      IF v_result ? 'error' THEN
        v_err := v_err + 1;
      ELSE
        v_ok := v_ok + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_err := v_err + 1;
    END;
  END LOOP;
  RAISE NOTICE 'Reprocessados: % ok, % erros', v_ok, v_err;
END $$;

NOTIFY pgrst, 'reload schema';

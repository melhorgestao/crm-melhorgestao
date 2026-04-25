-- ============================================================
-- Major Update V2 - Fix RPC criar_pedido: entrega_em_maos + estoque
-- ============================================================
-- 1. RPC criar_pedido agora seta entrega_em_maos corretamente
-- 2. Abate estoque admin para entrega_em_maos (lotes sem representante_id)
-- 3. Rep nao pode ter estoque negativo (validacao no frontend PedidosRepPage)

BEGIN;

-- Drop versao anterior
DROP FUNCTION IF EXISTS public.criar_pedido(uuid, text, numeric, text, text, text, text, jsonb, uuid);

CREATE OR REPLACE FUNCTION public.criar_pedido(
  p_contato_id uuid DEFAULT NULL,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido_id uuid;
  v_order_number integer;
  v_data_sp date;
  v_produto_text text;
  v_quantidade integer;
  v_socio text;
  v_canal_lancamento text;
  v_is_entrega_maos boolean;
  v_prod jsonb;
  v_prod_id uuid;
  v_prod_qty integer;
  v_remaining integer;
  v_lote_rec record;
  v_deduct integer;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_is_entrega_maos := (p_modalidade = 'entrega_maos');

  -- Get next order number
  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  -- Determine produto text
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(nome_oficial, ', ') FROM jsonb_to_recordset(p_produtos) AS x(nome_oficial text, quantidade integer));
    v_quantidade := (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x);
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  -- Determine socio
  v_socio := CASE WHEN p_criado_por ILIKE 'v%' OR p_criado_por ILIKE 'v@%' THEN 'V' ELSE 'A' END;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;

  -- Insert pedido
  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem,
    criado_por, produto, quantidade, order_number, data, status_pedido,
    representante_id, tipo_origem, entrega_em_maos, estoque_debitado, estoque_processado
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, p_status_pagamento, p_modalidade, p_uf_postagem,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio',
    p_representante_id,
    CASE WHEN p_representante_id IS NOT NULL THEN 'rep' WHEN p_canal = 'ADS' THEN 'ads' ELSE 'base' END,
    v_is_entrega_maos,
    v_is_entrega_maos,
    v_is_entrega_maos
  ) RETURNING id INTO v_pedido_id;

  -- Insert produtos if provided
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
    SELECT v_pedido_id, (x->>'produto_id')::uuid, COALESCE(x->>'produto', x->>'nome_oficial'), (x->>'quantidade')::integer, (x->>'valor_unit')::numeric
    FROM jsonb_array_elements(p_produtos) AS x;
  END IF;

  -- Se entrega em maos (admin): abate estoque geral (lotes sem representante_id)
  IF v_is_entrega_maos AND p_representante_id IS NULL AND p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      IF v_prod_id IS NULL OR v_prod_qty IS NULL THEN CONTINUE; END IF;

      v_remaining := v_prod_qty;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual FROM public.lotes
        WHERE produto_id = v_prod_id
          AND representante_id IS NULL
          AND quantidade_atual > 0
          AND ativo = true
        ORDER BY data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE public.lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, pedido_id, observacao)
        VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_pedido_id, 'Entrega em maos #' || v_order_number);
        v_remaining := v_remaining - v_deduct;
      END LOOP;

      -- Recalcula estoque do produto
      PERFORM public.update_produto_estoque(v_prod_id);
    END LOOP;
  END IF;

  -- Processar estoque normal (nao entrega em maos) via trigger
  IF NOT v_is_entrega_maos AND p_uf_postagem IS NOT NULL AND p_representante_id IS NULL THEN
    PERFORM public.processar_pedido_estoque_trigger(v_pedido_id, p_uf_postagem);
  END IF;

  -- Cria lancamento se pago
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
    VALUES (v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);
  END IF;

  -- Atualiza contato status
  IF p_contato_id IS NOT NULL THEN
    UPDATE public.contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

COMMIT;

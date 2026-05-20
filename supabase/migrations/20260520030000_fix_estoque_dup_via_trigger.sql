-- ============================================================================
-- Fix: duplicacao de estoque_movimentacoes + double-decrement de lotes
-- Causa: trigger_novo_pedido_estoque (AFTER INSERT em pedidos) ja faz tudo
-- (abate lote + insere mov). Os RPCs criar_pedido_v2 e criar_pedido_free
-- tambem faziam manualmente, resultando em 2x movs por produto e lotes
-- decrementados em dobro para pedidos multi-produto.
--
-- Decisao: trigger e a unica fonte. RPCs nao mexem em estoque_movimentacoes
-- nem em lotes diretamente. Mantem insert em pedido_itens (rastreio).
-- ============================================================================

-- 1. criar_pedido_free: remove manipulacao de estoque
CREATE OR REPLACE FUNCTION public.criar_pedido_free(
  p_contato_id uuid,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido_id uuid; v_contato_id uuid; v_produto_id uuid; v_qtd integer;
  v_order_number integer; v_data_sp date;
  v_uf_postagem_calc text; v_modalidade_calc text;
  v_criado_por_apelido text; v_quantidade_total integer; v_produto_text text;
  v_canal text;
BEGIN
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;
  IF p_contato_id IS NULL THEN RAISE EXCEPTION 'p_contato_id obrigatorio'; END IF;
  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id; END IF;
  SELECT nome INTO v_criado_por_apelido FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1;
  v_criado_por_apelido := COALESCE(NULLIF(v_criado_por_apelido, ''), 'sistema');
  SELECT UPPER(canal_origem) INTO v_canal FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  v_canal := COALESCE(NULLIF(v_canal, ''), 'BASE');
  v_uf_postagem_calc := COALESCE(p_uf_postagem, 'SC');
  v_modalidade_calc := COALESCE(p_modalidade, 'mini');
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    v_quantidade_total := 0;
    FOR v_produto_id, v_qtd IN SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1) FROM jsonb_array_elements(p_produtos) AS item LOOP
      v_quantidade_total := v_quantidade_total + COALESCE(v_qtd, 1);
    END LOOP;
    IF jsonb_array_length(p_produtos) = 1 THEN v_produto_text := (p_produtos->0->>'produto');
    ELSE v_produto_text := p_produtos::text; END IF;
  ELSE
    v_quantidade_total := 1; v_produto_text := '';
  END IF;
  INSERT INTO public.pedidos (contato_id, valor, canal, status_pagamento, modalidade, uf_postagem, status_pedido, obs, observacao, criado_por, order_number, data, data_pago, estoque_processado, created_at, produto, quantidade, is_free)
  VALUES (p_contato_id, 0, v_canal, 'pago', v_modalidade_calc, v_uf_postagem_calc, 'aguardando_rastreio', COALESCE(p_obs, '')::text, COALESCE(p_obs, '')::text, v_criado_por_apelido, v_order_number, v_data_sp, v_data_sp, false, now(), COALESCE(v_produto_text, ''), v_quantidade_total, true)
  RETURNING id INTO v_pedido_id;
  -- pedido_itens (rastreio); trigger trata mov+lote
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_produto_id, v_qtd IN SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1) FROM jsonb_array_elements(p_produtos) AS item LOOP
      INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco) VALUES (v_pedido_id, v_produto_id, COALESCE(v_qtd, 1), 0);
    END LOOP;
  END IF;
  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number, 'is_free', true);
EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Erro ao criar pedido free: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_free TO anon, authenticated, service_role;

-- 2. criar_pedido_v2: remove manipulacao de estoque
CREATE OR REPLACE FUNCTION public.criar_pedido_v2(
  p_contato_id uuid, p_canal text DEFAULT 'ADS', p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago', p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL, p_criado_por text DEFAULT 'V',
  p_obs text DEFAULT NULL, p_produtos jsonb DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido_id uuid; v_contato_id uuid; v_produto_id uuid; v_qtd integer;
  v_order_number integer; v_data_sp date;
  v_uf_postagem_calc text; v_uf_cliente text; v_modalidade_calc text;
  v_socio text; v_criado_por_apelido text;
  v_canal_lancamento text; v_quantidade_total integer; v_produto_text text;
  v_snapshot_v numeric; v_snapshot_a numeric;
  v_data_pago date;
BEGIN
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;
  IF p_contato_id IS NULL THEN RAISE EXCEPTION 'p_contato_id e obrigatorio'; END IF;
  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id; END IF;
  IF UPPER(LEFT(COALESCE(p_criado_por, ''), 1)) = 'A' THEN v_socio := 'A'; ELSE v_socio := 'V'; END IF;
  SELECT nome INTO v_criado_por_apelido FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1;
  v_criado_por_apelido := COALESCE(NULLIF(v_criado_por_apelido, ''), v_socio);
  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS'; END IF;
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM((item->>'quantidade')::integer), 1)::int INTO v_quantidade_total FROM jsonb_array_elements(p_produtos) AS item;
  ELSE v_quantidade_total := 1; END IF;
  BEGIN SELECT cidade_uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL; END;
  IF p_uf_postagem IS NOT NULL AND LENGTH(p_uf_postagem) = 2 THEN v_uf_postagem_calc := p_uf_postagem;
  ELSE v_uf_postagem_calc := COALESCE(v_uf_cliente, 'SC'); END IF;
  v_modalidade_calc := COALESCE(p_modalidade, 'mini');
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    v_quantidade_total := 0;
    FOR v_produto_id, v_qtd IN SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1) FROM jsonb_array_elements(p_produtos) AS item LOOP
      v_quantidade_total := v_quantidade_total + COALESCE(v_qtd, 1);
    END LOOP;
    IF jsonb_array_length(p_produtos) = 1 THEN v_produto_text := (p_produtos->0->>'produto');
    ELSE v_produto_text := p_produtos::text; END IF;
  ELSE v_quantidade_total := 1; v_produto_text := ''; END IF;
  v_data_pago := CASE WHEN p_status_pagamento = 'pago' THEN v_data_sp ELSE NULL END;
  INSERT INTO public.pedidos (contato_id, valor, canal, status_pagamento, modalidade, uf_postagem, status_pedido, obs, observacao, criado_por, order_number, data, data_pago, estoque_processado, created_at, produto, quantidade)
  VALUES (p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc, 'aguardando_rastreio', COALESCE(p_obs, '')::text, COALESCE(p_obs, '')::text, v_criado_por_apelido, v_order_number, v_data_sp, v_data_pago, false, now(), COALESCE(v_produto_text, ''), v_quantidade_total)
  RETURNING id INTO v_pedido_id;
  -- pedido_itens (rastreio); trigger trata mov+lote
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_produto_id, v_qtd IN SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1) FROM jsonb_array_elements(p_produtos) AS item LOOP
      INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco) VALUES (v_pedido_id, v_produto_id, COALESCE(v_qtd, 1), 0);
    END LOOP;
  END IF;
  IF p_status_pagamento = 'pago' THEN
    SELECT COALESCE(SUM(CASE WHEN socio = 'V' THEN valor ELSE 0 END), 0), COALESCE(SUM(CASE WHEN socio = 'A' THEN valor ELSE 0 END), 0)
    INTO v_snapshot_v, v_snapshot_a FROM public.lancamentos_socios;
    INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao, snapshot_saldo_v, snapshot_saldo_a)
    VALUES (v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento, v_criado_por_apelido, v_pedido_id, v_data_sp, 'Venda #' || v_order_number::text, v_snapshot_v, v_snapshot_a);
  END IF;
  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);
EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_v2 TO anon, authenticated, service_role;

-- ============================================================
-- Fix: BASE repeat buyers re-enter 'Clientes' column for LTV flow
-- ============================================================
-- Quando um contato BASE paga novamente, ele volta para 'Clientes'
-- para reentrar no fluxo de LTV. ADS/REP continuam indo para 'Pagou'.

CREATE OR REPLACE FUNCTION public.process_venda(
  p_contato_id uuid,
  p_canal text,
  p_valor numeric,
  p_socio text DEFAULT 'V',
  p_criado_por text DEFAULT 'V',
  p_produtos jsonb DEFAULT NULL,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_obs text DEFAULT NULL
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
  v_canal_lancamento text;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;

  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(nome_oficial, ', ') FROM jsonb_to_recordset(p_produtos) AS x(nome_oficial text, quantidade integer));
    v_quantidade := (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x);
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem,
    criado_por, produto, quantidade, order_number, data, status_pedido, observacao
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, 'pago', p_modalidade, p_uf_postagem,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio', p_obs
  ) RETURNING id INTO v_pedido_id;

  -- BASE repeat buyers go back to 'Clientes' for LTV flow
  -- ADS/REP go to 'Pagou' as usual
  UPDATE public.contatos 
  SET status_kanban = CASE WHEN p_canal = 'BASE' THEN 'Clientes' ELSE 'Pagou' END,
      canal_atual = COALESCE(canal_atual, p_canal),
      updated_at = now()
  WHERE id = p_contato_id;

  INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
  VALUES (p_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

-- Also fix criar_pedido RPC for consistency
CREATE OR REPLACE FUNCTION public.criar_pedido(
  p_contato_id uuid DEFAULT NULL,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
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
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(nome_oficial, ', ') FROM jsonb_to_recordset(p_produtos) AS x(nome_oficial text, quantidade integer));
    v_quantidade := (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x);
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  v_socio := CASE WHEN p_criado_por ILIKE 'v%' OR p_criado_por ILIKE 'v@%' THEN 'V' ELSE 'A' END;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;

  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem,
    criado_por, produto, quantidade, order_number, data, status_pedido,
    representante_id, tipo_origem, entrega_em_maos
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, p_status_pagamento, p_modalidade, p_uf_postagem,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio',
    p_representante_id,
    CASE WHEN p_representante_id IS NOT NULL THEN 'rep' WHEN p_canal = 'ADS' THEN 'ads' ELSE 'base' END,
    false
  ) RETURNING id INTO v_pedido_id;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
    SELECT v_pedido_id, (x->>'produto_id')::uuid, COALESCE(x->>'produto', x->>'nome_oficial'), (x->>'quantidade')::integer, (x->>'valor_unit')::numeric
    FROM jsonb_array_elements(p_produtos) AS x;
  END IF;

  -- BASE repeat buyers -> Clientes | Others -> Pagou
  IF p_contato_id IS NOT NULL THEN
    UPDATE public.contatos 
    SET status_kanban = CASE WHEN p_canal = 'BASE' THEN 'Clientes' ELSE 'Pagou' END,
        canal_atual = COALESCE(canal_atual, p_canal),
        updated_at = now()
    WHERE id = p_contato_id;
  END IF;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
    VALUES (v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

CREATE OR REPLACE FUNCTION public.criar_pedido_v2(p_contato_id uuid, p_canal text DEFAULT 'ADS'::text, p_valor numeric DEFAULT 0, p_status_pagamento text DEFAULT 'pago'::text, p_modalidade text DEFAULT 'mini'::text, p_uf_postagem text DEFAULT NULL::text, p_criado_por text DEFAULT 'V'::text, p_obs text DEFAULT NULL::text, p_produtos jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_pedido_id uuid;
  v_contato_id uuid;
  v_produto_id uuid;
  v_qtd integer;
  v_order_number integer;
  v_data_sp date;
  v_uf_postagem_calc text;
  v_uf_cliente text;
  v_modalidade_calc text;
  v_socio text;          -- valor do constraint: V, A ou P
  v_criado_por text;     -- apelido original (ver/a) para auditoria
  v_canal_lancamento text;
  v_quantidade_total integer;
  v_produto_text text;
BEGIN
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_contato_id IS NULL THEN
    RAISE EXCEPTION 'p_contato_id e obrigatorio';
  END IF;
  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN
    RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id;
  END IF;

  -- Mapeia apelido -> letra do socio (constraint exige V/A/P)
  v_criado_por := COALESCE(NULLIF(LOWER(TRIM(p_criado_por)), ''), 'v');
  IF p_status_pagamento = 'pendente' THEN
    v_socio := 'P';
  ELSIF v_criado_por IN ('v', 'ver') THEN
    v_socio := 'V';
  ELSIF v_criado_por IN ('a') THEN
    v_socio := 'A';
  ELSE
    -- fallback: pega primeira letra em maiusculo
    v_socio := UPPER(LEFT(v_criado_por, 1));
    IF v_socio NOT IN ('V', 'A', 'P') THEN
      v_socio := 'V';
    END IF;
  END IF;

  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS';
  END IF;

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM((item->>'quantidade')::integer), 1)::int INTO v_quantidade_total
    FROM jsonb_array_elements(p_produtos) AS item;
  ELSE
    v_quantidade_total := 1;
  END IF;

  BEGIN
    SELECT cidade_uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  IF p_uf_postagem IS NOT NULL AND LENGTH(p_uf_postagem) = 2 THEN
    v_uf_postagem_calc := p_uf_postagem;
  ELSE
    v_uf_postagem_calc := COALESCE(v_uf_cliente, 'SC');
  END IF;
  v_modalidade_calc := COALESCE(p_modalidade, 'mini');

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    v_quantidade_total := 0;
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      v_quantidade_total := v_quantidade_total + COALESCE(v_qtd, 1);
    END LOOP;

    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := (p_produtos->0->>'produto');
    ELSE
      v_produto_text := p_produtos::text;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
  END IF;

  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, obs, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, v_criado_por, v_order_number, v_data_sp,
    false, now(),
    COALESCE(v_produto_text, ''), v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  IF p_status_pagamento IN ('pago', 'pendente') THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento,
      v_criado_por, v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$function$;
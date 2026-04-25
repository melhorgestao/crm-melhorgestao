CREATE OR REPLACE FUNCTION public.criar_pedido_v2(
  p_contato_id uuid,
  p_canal text DEFAULT 'ADS'::text,
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago'::text,
  p_modalidade text DEFAULT 'mini'::text,
  p_uf_postagem text DEFAULT NULL::text,
  p_criado_por text DEFAULT 'V'::text,
  p_obs text DEFAULT NULL::text,
  p_produtos jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_pedido_id uuid;
  v_contato_id uuid;
  v_order_number integer;
  v_data_sp date;
  v_uf_postagem_calc text;
  v_uf_cliente text;
  v_modalidade_calc text;
  v_socio text;
  v_criado_por text;
  v_canal_lancamento text;
  v_quantidade_total integer;
  v_produto_text text;
  v_item jsonb;
  v_item_produto_id uuid;
  v_item_qtd integer;
  v_item_nome text;
  v_first_produto_id uuid;
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
    v_socio := UPPER(LEFT(v_criado_por, 1));
    IF v_socio NOT IN ('V', 'A', 'P') THEN
      v_socio := 'V';
    END IF;
  END IF;

  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS';
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

  -- Calcula quantidade total e texto do produto
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM(COALESCE((item->>'quantidade')::integer, 1)), 1)::int
    INTO v_quantidade_total
    FROM jsonb_array_elements(p_produtos) AS item;

    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := COALESCE(p_produtos->0->>'produto', p_produtos->0->>'nome_oficial', '');
      v_first_produto_id := NULLIF(p_produtos->0->>'produto_id', '')::uuid;
    ELSE
      v_produto_text := p_produtos::text;
      v_first_produto_id := NULL;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
    v_first_produto_id := NULL;
  END IF;

  -- Insert pedido
  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, obs, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, produto_id, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, v_criado_por, v_order_number, v_data_sp,
    true, now(),
    COALESCE(v_produto_text, ''), v_first_produto_id, v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  -- Cria itens e movimentações de saída
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_item_produto_id := NULLIF(v_item->>'produto_id', '')::uuid;
      v_item_qtd := COALESCE((v_item->>'quantidade')::integer, 1);
      v_item_nome := COALESCE(v_item->>'produto', v_item->>'nome_oficial', '');

      -- Se não tiver produto_id, tenta resolver por nome
      IF v_item_produto_id IS NULL AND v_item_nome <> '' THEN
        SELECT id INTO v_item_produto_id
        FROM public.produtos
        WHERE LOWER(nome_oficial) = LOWER(TRIM(v_item_nome))
           OR LOWER(tag) = LOWER(TRIM(v_item_nome))
        LIMIT 1;
      END IF;

      IF v_item_produto_id IS NOT NULL THEN
        -- Pedido item
        INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
        VALUES (
          v_pedido_id, v_item_produto_id, v_item_nome, v_item_qtd,
          NULLIF(v_item->>'preco', '')::numeric
        );

        -- Movimentação de saída
        INSERT INTO public.estoque_movimentacoes (
          produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, data
        )
        VALUES (
          v_item_produto_id, v_item_qtd, 'saida', 'Venda', v_uf_postagem_calc,
          v_pedido_id,
          'Pedido #' || v_order_number::text || ' - ' || v_item_nome,
          v_data_sp
        );
      END IF;
    END LOOP;
  END IF;

  -- Lancamento socio
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

-- Backfill: corrigir pedido #21 (e quaisquer outros sem movimentação)
DO $backfill$
DECLARE
  v_ped record;
  v_item jsonb;
  v_pid uuid;
  v_qty integer;
  v_nome text;
BEGIN
  FOR v_ped IN
    SELECT p.id, p.order_number, p.produto, p.produto_id, p.quantidade, p.uf_postagem, p.data
    FROM public.pedidos p
    WHERE p.status_pedido != 'cancelado'
      AND p.data >= '2026-04-01'
      AND NOT EXISTS (
        SELECT 1 FROM public.estoque_movimentacoes em
        WHERE em.pedido_id = p.id AND em.tipo = 'saida'
      )
  LOOP
    IF v_ped.produto IS NOT NULL AND v_ped.produto LIKE '[%' THEN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_ped.produto::jsonb)
      LOOP
        v_pid := NULLIF(v_item->>'produto_id', '')::uuid;
        v_qty := COALESCE((v_item->>'quantidade')::integer, 1);
        v_nome := COALESCE(v_item->>'produto', '');
        IF v_pid IS NULL AND v_nome <> '' THEN
          SELECT id INTO v_pid FROM public.produtos
          WHERE LOWER(nome_oficial)=LOWER(TRIM(v_nome)) OR LOWER(tag)=LOWER(TRIM(v_nome)) LIMIT 1;
        END IF;
        IF v_pid IS NOT NULL THEN
          INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, data)
          VALUES (v_pid, v_qty, 'saida', 'Venda', COALESCE(v_ped.uf_postagem,'SP'), v_ped.id,
                  'Backfill Pedido #' || v_ped.order_number || ' - ' || v_nome, v_ped.data);
        END IF;
      END LOOP;
    ELSE
      v_pid := v_ped.produto_id;
      v_nome := COALESCE(v_ped.produto, '');
      IF v_pid IS NULL AND v_nome <> '' THEN
        SELECT id INTO v_pid FROM public.produtos
        WHERE LOWER(nome_oficial)=LOWER(TRIM(v_nome)) OR LOWER(tag)=LOWER(TRIM(v_nome)) LIMIT 1;
      END IF;
      IF v_pid IS NOT NULL THEN
        UPDATE public.pedidos SET produto_id = v_pid WHERE id = v_ped.id AND produto_id IS NULL;
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, data)
        VALUES (v_pid, COALESCE(v_ped.quantidade,1), 'saida', 'Venda', COALESCE(v_ped.uf_postagem,'SP'), v_ped.id,
                'Backfill Pedido #' || v_ped.order_number || ' - ' || v_nome, v_ped.data);
      END IF;
    END IF;
    UPDATE public.pedidos SET estoque_processado = true WHERE id = v_ped.id;
  END LOOP;
END;
$backfill$;

-- Atualiza snapshot
SELECT public.atualizar_estoque_snapshot();
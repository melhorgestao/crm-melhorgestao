-- REFACTOR process_venda - SYNC WITH INVENTORY SOURCE OF TRUTH
-- Remove chamadas manuais para triggers de estoque redundantes.

BEGIN;

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
  v_is_base boolean;
  v_next_midnight timestamptz;
  v_uf_cliente text;
  v_item jsonb;
BEGIN
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;
  v_next_midnight := (CURRENT_DATE + 1)::timestamptz;
  v_is_base := (p_canal = 'BASE');

  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  -- UF do cliente para registro
  SELECT uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;

  -- Parsing de produtos
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(nome_oficial, ', ') FROM jsonb_to_recordset(p_produtos) AS x(nome_oficial text, quantidade integer));
    v_quantidade := (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x);
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem, uf_cliente,
    criado_por, produto, quantidade, order_number, data, status_pedido, observacao,
    is_novo, novo_ate, estoque_processado, created_at
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, 'pago', p_modalidade, p_uf_postagem, v_uf_cliente,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio', p_obs,
    v_is_base, CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
    true, now() -- Já considerado processado pois o saldo é dinâmico
  ) RETURNING id INTO v_pedido_id;

  -- Registro de Itens e Movimentação Histórica
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_item IN SELECT jsonb_array_elements(p_produtos) LOOP
        -- Movimentação
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
        VALUES ((v_item->>'produto_id')::uuid, (v_item->>'quantidade')::int, 'saida', 'Venda', COALESCE(p_uf_postagem, v_uf_cliente, 'SP'), v_pedido_id, 'Venda automática process_venda');
        
        -- Item
        INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
        VALUES (v_pedido_id, (v_item->>'produto_id')::uuid, COALESCE(v_item->>'produto', v_item->>'nome_oficial'), (v_item->>'quantidade')::integer, (v_item->>'valor_unit')::numeric);
    END LOOP;
  END IF;

  -- Logística/Financeiro normal
  UPDATE public.contatos 
  SET status_kanban = CASE WHEN v_is_base THEN 'Clientes' ELSE 'Pagou' END,
      canal_atual = CASE WHEN v_is_base THEN 'BASE' ELSE COALESCE(canal_atual, p_canal) END,
      is_novo = v_is_base,
      novo_ate = CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
      updated_at = now()
  WHERE id = p_contato_id;

  INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
  VALUES (p_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);

  -- REMOVIDO: PERFORM public.processar_pedido_estoque_trigger(...) - Evita duplicidade
  
  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

COMMIT;

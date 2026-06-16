-- ============================================================================
-- Fase 3 — Fechamento de pedido com caixa destino + parcelamento 50/50
--
-- 1) fechar_pedido_pago ganha p_caixa_id: registra recebimento em
--    lancamentos_socios.socio = '<codigo da caixa>' em vez de derivar
--    de contato.canal_origem.
-- 2) criar_pedido_em_aberto ganha campos p_is_parcelado, p_primeira_parcela.
-- 3) Nova RPC iniciar_fechamento_contato: substitui o uso temporário de
--    escalar_suporte('intent_fechamento') no AGENT_START. Marca contato
--    como 'em_fechamento' e o router roteia automaticamente pra closing.
-- 4) Nova RPC gerar_pix_saldo_devedor: cobra exatamente o saldo pendente
--    do contato (sem criar pedido novo). Returns pedido_em_aberto_id
--    com flag is_cobranca_saldo=true e descrição apropriada.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) pedido_em_aberto: novas colunas pra parcelamento e cobrança de saldo
-- ----------------------------------------------------------------------------
ALTER TABLE public.pedido_em_aberto
  ADD COLUMN IF NOT EXISTS is_parcelado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS valor_primeira_parcela numeric,
  ADD COLUMN IF NOT EXISTS is_cobranca_saldo boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS caixa_id text;  -- C1..C5

COMMENT ON COLUMN public.pedido_em_aberto.is_parcelado IS
  'true se cliente optou por parcelar 50/50 (a partir de 4 produtos).';
COMMENT ON COLUMN public.pedido_em_aberto.valor_primeira_parcela IS
  'Valor da entrada (50% do total) quando parcelado. NULL se à vista.';
COMMENT ON COLUMN public.pedido_em_aberto.is_cobranca_saldo IS
  'true se este rascunho NÃO é um pedido novo — é cobrança de saldo devedor.';
COMMENT ON COLUMN public.pedido_em_aberto.caixa_id IS
  'Código da caixa que recebe o Pix (ex: C1 DeFlow). Lido da config se NULL.';

-- ----------------------------------------------------------------------------
-- 2) RPC criar_pedido_em_aberto v2 — aceita is_parcelado/valor primeira parcela
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.criar_pedido_em_aberto(
  p_contato_id        uuid,
  p_instancia_id      uuid,
  p_itens             jsonb,
  p_brindes           jsonb,
  p_modalidade_frete  text,
  p_frete_preco       numeric,
  p_frete_prazo_min   integer,
  p_frete_prazo_max   integer,
  p_frete_gratis      boolean,
  p_endereco_snapshot jsonb,
  p_subtotal          numeric,
  p_total             numeric,
  p_resumo_formatado  text,
  p_is_parcelado      boolean DEFAULT false,
  p_caixa_id          text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
  v_caixa text;
  v_primeira_parcela numeric;
BEGIN
  -- Cancela rascunho anterior se houver
  UPDATE public.pedido_em_aberto
     SET status = 'cancelado', updated_at = now()
   WHERE contato_id = p_contato_id
     AND status = 'aguardando_pagamento';

  -- Resolve caixa default
  IF p_caixa_id IS NULL THEN
    SELECT valor INTO v_caixa FROM public.configuracoes WHERE chave = 'caixa_default_bot';
    v_caixa := COALESCE(v_caixa, 'C1');
  ELSE
    v_caixa := p_caixa_id;
  END IF;

  v_primeira_parcela := CASE
    WHEN p_is_parcelado THEN ROUND(p_total / 2, 2)
    ELSE NULL
  END;

  INSERT INTO public.pedido_em_aberto (
    contato_id, instancia_id, itens, brindes, modalidade_frete,
    frete_preco, frete_prazo_min, frete_prazo_max, frete_gratis,
    endereco_snapshot, subtotal, total, resumo_formatado,
    is_parcelado, valor_primeira_parcela, caixa_id
  ) VALUES (
    p_contato_id, p_instancia_id, p_itens, p_brindes, p_modalidade_frete,
    p_frete_preco, p_frete_prazo_min, p_frete_prazo_max, p_frete_gratis,
    p_endereco_snapshot, p_subtotal, p_total, p_resumo_formatado,
    p_is_parcelado, v_primeira_parcela, v_caixa
  ) RETURNING id INTO v_id;

  UPDATE public.contatos
     SET ultima_interacao = 'aguardando_pagamento',
         data_aguardando_pagamento = now(),
         updated_at = now()
   WHERE id = p_contato_id;

  RETURN jsonb_build_object(
    'ok', true,
    'pedido_em_aberto_id', v_id,
    'is_parcelado', p_is_parcelado,
    'valor_a_pagar_pix', COALESCE(v_primeira_parcela, p_total),
    'valor_total', p_total,
    'caixa_id', v_caixa
  );
END $$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_em_aberto(uuid,uuid,jsonb,jsonb,text,numeric,integer,integer,boolean,jsonb,numeric,numeric,text,boolean,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 3) fechar_pedido_pago v2 — registra recebimento na caixa configurada
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fechar_pedido_pago(
  p_pedido_em_aberto_id uuid,
  p_pix_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rascunho public.pedido_em_aberto%ROWTYPE;
  v_pedido_id uuid;
  v_qtd integer;
  v_canal text;
  v_caixa text;
  v_status_pgto text;
  v_valor_pago numeric;
  v_saldo_devedor numeric;
BEGIN
  SELECT * INTO v_rascunho FROM public.pedido_em_aberto WHERE id = p_pedido_em_aberto_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_em_aberto não encontrado');
  END IF;

  IF v_rascunho.status = 'pago' THEN
    RETURN jsonb_build_object('ok', true, 'idempotente', true, 'pedido_id', v_rascunho.pedido_id);
  END IF;

  SELECT COALESCE(SUM((value->>'qtd')::int), 0)
    INTO v_qtd
    FROM jsonb_array_elements(v_rascunho.itens);

  SELECT canal_origem INTO v_canal FROM public.contatos WHERE id = v_rascunho.contato_id;
  v_canal := COALESCE(v_canal, 'BASE');
  IF v_canal NOT IN ('ADS','BASE','REP') THEN v_canal := 'BASE'; END IF;

  -- Define caixa destino (default DeFlow C1 ou o que veio do rascunho)
  v_caixa := COALESCE(v_rascunho.caixa_id, 'C1');

  -- Valor que efetivamente entrou neste Pix
  v_valor_pago := COALESCE(v_rascunho.valor_primeira_parcela, v_rascunho.total);

  -- Define status do pedido baseado em parcelamento
  IF v_rascunho.is_parcelado THEN
    v_status_pgto := 'pendente';
    v_saldo_devedor := v_rascunho.total - v_valor_pago;
  ELSE
    v_status_pgto := 'pago';
    v_saldo_devedor := 0;
  END IF;

  -- INSERT pedidos
  INSERT INTO public.pedidos (
    contato_id, produto, quantidade, valor, valor_original, canal,
    endereco_entrega, status_pedido, status_pagamento, data
  ) VALUES (
    v_rascunho.contato_id,
    (SELECT string_agg((it->>'emoji') || ' ' || (it->>'nome_oficial') || ' (' || (it->>'qtd') || 'x)', ' | ')
       FROM jsonb_array_elements(v_rascunho.itens) it),
    v_qtd,
    v_saldo_devedor,  -- saldo devedor (0 se à vista, restante se parcelado)
    v_rascunho.total, -- valor original
    v_canal,
    v_rascunho.endereco_snapshot::text,
    'aguardando_rastreio',
    v_status_pgto,
    CURRENT_DATE
  ) RETURNING id INTO v_pedido_id;

  -- Registra recebimento na CAIXA (VENDA se à vista; PARCELA_VENDA se parcelado)
  INSERT INTO public.lancamentos_socios (
    socio, tipo, valor, canal, contato_id, quantidade, modalidade,
    status_pagamento, criado_por, pedido_id, descricao
  ) VALUES (
    v_caixa,
    CASE WHEN v_rascunho.is_parcelado THEN 'PARCELA_VENDA' ELSE 'VENDA' END,
    v_valor_pago,
    v_canal,
    v_rascunho.contato_id,
    v_qtd,
    v_rascunho.modalidade_frete,
    'pago',
    'AGENT_CLOSING',
    v_pedido_id,
    CASE WHEN v_rascunho.is_parcelado
         THEN 'Parcela 1/2 (entrada) — pedido #' || v_pedido_id::text
         ELSE 'Venda à vista — pedido #' || v_pedido_id::text END
  );

  -- Se parcelado, registra linha pendente da 2ª parcela na coluna P
  IF v_rascunho.is_parcelado THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      status_pagamento, criado_por, pedido_id, descricao
    ) VALUES (
      'P', 'VENDA', v_saldo_devedor, v_canal, v_rascunho.contato_id,
      v_qtd, v_rascunho.modalidade_frete, 'pendente',
      'AGENT_CLOSING', v_pedido_id,
      'Saldo devedor (parcela 2/2) — pedido #' || v_pedido_id::text
    );
  END IF;

  -- Promove rascunho pra status final
  UPDATE public.pedido_em_aberto
     SET status = 'pago', pago_em = now(),
         pix_id = COALESCE(p_pix_id, pix_id),
         pedido_id = v_pedido_id,
         updated_at = now()
   WHERE id = p_pedido_em_aberto_id;

  -- Atualiza contato: cliente (à vista) OU cliente_pendente (parcelado)
  UPDATE public.contatos
     SET ultima_interacao = CASE WHEN v_rascunho.is_parcelado
                                 THEN 'cliente_pendente'
                                 ELSE 'cliente' END,
         ja_comprou = true,
         data_cliente = COALESCE(data_cliente, now()),
         data_cliente_pendente = CASE WHEN v_rascunho.is_parcelado
                                      THEN COALESCE(data_cliente_pendente, now())
                                      ELSE NULL END,
         data_em_fechamento = NULL,
         data_aguardando_pagamento = NULL,
         data_wait_follow_up = NULL,
         follow_up_tentativas = 0,
         updated_at = now()
   WHERE id = v_rascunho.contato_id;

  RETURN jsonb_build_object(
    'ok', true,
    'pedido_id', v_pedido_id,
    'valor_pago', v_valor_pago,
    'is_parcelado', v_rascunho.is_parcelado,
    'saldo_devedor', v_saldo_devedor,
    'caixa', v_caixa
  );
END $$;

GRANT EXECUTE ON FUNCTION public.fechar_pedido_pago(uuid, text) TO service_role;

-- ----------------------------------------------------------------------------
-- 4) RPC iniciar_fechamento_contato — substitui escalar_suporte('intent_fechamento')
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.iniciar_fechamento_contato(
  p_contato_id uuid,
  p_produto_pretendido text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_estado_atual text;
BEGIN
  SELECT ultima_interacao INTO v_estado_atual
    FROM public.contatos WHERE id = p_contato_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  -- Não muda estado se já está em fluxo de fechamento
  IF v_estado_atual IN ('em_fechamento','aguardando_pagamento') THEN
    RETURN jsonb_build_object('ok', true, 'idempotente', true,
                              'estado_atual', v_estado_atual);
  END IF;

  UPDATE public.contatos
     SET ultima_interacao = 'em_fechamento',
         data_em_fechamento = now(),
         updated_at = now()
   WHERE id = p_contato_id;

  -- log
  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'intent_fechamento', v_estado_atual, 'em_fechamento',
            jsonb_build_object('produto_pretendido', p_produto_pretendido));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'estado_para', 'em_fechamento');
END $$;

GRANT EXECUTE ON FUNCTION public.iniciar_fechamento_contato(uuid, text) TO service_role;

-- ----------------------------------------------------------------------------
-- 5) RPC criar_cobranca_saldo_devedor — gera pedido_em_aberto pra saldo devedor
--    Usada pela tool gerar_pix_saldo_devedor: NÃO cria pedido novo, apenas
--    rascunho de cobrança que o webhook DeFlow vai converter em PARCELA_VENDA.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.criar_cobranca_saldo_devedor(
  p_contato_id   uuid,
  p_instancia_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_saldo numeric := 0;
  v_pedido_pendente_id uuid;
  v_caixa text;
  v_id uuid;
BEGIN
  -- Pega o saldo devedor total + o pedido pendente mais antigo (target)
  SELECT COALESCE(SUM(valor), 0)
    INTO v_saldo
    FROM public.pedidos
   WHERE contato_id = p_contato_id
     AND status_pagamento = 'pendente'
     AND status_pedido != 'cancelado';

  IF v_saldo <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não tem saldo devedor');
  END IF;

  SELECT id INTO v_pedido_pendente_id
    FROM public.pedidos
   WHERE contato_id = p_contato_id
     AND status_pagamento = 'pendente'
     AND status_pedido != 'cancelado'
   ORDER BY data ASC LIMIT 1;

  -- Caixa default
  SELECT valor INTO v_caixa FROM public.configuracoes WHERE chave = 'caixa_default_bot';
  v_caixa := COALESCE(v_caixa, 'C1');

  -- Cancela rascunho anterior
  UPDATE public.pedido_em_aberto
     SET status = 'cancelado', updated_at = now()
   WHERE contato_id = p_contato_id AND status = 'aguardando_pagamento';

  INSERT INTO public.pedido_em_aberto (
    contato_id, instancia_id, itens, brindes, modalidade_frete,
    frete_preco, frete_gratis, endereco_snapshot,
    subtotal, total, resumo_formatado,
    is_cobranca_saldo, caixa_id
  ) VALUES (
    p_contato_id, p_instancia_id,
    '[]'::jsonb, '[]'::jsonb, NULL,
    0, true, '{}'::jsonb,
    v_saldo, v_saldo,
    'Cobrança de saldo devedor — R$ ' || v_saldo::text,
    true, v_caixa
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true,
                            'pedido_em_aberto_id', v_id,
                            'valor', v_saldo,
                            'pedido_pendente_id', v_pedido_pendente_id,
                            'caixa_id', v_caixa);
END $$;

GRANT EXECUTE ON FUNCTION public.criar_cobranca_saldo_devedor(uuid, uuid) TO service_role;

-- ----------------------------------------------------------------------------
-- 6) Ajuste fechar_pedido_pago pra cobranca_saldo: aplica parcela ao pedido
--    original em vez de criar pedido novo
-- ----------------------------------------------------------------------------
-- Re-cria fechar_pedido_pago com branch pra is_cobranca_saldo
CREATE OR REPLACE FUNCTION public.fechar_pedido_pago(
  p_pedido_em_aberto_id uuid,
  p_pix_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rascunho public.pedido_em_aberto%ROWTYPE;
  v_pedido_id uuid;
  v_qtd integer;
  v_canal text;
  v_caixa text;
  v_status_pgto text;
  v_valor_pago numeric;
  v_saldo_devedor numeric;
  v_pedido_pendente_target uuid;
  v_resultado jsonb;
BEGIN
  SELECT * INTO v_rascunho FROM public.pedido_em_aberto WHERE id = p_pedido_em_aberto_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_em_aberto não encontrado');
  END IF;

  IF v_rascunho.status = 'pago' THEN
    RETURN jsonb_build_object('ok', true, 'idempotente', true, 'pedido_id', v_rascunho.pedido_id);
  END IF;

  v_caixa := COALESCE(v_rascunho.caixa_id, 'C1');

  -- ============== BRANCH: COBRANÇA DE SALDO DEVEDOR ==============
  IF v_rascunho.is_cobranca_saldo THEN
    -- Procura pedido pendente mais antigo do contato pra abater
    SELECT id INTO v_pedido_pendente_target
      FROM public.pedidos
     WHERE contato_id = v_rascunho.contato_id
       AND status_pagamento = 'pendente'
       AND status_pedido != 'cancelado'
     ORDER BY data ASC LIMIT 1;

    IF v_pedido_pendente_target IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'nenhum pedido pendente encontrado pra abater');
    END IF;

    -- Aplica parcela ao pedido alvo
    SELECT public.aplicar_parcela_pedido(
      v_pedido_pendente_target, v_rascunho.total, v_caixa
    ) INTO v_resultado;

    UPDATE public.pedido_em_aberto
       SET status = 'pago', pago_em = now(),
           pix_id = COALESCE(p_pix_id, pix_id),
           pedido_id = v_pedido_pendente_target,
           updated_at = now()
     WHERE id = p_pedido_em_aberto_id;

    -- Trigger de pedidos recomputa estado do contato automaticamente
    -- (cliente_pendente → cliente quando saldo zera)
    RETURN jsonb_build_object('ok', true,
                              'cobranca_saldo', true,
                              'pedido_id', v_pedido_pendente_target,
                              'valor_pago', v_rascunho.total,
                              'caixa', v_caixa,
                              'parcela_resultado', v_resultado);
  END IF;

  -- ============== BRANCH: PEDIDO NOVO (à vista ou parcelado) ==============
  SELECT COALESCE(SUM((value->>'qtd')::int), 0)
    INTO v_qtd
    FROM jsonb_array_elements(v_rascunho.itens);

  SELECT canal_origem INTO v_canal FROM public.contatos WHERE id = v_rascunho.contato_id;
  v_canal := COALESCE(v_canal, 'BASE');
  IF v_canal NOT IN ('ADS','BASE','REP') THEN v_canal := 'BASE'; END IF;

  v_valor_pago := COALESCE(v_rascunho.valor_primeira_parcela, v_rascunho.total);

  IF v_rascunho.is_parcelado THEN
    v_status_pgto := 'pendente';
    v_saldo_devedor := v_rascunho.total - v_valor_pago;
  ELSE
    v_status_pgto := 'pago';
    v_saldo_devedor := 0;
  END IF;

  INSERT INTO public.pedidos (
    contato_id, produto, quantidade, valor, valor_original, canal,
    endereco_entrega, status_pedido, status_pagamento, data
  ) VALUES (
    v_rascunho.contato_id,
    (SELECT string_agg((it->>'emoji') || ' ' || (it->>'nome_oficial') || ' (' || (it->>'qtd') || 'x)', ' | ')
       FROM jsonb_array_elements(v_rascunho.itens) it),
    v_qtd,
    v_saldo_devedor,
    v_rascunho.total,
    v_canal,
    v_rascunho.endereco_snapshot::text,
    'aguardando_rastreio',
    v_status_pgto,
    CURRENT_DATE
  ) RETURNING id INTO v_pedido_id;

  INSERT INTO public.lancamentos_socios (
    socio, tipo, valor, canal, contato_id, quantidade, modalidade,
    status_pagamento, criado_por, pedido_id, descricao
  ) VALUES (
    v_caixa,
    CASE WHEN v_rascunho.is_parcelado THEN 'PARCELA_VENDA' ELSE 'VENDA' END,
    v_valor_pago, v_canal, v_rascunho.contato_id, v_qtd, v_rascunho.modalidade_frete,
    'pago', 'AGENT_CLOSING', v_pedido_id,
    CASE WHEN v_rascunho.is_parcelado
         THEN 'Parcela 1/2 (entrada) — pedido #' || v_pedido_id::text
         ELSE 'Venda à vista — pedido #' || v_pedido_id::text END
  );

  IF v_rascunho.is_parcelado THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      status_pagamento, criado_por, pedido_id, descricao
    ) VALUES (
      'P', 'VENDA', v_saldo_devedor, v_canal, v_rascunho.contato_id, v_qtd,
      v_rascunho.modalidade_frete, 'pendente', 'AGENT_CLOSING', v_pedido_id,
      'Saldo devedor (parcela 2/2) — pedido #' || v_pedido_id::text
    );
  END IF;

  UPDATE public.pedido_em_aberto
     SET status = 'pago', pago_em = now(),
         pix_id = COALESCE(p_pix_id, pix_id),
         pedido_id = v_pedido_id,
         updated_at = now()
   WHERE id = p_pedido_em_aberto_id;

  -- Trigger de pedidos recomputa estado do contato (cliente OU cliente_pendente)
  RETURN jsonb_build_object('ok', true,
                            'pedido_id', v_pedido_id,
                            'valor_pago', v_valor_pago,
                            'is_parcelado', v_rascunho.is_parcelado,
                            'saldo_devedor', v_saldo_devedor,
                            'caixa', v_caixa);
END $$;

GRANT EXECUTE ON FUNCTION public.fechar_pedido_pago(uuid, text) TO service_role;

-- ----------------------------------------------------------------------------
-- 7) aplicar_parcela_pedido sobrecarregada pra aceitar p_socio explícito
--    (caixa em vez do socio do usuário logado, usado em cobranças do bot)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.aplicar_parcela_pedido(
  p_pedido_id uuid,
  p_valor numeric,
  p_socio text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido public.pedidos%ROWTYPE;
  v_novo_valor numeric;
  v_data_sp date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_existing_p_id uuid;
BEGIN
  SELECT * INTO v_pedido FROM public.pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado';
  END IF;
  IF v_pedido.status_pagamento <> 'pendente' THEN
    RAISE EXCEPTION 'Pedido não está pendente (status=%)', v_pedido.status_pagamento;
  END IF;
  IF p_valor IS NULL OR p_valor <= 0 THEN
    RAISE EXCEPTION 'Valor da parcela deve ser maior que 0';
  END IF;
  IF v_pedido.valor_original IS NULL THEN
    UPDATE public.pedidos SET valor_original = valor WHERE id = p_pedido_id;
  END IF;
  IF p_valor > v_pedido.valor THEN
    RAISE EXCEPTION 'Valor da parcela (%) excede o saldo devedor (%)', p_valor, v_pedido.valor;
  END IF;

  v_novo_valor := v_pedido.valor - p_valor;

  INSERT INTO public.lancamentos_socios (
    socio, tipo, valor, canal, contato_id, modalidade, status_pagamento,
    criado_por, pedido_id, data, descricao
  ) VALUES (
    p_socio, 'PARCELA_VENDA', p_valor, v_pedido.canal, v_pedido.contato_id,
    v_pedido.modalidade, 'pago', 'AGENT_CLOSING', p_pedido_id, v_data_sp,
    'Parcela #' || v_pedido.order_number::text
  );

  UPDATE public.pedidos
     SET valor = v_novo_valor,
         data_pago = CASE WHEN v_novo_valor <= 0 THEN v_data_sp ELSE data_pago END,
         status_pagamento = CASE WHEN v_novo_valor <= 0 THEN 'pago' ELSE status_pagamento END
   WHERE id = p_pedido_id;

  SELECT id INTO v_existing_p_id FROM public.lancamentos_socios
   WHERE pedido_id = p_pedido_id AND socio = 'P' AND tipo = 'VENDA' LIMIT 1;
  IF v_existing_p_id IS NOT NULL THEN
    IF v_novo_valor <= 0 THEN
      DELETE FROM public.lancamentos_socios WHERE id = v_existing_p_id;
    ELSE
      UPDATE public.lancamentos_socios SET valor = v_novo_valor WHERE id = v_existing_p_id;
    END IF;
  END IF;

  UPDATE public.financeiro
  SET valor = v_novo_valor
  WHERE tipo = 'receita_pendente'
    AND descricao ILIKE '%Venda Pendente #' || p_pedido_id::text || '%';

  IF v_novo_valor <= 0 THEN
    DELETE FROM public.financeiro
    WHERE tipo = 'receita_pendente'
      AND descricao ILIKE '%Venda Pendente #' || p_pedido_id::text || '%';
  END IF;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id,
    'saldo_anterior', v_pedido.valor,
    'parcela', p_valor,
    'saldo_atual', v_novo_valor,
    'status', CASE WHEN v_novo_valor <= 0 THEN 'pago' ELSE 'pendente' END
  );
END $$;

GRANT EXECUTE ON FUNCTION public.aplicar_parcela_pedido(uuid, numeric, text) TO service_role;

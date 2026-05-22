-- ============================================================================
-- Feature: Parcelas e Desconto em pedidos pendentes
-- - pedidos.valor passa a ser o saldo devedor (decresce com parcelas/desconto)
-- - pedidos.valor_original preserva o valor inicial
-- - pedidos.desconto_total acumula descontos aplicados
-- - lancamentos_socios.tipo aceita PARCELA_VENDA
-- - RPCs: aplicar_parcela_pedido, aplicar_desconto_pedido
-- ============================================================================

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS valor_original numeric;
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS desconto_total numeric NOT NULL DEFAULT 0;

-- Backfill: valor_original = valor para pedidos existentes
UPDATE public.pedidos SET valor_original = valor WHERE valor_original IS NULL;

-- Expande o CHECK de tipos em lancamentos_socios
ALTER TABLE public.lancamentos_socios DROP CONSTRAINT IF EXISTS lancamentos_socios_tipo_check;
ALTER TABLE public.lancamentos_socios ADD CONSTRAINT lancamentos_socios_tipo_check
  CHECK (tipo IN ('VENDA', 'ADS', 'ETIQUETA', 'MATERIAL', 'LOGISTICA', 'TRANSFERENCIA', 'LUCRO', 'CAPITAL_INICIAL', 'PARCELA_VENDA'));

-- ----------------------------------------------------------------------------
-- RPC: aplicar_parcela_pedido
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.aplicar_parcela_pedido(
  p_pedido_id uuid,
  p_valor numeric,
  p_socio text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido record;
  v_socio_upper text;
  v_apelido text;
  v_data_sp date;
  v_snapshot_v numeric;
  v_snapshot_a numeric;
  v_novo_valor numeric;
  v_existing_p_id uuid;
BEGIN
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_pedido_id IS NULL THEN RAISE EXCEPTION 'p_pedido_id obrigatorio'; END IF;
  IF p_valor IS NULL OR p_valor <= 0 THEN RAISE EXCEPTION 'Valor da parcela deve ser maior que 0'; END IF;

  v_socio_upper := UPPER(LEFT(COALESCE(p_socio, ''), 1));
  IF v_socio_upper NOT IN ('V', 'A') THEN RAISE EXCEPTION 'Socio invalido: %', p_socio; END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF v_pedido.id IS NULL THEN RAISE EXCEPTION 'Pedido nao encontrado: %', p_pedido_id; END IF;

  IF v_pedido.status_pagamento <> 'pendente' THEN
    RAISE EXCEPTION 'Pedido nao esta pendente (status=%)', v_pedido.status_pagamento;
  END IF;

  IF p_valor > v_pedido.valor THEN
    RAISE EXCEPTION 'Valor da parcela (%) excede o saldo devedor (%)', p_valor, v_pedido.valor;
  END IF;

  -- Garante valor_original
  IF v_pedido.valor_original IS NULL THEN
    UPDATE public.pedidos SET valor_original = valor WHERE id = p_pedido_id;
  END IF;

  v_novo_valor := v_pedido.valor - p_valor;

  -- Apelido do usuario logado
  SELECT nome INTO v_apelido FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1;
  v_apelido := COALESCE(NULLIF(v_apelido, ''), v_socio_upper);

  -- Snapshot dos saldos ANTES de inserir parcela
  SELECT
    COALESCE(SUM(CASE WHEN socio = 'V' THEN valor ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN socio = 'A' THEN valor ELSE 0 END), 0)
  INTO v_snapshot_v, v_snapshot_a
  FROM public.lancamentos_socios;

  -- Insere nova linha PARCELA_VENDA
  INSERT INTO public.lancamentos_socios (
    socio, tipo, valor, canal, contato_id, quantidade, modalidade,
    uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao,
    snapshot_saldo_v, snapshot_saldo_a, realizado, realizado_em
  ) VALUES (
    v_socio_upper, 'PARCELA_VENDA', p_valor, v_pedido.canal, v_pedido.contato_id,
    NULL, v_pedido.modalidade, v_pedido.uf_postagem, 'pago',
    v_apelido, p_pedido_id, v_data_sp,
    'Parcela #' || v_pedido.order_number::text,
    v_snapshot_v, v_snapshot_a, true, now()
  );

  -- Atualiza o saldo devedor no pedido
  UPDATE public.pedidos
  SET valor = v_novo_valor,
      data_pago = CASE WHEN v_novo_valor <= 0 THEN v_data_sp ELSE data_pago END,
      status_pagamento = CASE WHEN v_novo_valor <= 0 THEN 'pago' ELSE status_pagamento END
  WHERE id = p_pedido_id;

  -- Atualiza a linha pendente original (socio='P') se ainda existir
  SELECT id INTO v_existing_p_id FROM public.lancamentos_socios
  WHERE pedido_id = p_pedido_id AND socio = 'P' AND tipo = 'VENDA' LIMIT 1;

  IF v_existing_p_id IS NOT NULL THEN
    IF v_novo_valor <= 0 THEN
      -- Saldo zerado: a venda foi totalmente recebida em parcelas/desconto.
      -- Remove a linha pendente original (nao ha venda final a converter).
      DELETE FROM public.lancamentos_socios WHERE id = v_existing_p_id;
    ELSE
      -- Decrementa o valor pendente da linha P para refletir o saldo
      UPDATE public.lancamentos_socios SET valor = v_novo_valor WHERE id = v_existing_p_id;
    END IF;
  END IF;

  -- Tambem atualiza a linha receita_pendente no financeiro
  UPDATE public.financeiro
  SET valor = v_novo_valor
  WHERE tipo = 'receita_pendente'
    AND (descricao = v_pedido.canal || ' - Venda Pendente #' || p_pedido_id::text
         OR descricao ILIKE '%Venda Pendente #' || p_pedido_id::text || '%');

  IF v_novo_valor <= 0 THEN
    DELETE FROM public.financeiro
    WHERE tipo = 'receita_pendente'
      AND (descricao = v_pedido.canal || ' - Venda Pendente #' || p_pedido_id::text
           OR descricao ILIKE '%Venda Pendente #' || p_pedido_id::text || '%');
  END IF;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id,
    'saldo_anterior', v_pedido.valor,
    'parcela', p_valor,
    'saldo_atual', v_novo_valor,
    'status', CASE WHEN v_novo_valor <= 0 THEN 'pago' ELSE 'pendente' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.aplicar_parcela_pedido TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- RPC: aplicar_desconto_pedido
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.aplicar_desconto_pedido(
  p_pedido_id uuid,
  p_valor numeric
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido record;
  v_data_sp date;
  v_novo_valor numeric;
  v_existing_p_id uuid;
BEGIN
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_pedido_id IS NULL THEN RAISE EXCEPTION 'p_pedido_id obrigatorio'; END IF;
  IF p_valor IS NULL OR p_valor <= 0 THEN RAISE EXCEPTION 'Valor do desconto deve ser maior que 0'; END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF v_pedido.id IS NULL THEN RAISE EXCEPTION 'Pedido nao encontrado: %', p_pedido_id; END IF;

  IF v_pedido.status_pagamento <> 'pendente' THEN
    RAISE EXCEPTION 'Pedido nao esta pendente (status=%)', v_pedido.status_pagamento;
  END IF;

  IF p_valor > v_pedido.valor THEN
    RAISE EXCEPTION 'Desconto (%) excede o saldo devedor (%)', p_valor, v_pedido.valor;
  END IF;

  IF v_pedido.valor_original IS NULL THEN
    UPDATE public.pedidos SET valor_original = valor WHERE id = p_pedido_id;
  END IF;

  v_novo_valor := v_pedido.valor - p_valor;

  -- Atualiza o pedido (saldo + desconto_total + status se zerou)
  UPDATE public.pedidos
  SET valor = v_novo_valor,
      desconto_total = COALESCE(desconto_total, 0) + p_valor,
      data_pago = CASE WHEN v_novo_valor <= 0 THEN v_data_sp ELSE data_pago END,
      status_pagamento = CASE WHEN v_novo_valor <= 0 THEN 'pago' ELSE status_pagamento END
  WHERE id = p_pedido_id;

  -- Ajusta linha P se ainda existir
  SELECT id INTO v_existing_p_id FROM public.lancamentos_socios
  WHERE pedido_id = p_pedido_id AND socio = 'P' AND tipo = 'VENDA' LIMIT 1;

  IF v_existing_p_id IS NOT NULL THEN
    IF v_novo_valor <= 0 THEN
      DELETE FROM public.lancamentos_socios WHERE id = v_existing_p_id;
    ELSE
      UPDATE public.lancamentos_socios SET valor = v_novo_valor WHERE id = v_existing_p_id;
    END IF;
  END IF;

  -- Atualiza/remove a linha receita_pendente
  UPDATE public.financeiro
  SET valor = v_novo_valor
  WHERE tipo = 'receita_pendente'
    AND (descricao = v_pedido.canal || ' - Venda Pendente #' || p_pedido_id::text
         OR descricao ILIKE '%Venda Pendente #' || p_pedido_id::text || '%');

  IF v_novo_valor <= 0 THEN
    DELETE FROM public.financeiro
    WHERE tipo = 'receita_pendente'
      AND (descricao = v_pedido.canal || ' - Venda Pendente #' || p_pedido_id::text
           OR descricao ILIKE '%Venda Pendente #' || p_pedido_id::text || '%');
  END IF;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id,
    'saldo_anterior', v_pedido.valor,
    'desconto', p_valor,
    'saldo_atual', v_novo_valor,
    'status', CASE WHEN v_novo_valor <= 0 THEN 'pago' ELSE 'pendente' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.aplicar_desconto_pedido TO authenticated, service_role;

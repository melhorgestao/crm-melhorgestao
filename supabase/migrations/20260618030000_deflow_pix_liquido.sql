-- ============================================================================
-- DeFlow: campos pra taxa/líquido + ajuste fechar_pedido_pago pra lançar
-- VALOR LÍQUIDO na caixa (regra de negócio: caixa = real recebido pós-taxa)
--
-- Endpoint usado: POST /v1/deposit/create (mode=exact)
-- - Cliente paga amountCents cheios (valor do pedido)
-- - DeFlow cobra feeCents
-- - DePix creditado = netAmountCents
-- - Lançamos VENDA/PARCELA_VENDA na caixa com netAmountCents/100 (= reais)
--
-- Doc não suporta external_id/metadata → linkagem via pedido_em_aberto.pix_id
-- ============================================================================

-- 1) Campos novos no pedido_em_aberto
ALTER TABLE public.pedido_em_aberto
  ADD COLUMN IF NOT EXISTS pix_taxa_cents      bigint,
  ADD COLUMN IF NOT EXISTS pix_liquido_cents   bigint,
  ADD COLUMN IF NOT EXISTS pix_bruto_cents     bigint,
  ADD COLUMN IF NOT EXISTS pix_qr_image_url    text;

COMMENT ON COLUMN public.pedido_em_aberto.pix_taxa_cents IS
  'Taxa cobrada pelo DeFlow (feeCents) — não vai pra caixa.';
COMMENT ON COLUMN public.pedido_em_aberto.pix_liquido_cents IS
  'Valor LÍQUIDO creditado na conta DeFlow (netAmountCents). É o que entra no caixa.';
COMMENT ON COLUMN public.pedido_em_aberto.pix_bruto_cents IS
  'Valor BRUTO pago pelo cliente (amountCents). Igual a total*100 quando mode=exact.';

-- 2) Atualiza fechar_pedido_pago pra usar valor líquido na caixa
--    Mantém compatibilidade com chamadas antigas (sem p_valor_liquido_cents)
CREATE OR REPLACE FUNCTION public.fechar_pedido_pago(
  p_pedido_em_aberto_id uuid,
  p_pix_id text DEFAULT NULL,
  p_valor_liquido_cents bigint DEFAULT NULL,
  p_taxa_cents bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rascunho public.pedido_em_aberto%ROWTYPE;
  v_pedido_id uuid;
  v_qtd integer;
  v_canal text;
  v_caixa text;
  v_status_pgto text;
  v_valor_pago numeric;       -- valor BRUTO pago pelo cliente (que abate saldo)
  v_valor_caixa numeric;      -- valor LÍQUIDO pra creditar na caixa
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

  -- Persiste taxa/líquido se vieram do webhook
  IF p_valor_liquido_cents IS NOT NULL OR p_taxa_cents IS NOT NULL THEN
    UPDATE public.pedido_em_aberto
       SET pix_taxa_cents = COALESCE(p_taxa_cents, pix_taxa_cents),
           pix_liquido_cents = COALESCE(p_valor_liquido_cents, pix_liquido_cents),
           updated_at = now()
     WHERE id = p_pedido_em_aberto_id;
    -- atualiza a row em memória
    SELECT * INTO v_rascunho FROM public.pedido_em_aberto WHERE id = p_pedido_em_aberto_id;
  END IF;

  -- ============== BRANCH: COBRANÇA DE SALDO DEVEDOR ==============
  IF v_rascunho.is_cobranca_saldo THEN
    SELECT id INTO v_pedido_pendente_target
      FROM public.pedidos
     WHERE contato_id = v_rascunho.contato_id
       AND status_pagamento = 'pendente'
       AND status_pedido != 'cancelado'
     ORDER BY data ASC LIMIT 1;

    IF v_pedido_pendente_target IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'nenhum pedido pendente pra abater');
    END IF;

    -- VALOR PRA ABATER NO SALDO = BRUTO pago pelo cliente (descontar a dívida cheia)
    -- VALOR LANÇADO NA CAIXA = LÍQUIDO recebido (pós-taxa DeFlow)
    v_valor_pago := v_rascunho.total;  -- bruto (== amountCents/100)
    v_valor_caixa := COALESCE(v_rascunho.pix_liquido_cents::numeric / 100.0, v_valor_pago);

    -- Aplica parcela ao pedido alvo (abate o BRUTO da dívida)
    SELECT public.aplicar_parcela_pedido(
      v_pedido_pendente_target, v_valor_pago, v_caixa, v_valor_caixa
    ) INTO v_resultado;

    UPDATE public.pedido_em_aberto
       SET status = 'pago', pago_em = now(),
           pix_id = COALESCE(p_pix_id, pix_id),
           pedido_id = v_pedido_pendente_target,
           updated_at = now()
     WHERE id = p_pedido_em_aberto_id;

    RETURN jsonb_build_object('ok', true,
                              'cobranca_saldo', true,
                              'pedido_id', v_pedido_pendente_target,
                              'valor_bruto', v_valor_pago,
                              'valor_liquido_caixa', v_valor_caixa,
                              'caixa', v_caixa);
  END IF;

  -- ============== BRANCH: PEDIDO NOVO ==============
  SELECT COALESCE(SUM((value->>'qtd')::int), 0)
    INTO v_qtd
    FROM jsonb_array_elements(v_rascunho.itens);

  SELECT canal_origem INTO v_canal FROM public.contatos WHERE id = v_rascunho.contato_id;
  v_canal := COALESCE(v_canal, 'BASE');
  IF v_canal NOT IN ('ADS','BASE','REP') THEN v_canal := 'BASE'; END IF;

  -- VALOR PAGO BRUTO (do cliente): se parcelado, é a 1ª parcela; senão, total
  v_valor_pago := COALESCE(v_rascunho.valor_primeira_parcela, v_rascunho.total);

  -- VALOR LÍQUIDO PRA CAIXA = veio do webhook (preferido) OU bruto se não veio
  v_valor_caixa := COALESCE(v_rascunho.pix_liquido_cents::numeric / 100.0, v_valor_pago);

  IF v_rascunho.is_parcelado THEN
    v_status_pgto := 'pendente';
    v_saldo_devedor := v_rascunho.total - v_valor_pago;  -- saldo ainda é bruto
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

  -- LANÇAMENTO NA CAIXA: VALOR LÍQUIDO (pós-taxa DeFlow)
  INSERT INTO public.lancamentos_socios (
    socio, tipo, valor, canal, contato_id, quantidade, modalidade,
    status_pagamento, criado_por, pedido_id, descricao
  ) VALUES (
    v_caixa,
    CASE WHEN v_rascunho.is_parcelado THEN 'PARCELA_VENDA' ELSE 'VENDA' END,
    v_valor_caixa,  -- LÍQUIDO
    v_canal, v_rascunho.contato_id, v_qtd, v_rascunho.modalidade_frete,
    'pago', 'AGENT_CLOSING', v_pedido_id,
    CASE WHEN v_rascunho.is_parcelado
         THEN 'Parcela 1/2 entrada (líq) — pedido #' || v_pedido_id::text
         ELSE 'Venda à vista (líq) — pedido #' || v_pedido_id::text END
  );

  -- Se parcelado, registra pendente da 2ª parcela com VALOR BRUTO restante
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

  RETURN jsonb_build_object('ok', true,
                            'pedido_id', v_pedido_id,
                            'valor_bruto_pago', v_valor_pago,
                            'valor_liquido_caixa', v_valor_caixa,
                            'taxa_descontada', v_valor_pago - v_valor_caixa,
                            'is_parcelado', v_rascunho.is_parcelado,
                            'saldo_devedor', v_saldo_devedor,
                            'caixa', v_caixa);
END $$;

GRANT EXECUTE ON FUNCTION public.fechar_pedido_pago(uuid, text, bigint, bigint) TO service_role, anon, authenticated;

-- 3) aplicar_parcela_pedido v3 — aceita valor_caixa_override (lança líquido em vez de bruto)
CREATE OR REPLACE FUNCTION public.aplicar_parcela_pedido(
  p_pedido_id uuid,
  p_valor numeric,           -- valor BRUTO que abate dívida
  p_socio text,
  p_valor_caixa numeric DEFAULT NULL  -- valor LÍQUIDO pra caixa (default: igual ao bruto)
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido public.pedidos%ROWTYPE;
  v_novo_valor numeric;
  v_data_sp date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_existing_p_id uuid;
  v_caixa_efetivo numeric := COALESCE(p_valor_caixa, p_valor);
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

  v_novo_valor := v_pedido.valor - p_valor;  -- saldo decresce no BRUTO

  -- Lança parcela com VALOR LÍQUIDO (= o que entrou de fato na caixa)
  INSERT INTO public.lancamentos_socios (
    socio, tipo, valor, canal, contato_id, modalidade, status_pagamento,
    criado_por, pedido_id, data, descricao
  ) VALUES (
    p_socio, 'PARCELA_VENDA', v_caixa_efetivo, v_pedido.canal, v_pedido.contato_id,
    v_pedido.modalidade, 'pago', 'AGENT_CLOSING', p_pedido_id, v_data_sp,
    'Parcela #' || v_pedido.order_number::text || ' (líq)'
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
    'parcela_bruta', p_valor,
    'parcela_liquida_caixa', v_caixa_efetivo,
    'saldo_atual', v_novo_valor,
    'status', CASE WHEN v_novo_valor <= 0 THEN 'pago' ELSE 'pendente' END
  );
END $$;

GRANT EXECUTE ON FUNCTION public.aplicar_parcela_pedido(uuid, numeric, text, numeric) TO service_role;

-- 4) RPC pra processar webhook do DeFlow (atomicidade total)
CREATE OR REPLACE FUNCTION public.processar_webhook_deflow(
  p_event       text,
  p_deposit_id  text,
  p_status      text,
  p_amount_cents bigint,
  p_fee_cents   bigint,
  p_net_cents   bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido_aberto_id uuid;
  v_resultado jsonb;
BEGIN
  -- Lookup do rascunho pelo pix_id (= deposit.id do DeFlow)
  SELECT id INTO v_pedido_aberto_id
    FROM public.pedido_em_aberto
   WHERE pix_id = p_deposit_id
   LIMIT 1;

  IF v_pedido_aberto_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'nenhum pedido_em_aberto com pix_id=' || p_deposit_id);
  END IF;

  -- EVENT deposit.completed (terminal de sucesso)
  IF p_event IN ('deposit.completed','deposit.approved') THEN
    SELECT public.fechar_pedido_pago(
      v_pedido_aberto_id,
      p_deposit_id,
      p_net_cents,
      p_fee_cents
    ) INTO v_resultado;
    RETURN jsonb_build_object('ok', true, 'evento', p_event,
                              'pedido_em_aberto_id', v_pedido_aberto_id,
                              'fechamento', v_resultado);
  END IF;

  -- EVENT deposit.expired → marca expirado, contato volta pra estado anterior
  IF p_event = 'deposit.expired' THEN
    UPDATE public.pedido_em_aberto
       SET status = 'expirado', updated_at = now()
     WHERE id = v_pedido_aberto_id AND status = 'aguardando_pagamento';

    UPDATE public.contatos
       SET ultima_interacao = CASE WHEN ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
           data_aguardando_pagamento = NULL,
           updated_at = now()
     WHERE id = (SELECT contato_id FROM public.pedido_em_aberto WHERE id = v_pedido_aberto_id)
       AND ultima_interacao = 'aguardando_pagamento';

    RETURN jsonb_build_object('ok', true, 'evento', p_event,
                              'pedido_em_aberto_id', v_pedido_aberto_id,
                              'acao', 'expirado');
  END IF;

  RETURN jsonb_build_object('ok', false, 'error', 'evento desconhecido: ' || p_event);
END $$;

GRANT EXECUTE ON FUNCTION public.processar_webhook_deflow(text, text, text, bigint, bigint, bigint)
  TO service_role;

-- 5) Configs default (chaves DeFlow ficam vazias até user preencher via UI)
INSERT INTO public.configuracoes (chave, valor) VALUES
  ('deflow_api_key', ''),
  ('deflow_secret', ''),
  ('deflow_passphrase', ''),
  ('deflow_wallet_id', ''),
  ('deflow_webhook_n8n_url', 'https://n8n.melhorgestao.online/webhook/pix-pago-notify')
ON CONFLICT (chave) DO NOTHING;

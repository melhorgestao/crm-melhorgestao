-- ============================================================================
-- fechar_pedido_pago: corrige 2 bugs expostos no 1º pagamento DeFlow real.
--
-- BUG 1 (não ia pra Logística): o INSERT em pedidos NÃO setava `modalidade`.
--   A Logística filtra `modalidade <> 'entrega_maos'` — e NULL <> x é NULL
--   (não-verdadeiro) no Postgres → o pedido sumia da fila de envio.
--   FIX: seta modalidade (da modalidade_frete do rascunho; fallback 'sedex')
--   + uf_postagem (do endereço), pra a etiqueta sair certa.
--
-- BUG 2 (valor bruto em Pedidos): o INSERT setava valor_original = total
--   (bruto) e NÃO setava desconto_total. Pedidos mostra
--   valor_original − desconto_total → ficava o bruto. O caixa já lança o
--   líquido; faltava alinhar o pedido.
--   FIX: desconto_total = taxa DeFlow (pix_taxa_cents), então vendaReal
--   (valor_original − desconto) = líquido, igual ao caixa e às métricas.
--
-- BUG 3 (não baixava estoque): não criava pedido_itens → estoque nunca abatia
--   nos pedidos DeFlow. FIX: cria pedido_itens (resolve produto_id pela tag,
--   itens + brindes) e chama processar_pedido_estoque_trigger (FIFO idempotente).
--
-- Resto da função idêntico à 20260618030000.
-- ============================================================================

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
  v_valor_pago numeric;
  v_valor_caixa numeric;
  v_saldo_devedor numeric;
  v_pedido_pendente_target uuid;
  v_resultado jsonb;
  v_taxa numeric;
  v_modalidade text;
  v_uf text;
BEGIN
  SELECT * INTO v_rascunho FROM public.pedido_em_aberto WHERE id = p_pedido_em_aberto_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_em_aberto não encontrado');
  END IF;

  IF v_rascunho.status = 'pago' THEN
    RETURN jsonb_build_object('ok', true, 'idempotente', true, 'pedido_id', v_rascunho.pedido_id);
  END IF;

  v_caixa := COALESCE(v_rascunho.caixa_id, 'C1');

  IF p_valor_liquido_cents IS NOT NULL OR p_taxa_cents IS NOT NULL THEN
    UPDATE public.pedido_em_aberto
       SET pix_taxa_cents = COALESCE(p_taxa_cents, pix_taxa_cents),
           pix_liquido_cents = COALESCE(p_valor_liquido_cents, pix_liquido_cents),
           updated_at = now()
     WHERE id = p_pedido_em_aberto_id;
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

    v_valor_pago := v_rascunho.total;
    v_valor_caixa := COALESCE(v_rascunho.pix_liquido_cents::numeric / 100.0, v_valor_pago);

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

  v_valor_pago := COALESCE(v_rascunho.valor_primeira_parcela, v_rascunho.total);
  v_valor_caixa := COALESCE(v_rascunho.pix_liquido_cents::numeric / 100.0, v_valor_pago);

  -- taxa DeFlow (vira desconto_total do pedido → vendaReal = líquido)
  v_taxa := COALESCE(v_rascunho.pix_taxa_cents::numeric / 100.0, 0);
  -- modalidade real (senão NULL some da Logística) + uf pra etiqueta
  v_modalidade := COALESCE(NULLIF(btrim(v_rascunho.modalidade_frete), ''), 'sedex');
  v_uf := NULLIF(btrim(COALESCE(v_rascunho.endereco_snapshot->>'uf', '')), '');

  IF v_rascunho.is_parcelado THEN
    v_status_pgto := 'pendente';
    v_saldo_devedor := v_rascunho.total - v_valor_pago;
  ELSE
    v_status_pgto := 'pago';
    v_saldo_devedor := 0;
  END IF;

  INSERT INTO public.pedidos (
    contato_id, produto, quantidade, valor, valor_original, desconto_total, canal,
    endereco_entrega, modalidade, uf_postagem, status_pedido, status_pagamento, data
  ) VALUES (
    v_rascunho.contato_id,
    (SELECT string_agg((it->>'emoji') || ' ' || (it->>'nome_oficial') || ' (' || (it->>'qtd') || 'x)', ' | ')
       FROM jsonb_array_elements(v_rascunho.itens) it),
    v_qtd,
    v_saldo_devedor,
    v_rascunho.total,
    v_taxa,
    v_canal,
    v_rascunho.endereco_snapshot::text,
    v_modalidade,
    v_uf,
    'aguardando_rastreio',
    v_status_pgto,
    CURRENT_DATE
  ) RETURNING id INTO v_pedido_id;

  -- BUG 3 (não baixava estoque): a fechar_pedido_pago não criava pedido_itens,
  -- então o pedido DeFlow nunca abatia estoque. Os itens do rascunho têm `tag`
  -- (não produto_id), então resolvemos o produto pela tag. Brindes entram como
  -- is_free=true (envio real, também abatem). Depois chamamos a função
  -- idempotente de abatimento (FIFO, trata "sem lote").
  INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco, is_free)
  SELECT v_pedido_id, pr.id, COALESCE((it->>'qtd')::int, 1), 0, false
    FROM jsonb_array_elements(v_rascunho.itens) it
    CROSS JOIN LATERAL (
      SELECT id FROM public.produtos WHERE tag = (it->>'tag')
       ORDER BY ativo DESC, created_at ASC LIMIT 1
    ) pr
   WHERE COALESCE(it->>'tag', '') <> '';

  INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco, is_free)
  SELECT v_pedido_id, pr.id, 1, 0, true
    FROM jsonb_array_elements(COALESCE(v_rascunho.brindes, '[]'::jsonb)) br
    CROSS JOIN LATERAL (
      SELECT id FROM public.produtos WHERE tag = (br->>'tag')
       ORDER BY ativo DESC, created_at ASC LIMIT 1
    ) pr
   WHERE COALESCE(br->>'tag', '') <> '';

  BEGIN
    PERFORM public.processar_pedido_estoque_trigger(v_pedido_id, v_uf);
  EXCEPTION WHEN OTHERS THEN
    -- estoque é best-effort: um erro aqui NÃO pode desfazer a venda paga.
    NULL;
  END;

  INSERT INTO public.lancamentos_socios (
    socio, tipo, valor, canal, contato_id, quantidade, modalidade,
    status_pagamento, criado_por, pedido_id, descricao
  ) VALUES (
    v_caixa,
    CASE WHEN v_rascunho.is_parcelado THEN 'PARCELA_VENDA' ELSE 'VENDA' END,
    v_valor_caixa,
    v_canal, v_rascunho.contato_id, v_qtd, v_rascunho.modalidade_frete,
    'pago', 'AGENT_CLOSING', v_pedido_id,
    CASE WHEN v_rascunho.is_parcelado
         THEN 'Parcela 1/2 entrada (líq) — pedido #' || v_pedido_id::text
         ELSE 'Venda à vista (líq) — pedido #' || v_pedido_id::text END
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

  RETURN jsonb_build_object('ok', true,
                            'pedido_id', v_pedido_id,
                            'valor_bruto_pago', v_valor_pago,
                            'valor_liquido_caixa', v_valor_caixa,
                            'taxa_descontada', v_valor_pago - v_valor_caixa,
                            'is_parcelado', v_rascunho.is_parcelado,
                            'saldo_devedor', v_saldo_devedor,
                            'caixa', v_caixa);
END $$;

GRANT EXECUTE ON FUNCTION public.fechar_pedido_pago(uuid, text, bigint, bigint)
  TO service_role, anon, authenticated;

NOTIFY pgrst, 'reload schema';

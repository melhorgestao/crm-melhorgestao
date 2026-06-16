-- ============================================================================
-- Pix expirado: mantém contato em 'em_fechamento' (NÃO joga pra wait_follow_up)
--
-- Motivo: agente de closing deve poder gerar novo Pix se cliente voltar
-- e disser que quer pagar. Cron da state machine cuida de retroceder
-- contatos parados em em_fechamento depois de 48h.
-- ============================================================================

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
  SELECT id INTO v_pedido_aberto_id
    FROM public.pedido_em_aberto
   WHERE pix_id = p_deposit_id
   LIMIT 1;

  IF v_pedido_aberto_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'nenhum pedido_em_aberto com pix_id=' || p_deposit_id);
  END IF;

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

  -- EVENT deposit.expired → MANTÉM contato em em_fechamento
  -- Só marca o rascunho como expirado. Agente closing pode gerar novo Pix
  -- na próxima mensagem do cliente. Cron decide retroceder após 48h.
  IF p_event = 'deposit.expired' THEN
    UPDATE public.pedido_em_aberto
       SET status = 'expirado', updated_at = now()
     WHERE id = v_pedido_aberto_id AND status = 'aguardando_pagamento';

    -- Volta o contato de 'aguardando_pagamento' pra 'em_fechamento'
    -- (NÃO pra wait_follow_up — cron resolve depois)
    UPDATE public.contatos
       SET ultima_interacao = 'em_fechamento',
           data_em_fechamento = COALESCE(data_em_fechamento, now()),
           data_aguardando_pagamento = NULL,
           updated_at = now()
     WHERE id = (SELECT contato_id FROM public.pedido_em_aberto WHERE id = v_pedido_aberto_id)
       AND ultima_interacao = 'aguardando_pagamento';

    RETURN jsonb_build_object('ok', true, 'evento', p_event,
                              'pedido_em_aberto_id', v_pedido_aberto_id,
                              'acao', 'expirado_em_fechamento');
  END IF;

  RETURN jsonb_build_object('ok', false, 'error', 'evento desconhecido: ' || p_event);
END $$;

GRANT EXECUTE ON FUNCTION public.processar_webhook_deflow(text, text, text, bigint, bigint, bigint)
  TO service_role;

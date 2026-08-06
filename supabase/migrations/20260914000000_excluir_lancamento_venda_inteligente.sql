-- ============================================================================
-- Exclusão INTELIGENTE de lançamento de venda no Financeiro.
--
-- Regras (definidas pelo dono do sistema):
--   1. VENDA de pedido que NASCEU PAGO (criado já pago via Financeiro):
--        excluir o lançamento  →  EXCLUI o pedido (cascade — reusa
--        deletar_venda_completa). Ele não vira pendente.
--   2. VENDA de pedido que NASCEU PENDENTE (foi pago depois):
--        excluir o lançamento  →  o pedido VOLTA para 'pendente'
--        (desfaz o pagamento). Pedido/itens/estoque permanecem.
--   3. PARCELA_VENDA:
--        excluir a parcela  →  o valor volta a somar no SALDO devedor
--        (pedido.valor += parcela) e o pedido volta/permanece 'pendente'.
--
-- Diferenciação nasceu-pendente x nasceu-pago (conservadora — na dúvida,
-- reverte em vez de apagar): considera-se que JÁ FOI pendente se houver
-- QUALQUER evidência — linha socio='P', marcador "Venda Pendente #<id>" no
-- financeiro, ou alguma PARCELA_VENDA no pedido.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.excluir_lancamento_venda(p_lancamento_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lanc        record;
  v_pedido      record;
  v_pid         uuid;
  v_was_pending boolean;
  v_novo_saldo  numeric;
  v_p_id        uuid;
  v_fin_id      uuid;
BEGIN
  SELECT * INTO v_lanc FROM public.lancamentos_socios WHERE id = p_lancamento_id;
  IF v_lanc IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Lançamento não encontrado');
  END IF;
  IF v_lanc.locked_at IS NOT NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Lançamento bloqueado (dia fechado)');
  END IF;

  v_pid := v_lanc.pedido_id;

  -- Sem pedido vinculado (custo avulso etc): remove normal.
  IF v_pid IS NULL THEN
    DELETE FROM public.lancamentos_socios WHERE id = p_lancamento_id;
    RETURN jsonb_build_object('status', 'ok', 'acao', 'removido');
  END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_pid FOR UPDATE;

  -- ---------------------------------------------------------------------------
  -- CASO 3: PARCELA_VENDA → devolve o valor ao saldo devedor
  -- ---------------------------------------------------------------------------
  IF v_lanc.tipo = 'PARCELA_VENDA' THEN
    IF v_pedido.id IS NULL THEN
      DELETE FROM public.lancamentos_socios WHERE id = p_lancamento_id;
      RETURN jsonb_build_object('status', 'ok', 'acao', 'removido');
    END IF;

    v_novo_saldo := COALESCE(v_pedido.valor, 0) + v_lanc.valor;

    UPDATE public.pedidos
       SET valor            = v_novo_saldo,
           status_pagamento = 'pendente',
           data_pago        = NULL
     WHERE id = v_pid;

    -- Reconstitui a linha pendente socio='P' (atualiza ou recria)
    SELECT id INTO v_p_id FROM public.lancamentos_socios
     WHERE pedido_id = v_pid AND socio = 'P' AND tipo = 'VENDA' LIMIT 1;
    IF v_p_id IS NOT NULL THEN
      UPDATE public.lancamentos_socios SET valor = v_novo_saldo, status_pagamento = 'pendente' WHERE id = v_p_id;
    ELSE
      INSERT INTO public.lancamentos_socios
        (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem,
         status_pagamento, criado_por, pedido_id, data)
      VALUES
        ('P', 'VENDA', v_novo_saldo, v_pedido.canal, v_pedido.contato_id, v_pedido.quantidade,
         v_pedido.modalidade, v_pedido.uf_postagem, 'pendente',
         COALESCE(v_pedido.criado_por, 'sistema'), v_pid, v_pedido.data);
    END IF;

    -- Reconstitui a linha receita_pendente no financeiro (atualiza ou recria)
    SELECT id INTO v_fin_id FROM public.financeiro
     WHERE descricao ILIKE '%Venda Pendente #' || v_pid::text || '%' LIMIT 1;
    IF v_fin_id IS NOT NULL THEN
      UPDATE public.financeiro SET tipo = 'receita_pendente', valor = v_novo_saldo WHERE id = v_fin_id;
    ELSE
      INSERT INTO public.financeiro (tipo, valor, canal, descricao)
      VALUES ('receita_pendente', v_novo_saldo, v_pedido.canal,
              v_pedido.canal || ' - Venda Pendente #' || v_pid::text);
    END IF;

    DELETE FROM public.lancamentos_socios WHERE id = p_lancamento_id;
    RETURN jsonb_build_object('status', 'ok', 'acao', 'parcela_revertida', 'pedido_id', v_pid, 'saldo', v_novo_saldo);
  END IF;

  -- ---------------------------------------------------------------------------
  -- CASO VENDA: decide entre reverter (nasceu pendente) ou apagar (nasceu pago)
  -- ---------------------------------------------------------------------------
  v_was_pending :=
       EXISTS (SELECT 1 FROM public.financeiro
                WHERE descricao ILIKE '%Venda Pendente #' || v_pid::text || '%')
    OR EXISTS (SELECT 1 FROM public.lancamentos_socios
                WHERE pedido_id = v_pid AND socio = 'P' AND tipo = 'VENDA')
    OR EXISTS (SELECT 1 FROM public.lancamentos_socios
                WHERE pedido_id = v_pid AND tipo = 'PARCELA_VENDA' AND id <> p_lancamento_id);

  IF v_was_pending THEN
    -- CASO 2: volta para pendente (inverso do "marcar como pago")
    UPDATE public.pedidos
       SET status_pagamento = 'pendente', data_pago = NULL, recebido_por = NULL
     WHERE id = v_pid;

    -- o lançamento clicado volta a ser a linha pendente 'P'
    UPDATE public.lancamentos_socios
       SET socio = 'P', status_pagamento = 'pendente', realizado = false, realizado_em = NULL
     WHERE id = p_lancamento_id;

    -- restaura o marcador no financeiro
    UPDATE public.financeiro
       SET tipo = 'receita_pendente'
     WHERE tipo = 'receita'
       AND descricao ILIKE '%Venda Pendente #' || v_pid::text || '%';

    RETURN jsonb_build_object('status', 'ok', 'acao', 'revertido_pendente', 'pedido_id', v_pid);
  END IF;

  -- CASO 1: nasceu pago → exclui o pedido (cascata testada)
  RETURN (public.deletar_venda_completa(p_lancamento_id)) || jsonb_build_object('acao', 'pedido_excluido');
END $$;

GRANT EXECUTE ON FUNCTION public.excluir_lancamento_venda(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

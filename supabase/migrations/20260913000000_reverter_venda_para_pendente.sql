-- ============================================================================
-- FIX DEFINITIVO: excluir uma VENDA no Financeiro NÃO pode mais apagar o pedido.
--
-- Antes: deletar_venda_completa fazia hard delete em cascata (pedido, itens,
-- movimentações, comissões, lançamentos) — um clique errado sumia com a venda
-- e ainda bugava saldo de pendentes/estoque.
--
-- Agora: a exclusão de uma VENDA no Financeiro apenas REVERTE o pedido para
-- 'pendente' (desfaz o pagamento) e remove só os lançamentos financeiros do
-- pagamento (VENDA/PARCELA_VENDA/LUCRO). Pedido, itens, estoque e comissões
-- permanecem intactos — a venda continua existindo, só volta a não-paga.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reverter_venda_para_pendente(p_lancamento_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lanc   record;
  v_pedido uuid;
BEGIN
  SELECT * INTO v_lanc FROM public.lancamentos_socios WHERE id = p_lancamento_id;
  IF v_lanc IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Lançamento não encontrado');
  END IF;

  IF v_lanc.locked_at IS NOT NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Lançamento bloqueado (dia fechado)');
  END IF;

  v_pedido := v_lanc.pedido_id;

  -- Sem pedido vinculado: é um lançamento avulso (custo etc) → remove normal.
  IF v_pedido IS NULL THEN
    DELETE FROM public.lancamentos_socios WHERE id = p_lancamento_id;
    RETURN jsonb_build_object('status', 'ok', 'revertido', false);
  END IF;

  -- 1) Pedido volta a PENDENTE. NUNCA apaga pedido / itens / estoque / comissões.
  UPDATE public.pedidos
     SET status_pagamento = 'pendente',
         data_pago        = NULL,
         recebido_por     = NULL
   WHERE id = v_pedido;

  -- 2) Remove só os lançamentos financeiros do pagamento desse pedido.
  DELETE FROM public.lancamentos_socios
   WHERE pedido_id = v_pedido
     AND tipo IN ('VENDA', 'PARCELA_VENDA', 'LUCRO');

  RETURN jsonb_build_object('status', 'ok', 'revertido', true, 'pedido_id', v_pedido);
END $$;

GRANT EXECUTE ON FUNCTION public.reverter_venda_para_pendente(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

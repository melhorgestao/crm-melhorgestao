
CREATE OR REPLACE FUNCTION public.deletar_venda_completa(p_lancamento_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_lanc record;
  v_pedido_id uuid;
  v_mov record;
BEGIN
  -- 1. Busca o lançamento
  SELECT * INTO v_lanc FROM public.lancamentos_socios WHERE id = p_lancamento_id;
  IF v_lanc IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Lançamento não encontrado');
  END IF;

  v_pedido_id := v_lanc.pedido_id;

  -- 2. Se tem pedido vinculado, faz cascade
  IF v_pedido_id IS NOT NULL THEN
    -- 2a. Restaura lotes e produtos a partir das movimentações de saída
    FOR v_mov IN
      SELECT produto_id, quantidade, lote_id
      FROM public.estoque_movimentacoes
      WHERE pedido_id = v_pedido_id AND tipo = 'saida'
    LOOP
      -- Restaura lote se existir
      IF v_mov.lote_id IS NOT NULL THEN
        UPDATE public.lotes
        SET quantidade_atual = quantidade_atual + v_mov.quantidade
        WHERE id = v_mov.lote_id;
      END IF;
      -- Restaura estoque_atual do produto
      UPDATE public.produtos
      SET estoque_atual = estoque_atual + v_mov.quantidade
      WHERE id = v_mov.produto_id;
    END LOOP;

    -- 2b. Deleta movimentações de estoque
    DELETE FROM public.estoque_movimentacoes WHERE pedido_id = v_pedido_id;

    -- 2c. Deleta comissões vinculadas
    DELETE FROM public.comissoes WHERE pedido_id = v_pedido_id;

    -- 2d. Deleta itens do pedido
    DELETE FROM public.pedido_itens WHERE pedido_id = v_pedido_id;

    -- 2e. Deleta outros lancamentos_socios vinculados ao mesmo pedido (exceto o atual)
    DELETE FROM public.lancamentos_socios WHERE pedido_id = v_pedido_id AND id != p_lancamento_id;

    -- 2f. Deleta registro financeiro relacionado
    DELETE FROM public.financeiro WHERE descricao ILIKE '%' || v_pedido_id::text || '%';

    -- 2g. Deleta o pedido
    DELETE FROM public.pedidos WHERE id = v_pedido_id;
  END IF;

  -- 3. Deleta o próprio lançamento
  DELETE FROM public.lancamentos_socios WHERE id = p_lancamento_id;

  -- 4. Atualiza snapshot de estoque
  PERFORM public.atualizar_estoque_snapshot();

  RETURN jsonb_build_object('status', 'ok', 'pedido_deletado', v_pedido_id);
END;
$$;

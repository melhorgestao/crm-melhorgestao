-- ============================================================================
-- finalizar_fechamento_contato: o botão X do card em Fechamento (Kanban)
-- finaliza o fechamento e RETROAGE o contato ao estado anterior.
--
-- Prioriza estado_antes_fechamento (carimbado pelo trigger ao entrar em
-- fechamento). Se estiver vazio, cai num fallback por canal/ja_comprou —
-- os MESMOS estados válidos e visíveis que o Kanban já usa (nunca inventa
-- status). Limpa data_em_fechamento.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.finalizar_fechamento_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_c    record;
  v_novo text;
BEGIN
  SELECT * INTO v_c FROM public.contatos WHERE id = p_contato_id;
  IF v_c.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;
  IF v_c.ultima_interacao <> 'em_fechamento' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não está em fechamento');
  END IF;

  -- estado anterior salvo, ou fallback (igual ao computeReturnState do front)
  v_novo := COALESCE(
    NULLIF(btrim(v_c.estado_antes_fechamento), ''),
    CASE
      WHEN v_c.ja_comprou THEN 'cliente'
      WHEN v_c.canal_atual IN ('REP', 'C-REP') THEN 'suporte'
      WHEN v_c.canal_atual = 'ADS' THEN 'wait_follow_up'
      ELSE 'ativacao_contatos'
    END
  );

  UPDATE public.contatos
     SET ultima_interacao        = v_novo,
         data_em_fechamento      = NULL,
         estado_antes_fechamento = NULL,
         -- se voltar pra fila de follow-up, garante o carimbo do relógio
         data_wait_follow_up     = CASE WHEN v_novo = 'wait_follow_up'
                                        THEN COALESCE(data_wait_follow_up, NOW())
                                        ELSE data_wait_follow_up END,
         updated_at              = NOW()
   WHERE id = p_contato_id;

  RETURN jsonb_build_object('ok', true, 'novo_estado', v_novo);
END $$;

GRANT EXECUTE ON FUNCTION public.finalizar_fechamento_contato(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

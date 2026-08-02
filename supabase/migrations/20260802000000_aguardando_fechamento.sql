-- Aguardando fechamento: clientes que estão esperando data de pagamento ou
-- esperando pagar um PIX. Comportamento = suporte (bot pausado, agente calado),
-- mas exibidos na coluna FECHAMENTO (não poluem a coluna SUPORTE, que é crítica).
--
-- Modelado como ultima_interacao='suporte' + flag fechamento_aguardando=true.
-- Assim o bot já fica naturalmente pausado (estado suporte) e não criamos
-- nenhum status novo em ultima_interacao (regra: nunca criar status novos).

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS fechamento_aguardando boolean NOT NULL DEFAULT false;

-- Move um contato para "aguardando fechamento".
-- Serve tanto para cards em SUPORTE quanto em EM_FECHAMENTO (ampulheta ⏳).
-- Preserva o estado anterior em estado_antes_suporte para o X (finalizar) restaurar.
CREATE OR REPLACE FUNCTION public.mover_para_aguardando_fechamento(
  p_contato_id uuid,
  p_motivo text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado_atual text;
  v_estado_anterior text;
BEGIN
  SELECT ultima_interacao, estado_antes_suporte
    INTO v_estado_atual, v_estado_anterior
    FROM public.contatos WHERE id = p_contato_id;

  IF v_estado_atual IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  -- Só sobrescreve estado_antes_suporte se ainda não estava em suporte,
  -- para não perder a origem real (ex.: em_fechamento -> aguardando).
  UPDATE public.contatos
     SET ultima_interacao       = 'suporte',
         fechamento_aguardando  = true,
         estado_antes_suporte   = CASE
                                    WHEN v_estado_atual = 'suporte' THEN estado_antes_suporte
                                    ELSE v_estado_atual
                                  END,
         data_suporte           = COALESCE(data_suporte, NOW()),
         suporte_motivo         = COALESCE(p_motivo, suporte_motivo, 'aguardando pagamento'),
         bot_pausado_ate        = NULL,
         updated_at             = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'aguardando_fechamento', v_estado_atual, 'suporte',
            jsonb_build_object('via', 'ui_kanban'));
  EXCEPTION WHEN undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true);
END $$;

GRANT EXECUTE ON FUNCTION public.mover_para_aguardando_fechamento(uuid, text) TO anon, authenticated, service_role;

-- finalizar_suporte_contato: agora também limpa a flag fechamento_aguardando,
-- para que o X no card de "aguardando fechamento" encerre de vez.
CREATE OR REPLACE FUNCTION public.finalizar_suporte_contato(
  p_contato_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado_atual text;
  v_estado_anterior text;
  v_ja_comprou boolean;
  v_canal text;
  v_destino text;
BEGIN
  SELECT ultima_interacao, estado_antes_suporte, ja_comprou, canal_atual
    INTO v_estado_atual, v_estado_anterior, v_ja_comprou, v_canal
    FROM public.contatos WHERE id = p_contato_id;

  IF v_estado_atual != 'suporte' THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'contato não está em suporte (estado atual: ' || COALESCE(v_estado_atual,'NULL') || ')');
  END IF;

  IF v_estado_anterior IS NOT NULL AND v_estado_anterior != 'suporte' THEN
    IF v_canal IN ('REP','C-REP') AND v_estado_anterior IN ('wait_follow_up','follow_up') THEN
      v_destino := NULL;
    ELSE
      v_destino := v_estado_anterior;
    END IF;
  ELSIF v_ja_comprou THEN
    v_destino := 'cliente';
  ELSIF v_canal IN ('REP','C-REP') THEN
    v_destino := NULL;
  ELSE
    v_destino := 'wait_follow_up';
  END IF;

  UPDATE public.contatos
     SET ultima_interacao         = v_destino,
         estado_antes_suporte     = NULL,
         fechamento_aguardando    = false,
         bot_pausado_ate          = NULL,
         data_suporte             = NULL,
         suporte_motivo           = NULL,
         data_wait_follow_up      = CASE WHEN v_destino = 'wait_follow_up' THEN NOW()
                                         ELSE data_wait_follow_up END,
         updated_at               = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'suporte_finalizado', 'suporte', v_destino,
            jsonb_build_object('via', 'ui_kanban'));
  EXCEPTION WHEN undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'destino', COALESCE(v_destino, 'NULL (fora do Kanban)'));
END $$;

GRANT EXECUTE ON FUNCTION public.finalizar_suporte_contato(uuid) TO anon, authenticated, service_role;

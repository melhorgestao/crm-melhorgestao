-- ============================================================================
-- Rastreia estado_antes_fechamento + RPC sair_fechamento_contato.
--
-- Para o botão [X] no card de FECHAMENTO do Kanban: ao clicar, o contato sai
-- de em_fechamento e VOLTA pro estado que tinha antes de entrar em fechamento.
--
-- iniciar_fechamento_contato já capturava v_estado_atual (o estado anterior)
-- pra logar — agora também persiste em contatos.estado_antes_fechamento.
-- ============================================================================

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS estado_antes_fechamento text;

COMMENT ON COLUMN public.contatos.estado_antes_fechamento IS
  'ultima_interacao registrada no momento em que o contato entrou em em_fechamento. Usada pelo botão X do Kanban pra restaurar.';

-- Recria iniciar_fechamento_contato salvando o estado anterior
CREATE OR REPLACE FUNCTION public.iniciar_fechamento_contato(
  p_contato_id uuid,
  p_produto_pretendido text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado_atual text;
BEGIN
  SELECT ultima_interacao INTO v_estado_atual
    FROM public.contatos WHERE id = p_contato_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  IF v_estado_atual IN ('em_fechamento','aguardando_pagamento') THEN
    RETURN jsonb_build_object('ok', true, 'idempotente', true,
                              'estado_atual', v_estado_atual);
  END IF;

  UPDATE public.contatos
     SET ultima_interacao        = 'em_fechamento',
         estado_antes_fechamento = v_estado_atual,
         data_em_fechamento      = now(),
         updated_at              = now()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'intent_fechamento', v_estado_atual, 'em_fechamento',
            jsonb_build_object('produto_pretendido', p_produto_pretendido));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'estado_para', 'em_fechamento');
END $$;

GRANT EXECUTE ON FUNCTION public.iniciar_fechamento_contato(uuid, text) TO service_role;

-- RPC pro botão X: sai de fechamento → restaura estado anterior
CREATE OR REPLACE FUNCTION public.sair_fechamento_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado_atual text;
  v_anterior     text;
  v_ja_comprou   boolean;
  v_canal        text;
  v_destino      text;
BEGIN
  SELECT ultima_interacao, estado_antes_fechamento, ja_comprou, canal_atual
    INTO v_estado_atual, v_anterior, v_ja_comprou, v_canal
    FROM public.contatos WHERE id = p_contato_id;

  IF v_estado_atual NOT IN ('em_fechamento','aguardando_pagamento') THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'contato não está em fechamento (estado: ' || COALESCE(v_estado_atual,'NULL') || ')');
  END IF;

  -- Destino: estado anterior salvo, senão fallback coerente
  IF v_anterior IS NOT NULL AND v_anterior NOT IN ('em_fechamento','aguardando_pagamento') THEN
    v_destino := v_anterior;
  ELSIF v_ja_comprou THEN
    v_destino := 'cliente';
  ELSIF v_canal IN ('REP','C-REP') THEN
    v_destino := 'suporte';
  ELSE
    v_destino := 'wait_follow_up';
  END IF;

  UPDATE public.contatos
     SET ultima_interacao        = v_destino,
         estado_antes_fechamento = NULL,
         data_em_fechamento      = NULL,
         data_wait_follow_up     = CASE WHEN v_destino = 'wait_follow_up' THEN NOW() ELSE data_wait_follow_up END,
         updated_at              = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'saiu_fechamento', v_estado_atual, v_destino,
            jsonb_build_object('via', 'ui_kanban'));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'destino', v_destino);
END $$;

GRANT EXECUTE ON FUNCTION public.sair_fechamento_contato(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

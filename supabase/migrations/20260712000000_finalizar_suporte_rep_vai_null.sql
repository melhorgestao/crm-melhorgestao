-- ============================================================================
-- finalizar_suporte_contato: REP/C-REP sem estado_antes_suporte → NULL
--
-- Antes:
--   REP/C-REP fallback era 'suporte' (mantém o card no Kanban pra sempre).
--   Comentário original: "atendimento humano contínuo nesses canais".
--   Mas isso é incompatível com a regra nova: REP/C-REP NÃO entram em
--   wait_follow_up/follow_up. Pra eles, o "estado dinâmico de lead" não
--   se aplica — devem sair do Kanban inteiro ao finalizar suporte.
--
-- Agora:
--   estado_antes_suporte (se existir e não for 'suporte') →  vai pra ele.
--   Senão, ja_comprou → 'cliente'.
--   Senão, REP/C-REP → NULL (some do Kanban).
--   Senão → 'wait_follow_up' (regra geral).
-- ============================================================================

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

  -- Decide destino
  IF v_estado_anterior IS NOT NULL AND v_estado_anterior != 'suporte' THEN
    -- REP/C-REP: se estado_antes_suporte era wait/follow_up (caso histórico),
    -- ignora e vai pra NULL — REP não pode ir pra esses estados.
    IF v_canal IN ('REP','C-REP') AND v_estado_anterior IN ('wait_follow_up','follow_up') THEN
      v_destino := NULL;
    ELSE
      v_destino := v_estado_anterior;
    END IF;
  ELSIF v_ja_comprou THEN
    v_destino := 'cliente';
  ELSIF v_canal IN ('REP','C-REP') THEN
    v_destino := NULL;  -- REP/C-REP sem histórico → fora do Kanban
  ELSE
    v_destino := 'wait_follow_up';
  END IF;

  UPDATE public.contatos
     SET ultima_interacao         = v_destino,
         estado_antes_suporte     = NULL,
         duvidas_consecutivas     = 0,
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

GRANT EXECUTE ON FUNCTION public.finalizar_suporte_contato(uuid)
  TO authenticated, anon, service_role;

-- ============================================================================
-- DROP contatos.duvidas_consecutivas.
--
-- Ninguém lê/gate essa coluna — só zera em vários lugares (código morto).
-- Ela estava sendo apontada como possível trava pra abertura de suporte
-- (executa_comando_dono, finalizar_suporte_contato, marcar_contato_suporte
-- fazem UPDATE incluindo duvidas_consecutivas=0). Remover a coluna evita
-- confusão futura e simplifica as funções.
--
-- Estratégia: recria as 4 funções que a referenciam SEM a coluna, depois
-- dropa a coluna. Todas as outras semânticas mantidas.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) executa_comando_dono (última versão vive em 20260719 — recria sem dv)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.executa_comando_dono(
  p_contato_id UUID,
  p_comando    TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acao TEXT;
  v_estado_para TEXT;
  v_ja_comprou BOOLEAN;
  v_estado_atual TEXT;
  v_estado_anterior TEXT;
  v_canal TEXT;
BEGIN
  SELECT ultima_interacao, ja_comprou, estado_antes_suporte, canal_atual
    INTO v_estado_atual, v_ja_comprou, v_estado_anterior, v_canal
    FROM contatos WHERE id = p_contato_id;

  CASE p_comando
    WHEN '/humano' THEN
      UPDATE contatos
         SET bot_pausado_ate      = NOW() + INTERVAL '999 years',
             estado_antes_suporte = CASE
               WHEN ultima_interacao = 'suporte' THEN estado_antes_suporte
               ELSE ultima_interacao
             END,
             ultima_interacao     = 'suporte',
             data_suporte         = CASE
               WHEN ultima_interacao = 'suporte' THEN data_suporte
               ELSE NOW()
             END,
             suporte_motivo       = COALESCE(suporte_motivo, 'humano_atendendo'),
             updated_at           = NOW()
       WHERE id = p_contato_id;
      v_estado_para := 'suporte';
      v_acao := 'bot pausado + movido pra suporte (humano atendendo)';

    WHEN '/parar' THEN
      UPDATE contatos SET bot_pausado_ate = NOW() + INTERVAL '24 hours', updated_at = NOW()
        WHERE id = p_contato_id;
      v_acao := 'bot pausado por 24h';

    WHEN '/voltar' THEN
      UPDATE contatos SET bot_pausado_ate = NULL, updated_at = NOW() WHERE id = p_contato_id;
      IF v_estado_atual = 'suporte' THEN
        IF v_estado_anterior IS NOT NULL AND v_estado_anterior != 'suporte' THEN
          v_estado_para := v_estado_anterior;
        ELSIF v_ja_comprou THEN
          v_estado_para := 'cliente';
        ELSE
          v_estado_para := 'wait_follow_up';
        END IF;
        UPDATE contatos
           SET ultima_interacao    = v_estado_para,
               estado_antes_suporte = NULL,
               data_suporte         = NULL,
               suporte_motivo       = NULL,
               data_wait_follow_up = CASE WHEN v_estado_para = 'wait_follow_up' THEN NOW()
                                          ELSE data_wait_follow_up END,
               updated_at           = NOW()
         WHERE id = p_contato_id;
        v_acao := 'bot reativado + saiu de suporte → ' || v_estado_para;
      ELSE
        v_acao := 'bot reativado';
      END IF;

    WHEN '/cliente' THEN
      UPDATE contatos SET ultima_interacao = 'cliente', updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'cliente'; v_acao := 'estado forçado: cliente';

    WHEN '/sumiu' THEN
      UPDATE contatos SET ultima_interacao = 'wait_follow_up',
        data_wait_follow_up = NOW(), updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'wait_follow_up'; v_acao := 'estado forçado: wait_follow_up';

    WHEN '/banir' THEN
      UPDATE contatos SET ultima_interacao = 'NUNCA_MAIS',
        data_nunca_mais = NOW(), updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'NUNCA_MAIS'; v_acao := 'banido: NUNCA_MAIS';

    WHEN '/voltar_inicio' THEN
      UPDATE contatos SET ultima_interacao = NULL,
        typebot_closing_session_id = NULL, updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := NULL; v_acao := 'estado limpo (sessão typebot resetada)';

    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'comando desconhecido: ' || p_comando);
  END CASE;

  RETURN jsonb_build_object('ok', true, 'comando', p_comando, 'acao', v_acao, 'estado_para', v_estado_para);
END $$;

GRANT EXECUTE ON FUNCTION public.executa_comando_dono(UUID, TEXT)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 2) finalizar_suporte_contato — recria sem duvidas_consecutivas
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 3) DROP a coluna. Se restou algum default constraint, o CASCADE remove.
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos DROP COLUMN IF EXISTS duvidas_consecutivas;

NOTIFY pgrst, 'reload schema';

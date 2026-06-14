-- ============================================================================
-- Suporte: rastreia estado anterior e cria RPC finalizar_suporte_contato
--
-- Mudança principal: ao ENTRAR em suporte, salva ultima_interacao anterior
-- em contatos.estado_antes_suporte. Ao SAIR (via /voltar ou botão UI),
-- restaura aquele estado exato em vez de adivinhar.
--
-- Cobre todos os estados origem: cliente, wait_follow_up, rmkt, follow_up,
-- em_fechamento, aguardando_pagamento, start, NUNCA_MAIS, NULL.
-- ============================================================================

-- 1) Coluna nova
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS estado_antes_suporte text;

COMMENT ON COLUMN public.contatos.estado_antes_suporte IS
  'ultima_interacao registrada no momento da escalação pra suporte. Usada para restaurar no /voltar ou botão Suporte Finalizado.';

-- 2) marcar_contato_suporte agora salva estado anterior
CREATE OR REPLACE FUNCTION public.marcar_contato_suporte(
  p_contato_id uuid,
  p_motivo     text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado_atual text;
BEGIN
  SELECT ultima_interacao INTO v_estado_atual
    FROM public.contatos WHERE id = p_contato_id;

  -- Só salva estado anterior se não estamos já em suporte (idempotente)
  UPDATE public.contatos
     SET estado_antes_suporte = CASE
           WHEN v_estado_atual = 'suporte' THEN estado_antes_suporte
           ELSE v_estado_atual
         END,
         ultima_interacao = 'suporte',
         data_suporte     = NOW(),
         suporte_motivo   = p_motivo,
         updated_at       = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'escalado_suporte', v_estado_atual, 'suporte',
            jsonb_build_object('motivo', p_motivo));
  EXCEPTION WHEN undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'escalado_em', NOW(),
                            'estado_anterior', v_estado_atual);
END $$;

GRANT EXECUTE ON FUNCTION public.marcar_contato_suporte(uuid, text)
  TO authenticated, anon, service_role;

-- 3) finalizar_suporte_contato — chamada pelo botão UI Kanban
--    Restaura estado anterior (ou fallback ja_comprou/canal se NULL)
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

  -- Decide destino: estado anterior > fallback ja_comprou/canal
  IF v_estado_anterior IS NOT NULL AND v_estado_anterior != 'suporte' THEN
    v_destino := v_estado_anterior;
  ELSIF v_ja_comprou THEN
    v_destino := 'cliente';
  ELSIF v_canal IN ('REP','C-REP') THEN
    v_destino := 'suporte';  -- mantém — atendimento humano contínuo nesses canais
  ELSE
    v_destino := 'wait_follow_up';
  END IF;

  UPDATE public.contatos
     SET ultima_interacao         = v_destino,
         estado_antes_suporte     = NULL,
         duvidas_consecutivas     = 0,
         bot_pausado_ate          = NULL,  -- garante bot reativo
         data_wait_follow_up      = CASE WHEN v_destino = 'wait_follow_up' THEN NOW()
                                         ELSE data_wait_follow_up END,
         updated_at               = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'suporte_finalizado', 'suporte', v_destino,
            jsonb_build_object('via', 'ui_kanban'));
  EXCEPTION WHEN undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'destino', v_destino);
END $$;

GRANT EXECUTE ON FUNCTION public.finalizar_suporte_contato(uuid)
  TO authenticated, anon, service_role;

-- 4) Atualiza /voltar pra usar estado_antes_suporte
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
      UPDATE contatos SET bot_pausado_ate = NOW() + INTERVAL '999 years', updated_at = NOW()
        WHERE id = p_contato_id;
      v_acao := 'bot pausado indefinidamente (humano atendendo)';

    WHEN '/parar' THEN
      UPDATE contatos SET bot_pausado_ate = NOW() + INTERVAL '24 hours', updated_at = NOW()
        WHERE id = p_contato_id;
      v_acao := 'bot pausado por 24h';

    WHEN '/voltar' THEN
      -- 1) reativa bot
      UPDATE contatos SET bot_pausado_ate = NULL, updated_at = NOW()
        WHERE id = p_contato_id;
      -- 2) se em suporte, restaura via estado_antes_suporte
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
               duvidas_consecutivas = 0,
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
        typebot_closing_session_id = NULL,
        updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := NULL; v_acao := 'estado limpo (sessão typebot resetada)';

    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'comando desconhecido: ' || p_comando);
  END CASE;

  RETURN jsonb_build_object('ok', true, 'comando', p_comando, 'acao', v_acao, 'estado_para', v_estado_para);
END $$;

GRANT EXECUTE ON FUNCTION public.executa_comando_dono(UUID, TEXT)
  TO authenticated, anon, service_role;

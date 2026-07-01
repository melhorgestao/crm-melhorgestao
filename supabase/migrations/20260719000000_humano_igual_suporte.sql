-- ============================================================================
-- Unifica "humano atendendo" ↔ "suporte":
--
-- REGRAS:
--   1) /humano no WhatsApp → pausa o bot INDEFINIDAMENTE + move contato pra
--      'suporte' (salvando estado anterior). Card aparece na coluna SUPORTE.
--   2) /voltar no WhatsApp → reativa bot + restaura estado_antes_suporte
--      (já era assim, mantido).
--   3) Botão "Suporte Realizado" no CRM já reativa bot e restaura estado
--      (já era assim, mantido).
--
-- Efeito: /humano ⇔ botão suporte aberto ; /voltar ⇔ suporte realizado.
--
-- O gate do router-process em suporte (não chamar agent) fica no código
-- da Edge Function — nada de SQL pra isso.
-- ============================================================================

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
      -- Pausa bot indefinidamente E move pra suporte (equivalência com o card
      -- de suporte no Kanban). Se já está em suporte, é idempotente.
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
               data_suporte         = NULL,
               suporte_motivo       = NULL,
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

NOTIFY pgrst, 'reload schema';

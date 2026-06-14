-- ============================================================================
-- /voltar agora faz 2 coisas:
--   1) Reativa bot (limpa bot_pausado_ate) — mantém comportamento atual
--   2) Se contato está em 'suporte', devolve pro estado anterior
--      (cliente se já_comprou, wait_follow_up se não)
--
-- Substitui só o branch WHEN '/voltar' THEN da executa_comando_dono.
-- Mantém todos os outros comandos (/humano, /parar, /cliente, /sumiu, /banir, etc).
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
BEGIN
  SELECT ultima_interacao, ja_comprou
    INTO v_estado_atual, v_ja_comprou
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
      -- 1) Reativa bot
      UPDATE contatos SET bot_pausado_ate = NULL, updated_at = NOW()
        WHERE id = p_contato_id;
      -- 2) Se está em suporte, devolve pro estado anterior
      IF v_estado_atual = 'suporte' THEN
        v_estado_para := CASE WHEN v_ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END;
        UPDATE contatos
           SET ultima_interacao    = v_estado_para,
               data_wait_follow_up = CASE WHEN v_estado_para = 'wait_follow_up' THEN NOW()
                                          ELSE data_wait_follow_up END,
               duvidas_consecutivas = 0,
               updated_at           = NOW()
         WHERE id = p_contato_id;
        v_acao := 'bot reativado + saiu de suporte → ' || v_estado_para;
      ELSE
        v_acao := 'bot reativado';
      END IF;

    WHEN '/cliente' THEN
      UPDATE contatos SET ultima_interacao = 'cliente', updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'cliente';
      v_acao := 'estado forçado: cliente';

    WHEN '/sumiu' THEN
      UPDATE contatos SET ultima_interacao = 'wait_follow_up',
        data_wait_follow_up = NOW(), updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'wait_follow_up';
      v_acao := 'estado forçado: wait_follow_up';

    WHEN '/banir' THEN
      UPDATE contatos SET ultima_interacao = 'NUNCA_MAIS',
        data_nunca_mais = NOW(), updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'NUNCA_MAIS';
      v_acao := 'banido: NUNCA_MAIS';

    WHEN '/voltar_inicio' THEN
      UPDATE contatos SET ultima_interacao = NULL,
        typebot_closing_session_id = NULL,
        updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := NULL;
      v_acao := 'estado limpo (sessão typebot resetada)';

    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'comando desconhecido: ' || p_comando);
  END CASE;

  RETURN jsonb_build_object(
    'ok', true,
    'comando', p_comando,
    'acao', v_acao,
    'estado_para', v_estado_para
  );
END $$;

GRANT EXECUTE ON FUNCTION public.executa_comando_dono(UUID, TEXT)
  TO authenticated, anon, service_role;

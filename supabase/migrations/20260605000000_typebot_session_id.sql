-- ============================================================================
-- Persistência de sessão Typebot CLOSING por contato
--
-- Problema: cada webhook Typebot cria sessão nova → cliente perde contexto
-- mid-CLOSING (digitou CEP mas bot esqueceu produto que escolheu).
--
-- Solução: sessionId vive no contato. Router decide /startChat (cria) vs
-- /continueChat (retoma) baseado em typebot_closing_session_id.
-- Cron limpa sessionId ao expirar em_fechamento (48h).
-- ============================================================================

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS typebot_closing_session_id TEXT,
  ADD COLUMN IF NOT EXISTS typebot_closing_session_em TIMESTAMPTZ;

COMMENT ON COLUMN public.contatos.typebot_closing_session_id IS
  'sessionId ativo do Typebot CLOSING. NULL = nenhum em curso. Router usa pra continueChat.';

-- Atualiza cron pra limpar sessionId quando em_fechamento expira
CREATE OR REPLACE FUNCTION public.processar_transicoes_estado_contato()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ativacao_timeout INTEGER;
  v_follow_up_timeout INTEGER;
  v_em_fechamento_timeout INTEGER;
  v_wait_expirado INTEGER;
BEGIN
  -- 1) Ativação sem resposta 3d → cliente (se ja_comprou) ou wait_follow_up
  UPDATE public.contatos
  SET ultima_interacao = CASE WHEN ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE WHEN NOT ja_comprou THEN NOW() ELSE data_wait_follow_up END,
      ativacao_consecutive_silenciosos = ativacao_consecutive_silenciosos + 1,
      updated_at = NOW()
  WHERE ultima_interacao = 'ativacao_contatos'
    AND data_ultimo_ativacao < NOW() - INTERVAL '3 days'
    AND ativacao_respondeu_em IS NULL;
  GET DIAGNOSTICS v_ativacao_timeout = ROW_COUNT;

  -- 2) Follow-up sem resposta 24h → wait_follow_up (pronto pra próxima tentativa)
  UPDATE public.contatos
  SET ultima_interacao = 'wait_follow_up',
      data_wait_follow_up = NOW(),
      updated_at = NOW()
  WHERE ultima_interacao = 'follow_up'
    AND data_ultimo_follow_up < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 3) wait_follow_up com 3 tentativas esgotadas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS',
      data_nunca_mais = NOW(),
      updated_at = NOW()
  WHERE ultima_interacao = 'wait_follow_up'
    AND follow_up_tentativas >= 3;
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 4) em_fechamento parado 48h → volta + LIMPA sessão Typebot morta
  UPDATE public.contatos
  SET ultima_interacao = CASE WHEN ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE WHEN NOT ja_comprou THEN NOW() ELSE data_wait_follow_up END,
      typebot_closing_session_id = NULL,
      typebot_closing_session_em = NULL,
      updated_at = NOW()
  WHERE ultima_interacao = 'em_fechamento'
    AND data_em_fechamento < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  RETURN jsonb_build_object(
    'ativacao_timeout', v_ativacao_timeout,
    'follow_up_timeout', v_follow_up_timeout,
    'tentativas_esgotadas', v_wait_expirado,
    'em_fechamento_timeout', v_em_fechamento_timeout
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.processar_transicoes_estado_contato()
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- process_batch_mensagens respeita suporte/pausa feita DURANTE o debounce.
--
-- BUG: o dono abre a conversa, o lead mandou uma msg (nos 12s de debounce) e
-- o dono digita "/humano". O comando marca suporte + pausa NA HORA, mas quando
-- o debounce termina, process_batch_mensagens só checava "sou a msg mais
-- recente?" — não re-lia o estado. Resultado: o agente processava a msg antiga,
-- RESPONDIA e sobrescrevia ultima_interacao='suporte' de volta pra 'start',
-- tirando o card de suporte e dando a impressão de que /humano "não funcionou".
--
-- FIX: após confirmar que é a msg mais recente, re-checa o estado ATUAL. Se o
-- contato foi pra 'suporte' ou está com bot_pausado_ate no futuro (/humano,
-- /parar), retorna devo_processar=false SEM marcar as msgs como processadas
-- (ficam no buffer, igual ao caminho "bot pausado" — reprocessam quando /voltar
-- reativar). Não toca em /start (comando não passa por process_batch).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.process_batch_mensagens(
  p_contato_id UUID,
  p_minha_recebida_em TIMESTAMPTZ
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_latest TIMESTAMPTZ;
  v_concat TEXT;
  v_count INTEGER;
  v_pausado_ate TIMESTAMPTZ;
  v_estado TEXT;
BEGIN
  -- Check qual a msg mais recente unprocessed
  SELECT MAX(recebida_em) INTO v_latest
  FROM public.mensagens_buffer
  WHERE contato_id = p_contato_id
    AND processada_em IS NULL
    AND direcao = 'in';

  -- Se outra exec é mais recente que eu, eu saio
  IF v_latest IS NULL OR v_latest > p_minha_recebida_em THEN
    RETURN jsonb_build_object('devo_processar', false);
  END IF;

  -- Re-checa estado ATUAL: se /humano ou /parar entraram durante o debounce,
  -- NÃO processa (senão o agente responde e sobrescreve suporte→start).
  -- Deixa as msgs no buffer (não marca processada_em) pra reprocessarem no /voltar.
  SELECT ultima_interacao, bot_pausado_ate
    INTO v_estado, v_pausado_ate
    FROM public.contatos WHERE id = p_contato_id;

  IF v_estado = 'suporte'
     OR (v_pausado_ate IS NOT NULL AND v_pausado_ate > NOW()) THEN
    RETURN jsonb_build_object(
      'devo_processar', false,
      'motivo', 'pausado_ou_suporte_no_debounce'
    );
  END IF;

  -- Eu sou a mais recente, concat tudo
  SELECT
    STRING_AGG(mensagem, E'\n' ORDER BY recebida_em ASC),
    COUNT(*)::INTEGER
  INTO v_concat, v_count
  FROM public.mensagens_buffer
  WHERE contato_id = p_contato_id
    AND processada_em IS NULL
    AND direcao = 'in';

  -- Marca todas como processadas
  UPDATE public.mensagens_buffer
  SET processada_em = NOW()
  WHERE contato_id = p_contato_id
    AND processada_em IS NULL
    AND direcao = 'in';

  RETURN jsonb_build_object(
    'devo_processar', true,
    'mensagens_concat', v_concat,
    'count_msgs', v_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_batch_mensagens(UUID, TIMESTAMPTZ)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Infraestrutura do Router n8n
--
-- Cria:
--   1. contatos.bot_pausado_ate (controle de pausa via comandos do dono)
--   2. mensagens_buffer (debounce + audit de I/O)
--   3. eventos_contato (auditoria state machine + LLM cost + transições)
--   4. RPC get_or_create_contato (Router cria contato novo se necessário)
--   5. RPC process_batch_mensagens (debounce atômico + concat)
--   6. RPC executa_comando_dono (processa /humano /parar etc)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Coluna bot_pausado_ate
-- ----------------------------------------------------------------------------

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS bot_pausado_ate TIMESTAMPTZ;

COMMENT ON COLUMN public.contatos.bot_pausado_ate IS
  'NULL = bot ativo. > NOW() = bot ignorando msgs (dono atende via Chatwoot). Set via comandos /humano /parar.';

CREATE INDEX IF NOT EXISTS idx_contatos_bot_pausado
  ON public.contatos(bot_pausado_ate)
  WHERE bot_pausado_ate IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. Tabela mensagens_buffer
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.mensagens_buffer (
  id BIGSERIAL PRIMARY KEY,
  contato_id UUID REFERENCES public.contatos(id) ON DELETE CASCADE,
  telefone TEXT NOT NULL,
  mensagem TEXT,
  tipo TEXT NOT NULL DEFAULT 'text',
  direcao TEXT NOT NULL CHECK (direcao IN ('in', 'out')),
  instancia_id UUID REFERENCES public.instancias(id),
  metadata JSONB,
  recebida_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processada_em TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_msg_buffer_contato_unprocessed
  ON public.mensagens_buffer(contato_id, recebida_em)
  WHERE processada_em IS NULL;

CREATE INDEX IF NOT EXISTS idx_msg_buffer_telefone_recent
  ON public.mensagens_buffer(telefone, recebida_em DESC);

CREATE INDEX IF NOT EXISTS idx_msg_buffer_contato_history
  ON public.mensagens_buffer(contato_id, recebida_em DESC);

COMMENT ON TABLE public.mensagens_buffer IS
  'Buffer de mensagens recebidas/enviadas. Debounce do Router lê unprocessed. Histórico fica permanente.';

-- ----------------------------------------------------------------------------
-- 3. Tabela eventos_contato (auditoria)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.eventos_contato (
  id BIGSERIAL PRIMARY KEY,
  contato_id UUID REFERENCES public.contatos(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL,
  estado_de TEXT,
  estado_para TEXT,
  canal TEXT,
  instancia_id UUID REFERENCES public.instancias(id),
  custo_estimado_brl NUMERIC(10, 6),
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_eventos_contato_contato
  ON public.eventos_contato(contato_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_eventos_contato_tipo
  ON public.eventos_contato(tipo, created_at DESC);

COMMENT ON TABLE public.eventos_contato IS
  'Audit log de tudo que acontece com um contato. Tipos: state_change, llm_call, evolution_send, command_dono, error, etc.';

-- ----------------------------------------------------------------------------
-- 4. RPC get_or_create_contato
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_or_create_contato(
  p_telefone TEXT,
  p_nome TEXT DEFAULT NULL,
  p_instancia_id UUID DEFAULT NULL,
  p_canal_origem TEXT DEFAULT 'BASE',
  p_metadata JSONB DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized TEXT;
  v_contato_id UUID;
  v_was_created BOOLEAN := false;
  v_result jsonb;
BEGIN
  -- Normaliza telefone (só dígitos)
  v_normalized := REGEXP_REPLACE(p_telefone, '\D', '', 'g');

  -- Try find existing contato (match em dígitos normalizados)
  SELECT c.id INTO v_contato_id
  FROM public.contatos c
  WHERE REGEXP_REPLACE(COALESCE(c.telefone, ''), '\D', '', 'g') = v_normalized
  LIMIT 1;

  -- If not found, create
  IF v_contato_id IS NULL THEN
    INSERT INTO public.contatos (
      nome, telefone, canal_origem, canal_atual,
      instancia_id, created_at, updated_at
    )
    VALUES (
      COALESCE(NULLIF(TRIM(p_nome), ''), v_normalized),
      v_normalized,
      p_canal_origem,
      p_canal_origem,
      p_instancia_id,
      NOW(),
      NOW()
    )
    RETURNING contatos.id INTO v_contato_id;
    v_was_created := true;
  END IF;

  -- Build result com tudo que o Router precisa pra decidir
  SELECT jsonb_build_object(
    'id', c.id,
    'nome', c.nome,
    'telefone', c.telefone,
    'ultima_interacao', c.ultima_interacao,
    'ja_comprou', c.ja_comprou,
    'bot_pausado_ate', c.bot_pausado_ate,
    'typebot_closing_session_id', c.typebot_closing_session_id,
    'canal_origem', c.canal_origem,
    'canal_atual', c.canal_atual,
    'instancia_id', c.instancia_id,
    'was_created', v_was_created
  )
  INTO v_result
  FROM public.contatos c
  WHERE c.id = v_contato_id;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 5. RPC process_batch_mensagens
-- ----------------------------------------------------------------------------

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

-- ----------------------------------------------------------------------------
-- 6. RPC executa_comando_dono
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.executa_comando_dono(
  p_contato_id UUID,
  p_comando TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_acao TEXT;
  v_estado_de TEXT;
  v_estado_para TEXT;
  v_contato_data jsonb;
BEGIN
  -- Captura estado anterior pra log
  SELECT ultima_interacao INTO v_estado_de FROM contatos WHERE id = p_contato_id;

  CASE LOWER(TRIM(p_comando))
    WHEN '/humano' THEN
      UPDATE contatos SET bot_pausado_ate = NOW() + INTERVAL '999 years', updated_at = NOW()
        WHERE id = p_contato_id;
      v_acao := 'bot pausado indefinidamente (humano atendendo)';

    WHEN '/parar' THEN
      UPDATE contatos SET bot_pausado_ate = NOW() + INTERVAL '24 hours', updated_at = NOW()
        WHERE id = p_contato_id;
      v_acao := 'bot pausado por 24h';

    WHEN '/voltar' THEN
      UPDATE contatos SET bot_pausado_ate = NULL, updated_at = NOW()
        WHERE id = p_contato_id;
      v_acao := 'bot reativado';

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
      v_acao := 'reset: bot apresenta cardápio novamente';

    WHEN '/info' THEN
      -- /info não muda nada, só retorna dados
      v_acao := 'info request';

    ELSE
      RETURN jsonb_build_object(
        'success', false,
        'erro', 'comando desconhecido: ' || p_comando
      );
  END CASE;

  -- Log evento
  INSERT INTO eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
  VALUES (p_contato_id, 'command_dono', v_estado_de, v_estado_para,
    jsonb_build_object('comando', p_comando, 'acao', v_acao));

  -- Retorna estado atualizado pro Router enviar via Telegram
  SELECT jsonb_build_object(
    'id', c.id, 'nome', c.nome, 'telefone', c.telefone,
    'ultima_interacao', c.ultima_interacao,
    'ja_comprou', c.ja_comprou,
    'bot_pausado_ate', c.bot_pausado_ate,
    'ultima_venda_em', c.ultima_venda_em,
    'data_cliente', c.data_cliente
  ) INTO v_contato_data
  FROM contatos c WHERE c.id = p_contato_id;

  RETURN jsonb_build_object(
    'success', true,
    'comando', p_comando,
    'acao', v_acao,
    'contato', v_contato_data
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.executa_comando_dono(UUID, TEXT)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- MODO MUDO — a trava estava no lugar errado. URGENTE.
--
-- DIAGNÓSTICO: o workflow n8n ativo NÃO chama o router-ingest para mensagem
-- normal de lead. Ele só usa o router-ingest para comandos "/". O caminho do
-- lead é todo dele:
--
--   Webhook → GET/CREATE Contato → SAVE Buffer (in) → "Bot ativo?"
--     → WAIT 12s → PROCESS BATCH → "Devo processar?" → AGENT_START
--     → EVOLUTION SEND
--
-- Ou seja: as checagens de agente_mudo que eu pus no router-ingest e no
-- router-process nunca eram executadas nesse fluxo. O bot continuava
-- respondendo — a mensagem saía pela Evolution (por isso aparece no Chatwoot,
-- que espelha o envio) e só era barrada depois, pela restrição do WhatsApp.
-- Cada uma dessas tentativas é risco de agravar a restrição do número.
--
-- CORREÇÃO: travar nos dois RPCs que ESSE workflow obrigatoriamente atravessa,
-- então vale sem reimportar/alterar nada no n8n:
--
--   1) get_or_create_contato  → 1ª porta. Se a instância está muda, devolve
--      bot_pausado_ate no futuro. O nó "Bot ativo?" reprova e o fluxo vai pra
--      "Respond: bot pausado" — antes do WAIT, antes do agente, antes do envio.
--      NADA é gravado no contato: só o JSON de retorno é sintetizado, a coluna
--      bot_pausado_ate real continua intacta (desligar o mudo volta ao normal).
--
--   2) process_batch_mensagens → 2ª porta (cinto). Se alguém alterar o IF ou
--      chamar direto, devolve devo_processar=false e as mensagens ficam NO
--      BUFFER (não marca processada_em) — quando o mudo sair, reprocessam.
--
-- Some-se à 20260825 (campanhas) e às travas do router-ingest/router-process:
-- agora todo caminho de envio passa por uma checagem de agente_mudo.
-- ============================================================================

-- ── 0) helpers (idempotente: roda mesmo se a 20260824/20260825 não passaram) ─
CREATE OR REPLACE FUNCTION public.instancia_esta_muda(p_instancia_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT i.agente_mudo FROM public.instancias i WHERE i.id = p_instancia_id), false)
$$;

CREATE OR REPLACE FUNCTION public.nome_e_placeholder(p_nome text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_nome IS NULL
      OR btrim(p_nome) = ''
      OR btrim(p_nome) ~ '^\+?[0-9][0-9 ()+.-]*$'
$$;

GRANT EXECUTE ON FUNCTION public.instancia_esta_muda(uuid) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.nome_e_placeholder(text)  TO authenticated, anon, service_role;

-- ── 1) get_or_create_contato: mesma lógica da 20260824 + trava de modo mudo ──
CREATE OR REPLACE FUNCTION public.get_or_create_contato(
  p_telefone     TEXT,
  p_nome         TEXT DEFAULT NULL,
  p_instancia_id UUID DEFAULT NULL,
  p_canal_origem TEXT DEFAULT 'BASE',
  p_metadata     JSONB DEFAULT NULL,
  p_mensagem     TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized  TEXT;
  v_contato_id  UUID;
  v_was_created BOOLEAN := false;
  v_result      jsonb;
  v_is_ads      BOOLEAN := false;
  v_msg         TEXT;
  v_nome_in     TEXT;
  v_mudo        BOOLEAN := false;
BEGIN
  v_normalized := public.normalize_telefone_br(p_telefone);
  IF v_normalized IS NULL OR length(v_normalized) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'telefone inválido');
  END IF;

  -- nome recebido só vale se NÃO for um telefone disfarçado
  v_nome_in := NULLIF(TRIM(COALESCE(p_nome, '')), '');
  IF public.nome_e_placeholder(v_nome_in) THEN
    v_nome_in := NULL;
  END IF;

  SELECT c.id INTO v_contato_id
  FROM public.contatos c
  WHERE c.telefone IS NOT NULL
    AND public.telefone_br_match(c.telefone, p_telefone)
  ORDER BY c.created_at ASC
  LIMIT 1;

  -- ADS por: canal explícito (ctwa detectado no router) OU metadata com
  -- ctwa_source_id OU texto típico de clique em anúncio (LIKE, não igualdade).
  v_msg := LOWER(TRIM(COALESCE(p_mensagem, '')));
  IF p_canal_origem = 'ADS'
     OR COALESCE(p_metadata->>'ctwa_source_id', '') <> ''
     OR COALESCE(p_metadata->>'ctwa_source_url', '') <> ''
     OR v_msg LIKE '%saber mais%'
     OR v_msg LIKE '%vi o an%ncio%'
     OR v_msg LIKE '%vim pelo an%ncio%'
     OR v_msg LIKE '%vi seu an%ncio%'
     OR v_msg LIKE '%vi um an%ncio%'
     OR v_msg LIKE '%pelo an%ncio%'
     OR v_msg LIKE '%do an%ncio%'
  THEN
    v_is_ads := true;
  END IF;

  IF v_contato_id IS NULL THEN
    BEGIN
      INSERT INTO public.contatos (
        nome, telefone, canal_origem, canal_atual,
        instancia_id, ultima_interacao, created_at, updated_at
      )
      VALUES (
        COALESCE(v_nome_in, v_normalized),   -- sem nome real ainda → placeholder
        v_normalized,
        CASE WHEN v_is_ads THEN 'ADS' ELSE p_canal_origem END,
        CASE WHEN v_is_ads THEN 'ADS' ELSE p_canal_origem END,
        p_instancia_id,
        'start',
        NOW(),
        NOW()
      )
      RETURNING contatos.id INTO v_contato_id;
      v_was_created := true;
    EXCEPTION WHEN unique_violation THEN
      SELECT c.id INTO v_contato_id
      FROM public.contatos c
      WHERE c.telefone IS NOT NULL
        AND public.telefone_canonico_br(c.telefone) = public.telefone_canonico_br(v_normalized)
      ORDER BY c.created_at ASC
      LIMIT 1;
    END;
  END IF;

  IF NOT v_was_created AND v_contato_id IS NOT NULL THEN
    UPDATE public.contatos
    SET ultima_interacao = COALESCE(ultima_interacao, 'start'),
        canal_origem     = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_origem END,
        canal_atual      = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_atual END,
        instancia_id     = COALESCE(p_instancia_id, instancia_id),
        telefone         = v_normalized,
        -- nome ainda é placeholder (NULL/vazio/telefone em QUALQUER formato)
        -- e chegou pushName real → grava o nome de verdade
        nome             = CASE
          WHEN v_nome_in IS NOT NULL AND public.nome_e_placeholder(nome)
          THEN v_nome_in
          ELSE nome
        END,
        updated_at       = NOW()
    WHERE id = v_contato_id;
  END IF;

  SELECT jsonb_build_object(
    'id',               c.id,
    'nome',             c.nome,
    'telefone',         c.telefone,
    'ultima_interacao', c.ultima_interacao,
    'ja_comprou',       c.ja_comprou,
    'bot_pausado_ate',  c.bot_pausado_ate,
    'canal_origem',     c.canal_origem,
    'canal_atual',      c.canal_atual,
    'instancia_id',     c.instancia_id,
    'was_created',      v_was_created
  ) INTO v_result
  FROM public.contatos c
  WHERE c.id = v_contato_id;

  -- MODO MUDO: o contato foi salvo normalmente (é o objetivo do modo), mas o
  -- retorno diz "bot pausado" pra o workflow não seguir pro agente/envio.
  -- Sintético: nada disso é gravado na tabela.
  v_mudo := public.instancia_esta_muda(
              COALESCE(p_instancia_id, (SELECT instancia_id FROM public.contatos WHERE id = v_contato_id))
            );
  IF v_mudo THEN
    v_result := v_result
      || jsonb_build_object(
           'agente_mudo',     true,
           'motivo',          'agente_mudo',
           'bot_pausado_ate', (NOW() + INTERVAL '100 years')
         );
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB, TEXT)
  TO authenticated, anon, service_role;

-- ── 2) process_batch_mensagens: cinto, após o debounce ──────────────────────
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
  v_latest      TIMESTAMPTZ;
  v_concat      TEXT;
  v_count       INTEGER;
  v_pausado_ate TIMESTAMPTZ;
  v_estado      TEXT;
  v_inst        UUID;
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
  SELECT ultima_interacao, bot_pausado_ate, instancia_id
    INTO v_estado, v_pausado_ate, v_inst
    FROM public.contatos WHERE id = p_contato_id;

  -- MODO MUDO: mesma regra do pausado — não processa e NÃO marca as mensagens
  -- como processadas, então nada se perde: quando o mudo sair, reprocessam.
  IF public.instancia_esta_muda(v_inst) THEN
    RETURN jsonb_build_object(
      'devo_processar', false,
      'motivo', 'agente_mudo'
    );
  END IF;

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

-- conferência
DO $$
DECLARE r record; v_tem boolean := false;
BEGIN
  FOR r IN SELECT nome FROM public.instancias WHERE agente_mudo LOOP
    v_tem := true;
    RAISE NOTICE 'MODO MUDO ativo: instancia % — nenhum envio sai por ela (lead, comando, campanha).', r.nome;
  END LOOP;
  IF NOT v_tem THEN
    RAISE NOTICE 'Nenhuma instancia em modo mudo no momento.';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- 1) FIX: get_or_create_contato sempre atualiza instancia_id se vier valor
-- 2) BACKFILL: contatos sem instancia_id pegam da última mensagem no buffer
-- 3) Recria executa_comando_dono sem referência a typebot_closing_session_id
-- 4) DROP COLUMN typebot_closing_session_id, typebot_closing_session_em
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) get_or_create_contato — sempre atualiza instancia_id quando vem valor
-- ---------------------------------------------------------------------------
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
BEGIN
  v_normalized := REGEXP_REPLACE(p_telefone, '\D', '', 'g');

  SELECT c.id INTO v_contato_id
  FROM public.contatos c
  WHERE REGEXP_REPLACE(COALESCE(c.telefone, ''), '\D', '', 'g') = v_normalized
  LIMIT 1;

  IF p_canal_origem = 'ADS' OR (
    p_mensagem IS NOT NULL AND
    LOWER(TRIM(p_mensagem)) IN ('saber mais', 'quero saber mais', 'quero saber mais!', 'saber mais!')
  ) THEN
    v_is_ads := true;
  END IF;

  IF v_contato_id IS NULL THEN
    INSERT INTO public.contatos (
      nome, telefone, canal_origem, canal_atual,
      instancia_id, ultima_interacao, created_at, updated_at
    )
    VALUES (
      COALESCE(NULLIF(TRIM(p_nome), ''), v_normalized),
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

  ELSE
    -- CONTATO EXISTENTE — sempre tenta atualizar instancia_id se veio um valor
    -- (COALESCE preserva o já cadastrado se p_instancia_id vier NULL)
    UPDATE public.contatos
    SET ultima_interacao = COALESCE(ultima_interacao, 'start'),
        canal_origem     = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_origem END,
        canal_atual      = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_atual END,
        instancia_id     = COALESCE(p_instancia_id, instancia_id),
        updated_at       = NOW()
    WHERE id = v_contato_id;
  END IF;

  -- Retorno (sem typebot_closing_session_id, já que vamos dropar)
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

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB, TEXT)
  TO authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- 2) BACKFILL: pega instancia_id da última msg do buffer pra contatos órfãos
-- ---------------------------------------------------------------------------
UPDATE public.contatos c
SET instancia_id = src.instancia_id,
    updated_at   = NOW()
FROM (
  SELECT DISTINCT ON (mb.contato_id) mb.contato_id, mb.instancia_id
    FROM public.mensagens_buffer mb
   WHERE mb.instancia_id IS NOT NULL
   ORDER BY mb.contato_id, mb.recebida_em DESC
) src
WHERE c.id = src.contato_id
  AND c.instancia_id IS NULL;

-- ---------------------------------------------------------------------------
-- 3) executa_comando_dono — sem typebot_closing_session_id
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.executa_comando_dono(
  p_contato_id UUID,
  p_comando    TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acao            TEXT;
  v_estado_para     TEXT;
  v_ja_comprou      BOOLEAN;
  v_estado_atual    TEXT;
  v_estado_anterior TEXT;
  v_canal           TEXT;
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
      UPDATE contatos SET bot_pausado_ate = NULL, updated_at = NOW()
        WHERE id = p_contato_id;
      IF v_estado_atual = 'suporte' THEN
        IF v_estado_anterior IS NOT NULL AND v_estado_anterior != 'suporte' THEN
          v_estado_para := v_estado_anterior;
        ELSIF v_ja_comprou THEN
          v_estado_para := 'cliente';
        ELSE
          v_estado_para := 'wait_follow_up';
        END IF;
        UPDATE contatos
           SET ultima_interacao     = v_estado_para,
               estado_antes_suporte = NULL,
               duvidas_consecutivas = 0,
               data_wait_follow_up  = CASE WHEN v_estado_para = 'wait_follow_up' THEN NOW()
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
        updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := NULL; v_acao := 'estado limpo';

    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'comando desconhecido: ' || p_comando);
  END CASE;

  RETURN jsonb_build_object('ok', true, 'comando', p_comando, 'acao', v_acao, 'estado_para', v_estado_para);
END $$;

GRANT EXECUTE ON FUNCTION public.executa_comando_dono(UUID, TEXT)
  TO authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- 4) DROP COLUMNS typebot
-- ---------------------------------------------------------------------------
ALTER TABLE public.contatos DROP COLUMN IF EXISTS typebot_closing_session_id;
ALTER TABLE public.contatos DROP COLUMN IF EXISTS typebot_closing_session_em;

NOTIFY pgrst, 'reload schema';

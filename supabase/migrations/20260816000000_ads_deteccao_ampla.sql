-- ============================================================================
-- Detecção de ADS mais ampla no get_or_create_contato.
--
-- CONTEXTO: leads de anúncio estavam sendo salvos como BASE. Causa principal
-- (corrigida no router/edge): o ctwa era lido em message.messageContextInfo,
-- que guarda deviceListMetadata — o contexto do anúncio vive no contextInfo
-- de cada tipo de mensagem (externalAdReply / ctwaContext).
--
-- ESTA MIGRATION cobre a 2ª camada: a detecção por TEXTO usava igualdade
-- exata (IN ('saber mais', ...)), então "Quero saber mais sobre o óleo" ou
-- "vim pelo anúncio" NÃO casavam e caíam em BASE.
-- Agora usa LIKE nos padrões típicos de clique em anúncio.
--
-- Mantém tudo o mais igual (dedup por telefone, nome placeholder que se
-- corrige com o pushName real, etc).
-- ============================================================================

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
BEGIN
  v_normalized := public.normalize_telefone_br(p_telefone);
  IF v_normalized IS NULL OR length(v_normalized) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'telefone inválido');
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
        -- nome placeholder (NULL / = telefone) + pushName real chegou → atualiza
        nome             = CASE
          WHEN NULLIF(TRIM(p_nome), '') IS NOT NULL
           AND (nome IS NULL OR nome = telefone OR nome = v_normalized)
          THEN TRIM(p_nome)
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

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB, TEXT)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

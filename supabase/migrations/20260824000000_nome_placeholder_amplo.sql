-- ============================================================================
-- Nome do lead: auto-cura do placeholder ficou ampla demais restrita.
--
-- PROBLEMA: quando o pushName não vem (comando fromMe, ou evento sem pushName)
-- o contato nasce com o TELEFONE no lugar do nome. Isso é aceitável só porque
-- o get_or_create troca pelo nome real quando o lead escreve — mas a checagem
-- de "é placeholder?" era literal:
--     nome IS NULL OR nome = telefone OR nome = v_normalized
-- ou seja, só curava se a string batesse EXATAMENTE. Se o nome tivesse sido
-- gravado em outro formato ("5545991082763", "+55 45 99108-2763", "45 99108
-- 2763"), a comparação falhava e o número ficava lá pra sempre.
--
-- AGORA: qualquer nome composto só de dígitos/pontuação de telefone conta como
-- placeholder e é substituído pelo pushName real assim que ele aparecer —
-- inclusive nos contatos que já estão gravados errado hoje.
-- (contatos.nome é NOT NULL, então o placeholder continua sendo o telefone;
--  a diferença é que agora ele SEMPRE cura, em qualquer formato gravado.)
--
-- Do lado do router, o nome agora é buscado no store da Evolution
-- (findContacts/fetchProfile/whatsappNumbers) antes de cair no placeholder.
-- ============================================================================

-- helper: "esse nome é na verdade um telefone?"
CREATE OR REPLACE FUNCTION public.nome_e_placeholder(p_nome text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_nome IS NULL
      OR btrim(p_nome) = ''
      OR btrim(p_nome) ~ '^\+?[0-9][0-9 ()+.-]*$'
$$;

COMMENT ON FUNCTION public.nome_e_placeholder(text) IS
  'true quando o nome do contato é só o telefone (placeholder) e pode ser substituído pelo pushName real.';

-- ── get_or_create_contato: mesma lógica de ADS da 20260816, só o nome muda ──
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

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB, TEXT)
  TO authenticated, anon, service_role;

-- ── salvar_contato_se_novo (/saveads, /savebase): mesma regra de nome ────────
CREATE OR REPLACE FUNCTION public.salvar_contato_se_novo(
  p_telefone     text,
  p_nome         text,
  p_instancia_id uuid,
  p_canal        text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm  text;
  v_id    uuid;
  v_nome  text;
BEGIN
  v_norm := public.normalize_telefone_br(p_telefone);
  IF v_norm IS NULL OR length(v_norm) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'telefone inválido');
  END IF;

  v_nome := NULLIF(TRIM(COALESCE(p_nome, '')), '');
  IF public.nome_e_placeholder(v_nome) THEN
    v_nome := NULL;   -- telefone disfarçado de nome não conta como nome
  END IF;

  SELECT c.id INTO v_id
  FROM public.contatos c
  WHERE c.telefone IS NOT NULL
    AND public.telefone_br_match(c.telefone, p_telefone)
  ORDER BY c.created_at ASC
  LIMIT 1;

  -- contato já existe → comando NÃO surte efeito nenhum (regra do dono),
  -- exceto preencher o nome se ele ainda for placeholder.
  IF v_id IS NOT NULL THEN
    IF v_nome IS NOT NULL THEN
      UPDATE public.contatos
         SET nome = v_nome, updated_at = NOW()
       WHERE id = v_id AND public.nome_e_placeholder(nome);
    END IF;
    RETURN jsonb_build_object('ok', true, 'ja_existe', true, 'contato_id', v_id);
  END IF;

  BEGIN
    INSERT INTO public.contatos (
      nome, telefone, canal_origem, canal_atual,
      instancia_id, ultima_interacao, created_at, updated_at
    ) VALUES (
      COALESCE(v_nome, v_norm), v_norm, p_canal, p_canal,
      p_instancia_id, 'start', NOW(), NOW()
    )
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    SELECT id INTO v_id FROM public.contatos
     WHERE public.telefone_canonico_br(telefone) = public.telefone_canonico_br(v_norm)
     ORDER BY created_at ASC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'ja_existe', true, 'contato_id', v_id);
  END;

  RETURN jsonb_build_object('ok', true, 'ja_existe', false, 'contato_id', v_id, 'canal', p_canal);
END;
$$;

GRANT EXECUTE ON FUNCTION public.salvar_contato_se_novo(text, text, uuid, text)
  TO authenticated, anon, service_role;

-- diagnóstico: quantos contatos ainda estão com o telefone no lugar do nome.
-- Não mexe em nada — todos esses passam a curar sozinhos na próxima mensagem
-- do lead (ou já no próximo /saveads, que agora busca o nome na Evolution).
DO $$
DECLARE v_qtd int;
BEGIN
  SELECT count(*) INTO v_qtd FROM public.contatos WHERE public.nome_e_placeholder(nome);
  RAISE NOTICE 'Contatos com nome = telefone (curam na proxima mensagem): %', v_qtd;
END $$;

NOTIFY pgrst, 'reload schema';

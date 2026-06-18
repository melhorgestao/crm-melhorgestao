-- ============================================================================
-- Normalização de telefone BR para evitar contatos duplicados.
--
-- Problema: mesmo número salvo como (11) 99988-7766, 11999887766, 5511999887766
-- ou com/sem 9º dígito móvel não era reconhecido pelo get_or_create_contato.
--
-- Versão defensiva: DROP IF EXISTS antes de cada CREATE pra evitar
-- conflito de assinatura. Backfill com EXCEPTION handler.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Helpers de normalização
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_telefone_br(p_telefone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  d TEXT;
BEGIN
  d := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  IF d IS NULL OR d = '' THEN
    RETURN NULL;
  END IF;
  -- Remove código do país 55 se vier prefixado (12 ou 13 dígitos)
  IF length(d) IN (12, 13) AND d LIKE '55%' THEN
    d := substring(d from 3);
  END IF;
  RETURN d;
END;
$$;

CREATE OR REPLACE FUNCTION public.telefone_br_variants(p_telefone TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v    TEXT := public.normalize_telefone_br(p_telefone);
  vars TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF v IS NULL OR length(v) < 10 THEN
    RETURN ARRAY[v]::TEXT[];
  END IF;

  -- canônico + com 55
  vars := array_append(vars, v);
  vars := array_append(vars, '55' || v);

  -- Móvel 11 dígitos (DDD + 9 + 8 dígitos) → também tenta sem o 9º
  IF length(v) = 11 AND substring(v, 3, 1) = '9' THEN
    vars := array_append(vars, substring(v, 1, 2) || substring(v, 4));
    vars := array_append(vars, '55' || substring(v, 1, 2) || substring(v, 4));

  -- Móvel 10 dígitos (DDD + 8 dígitos, sem 9) → também tenta com o 9º
  ELSIF length(v) = 10 AND substring(v, 3, 1) IN ('6', '7', '8', '9') THEN
    vars := array_append(vars, substring(v, 1, 2) || '9' || substring(v, 3));
    vars := array_append(vars, '55' || substring(v, 1, 2) || '9' || substring(v, 3));
  END IF;

  RETURN (
    SELECT coalesce(array_agg(DISTINCT u), ARRAY[]::TEXT[])
    FROM unnest(vars) AS u
    WHERE u IS NOT NULL AND u <> ''
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.telefone_br_match(p_a TEXT, p_b TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM unnest(public.telefone_br_variants(p_a)) AS va
    JOIN unnest(public.telefone_br_variants(p_b)) AS vb ON va = vb
  );
$$;

-- ---------------------------------------------------------------------------
-- 2) get_or_create_contato — DROP antes pra evitar conflito de assinatura
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB, TEXT);
DROP FUNCTION IF EXISTS public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB);

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
  v_normalized := public.normalize_telefone_br(p_telefone);
  IF v_normalized IS NULL OR length(v_normalized) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'telefone inválido');
  END IF;

  -- Busca por EQUIVALÊNCIA (com/sem 55, com/sem 9º dígito)
  SELECT c.id INTO v_contato_id
  FROM public.contatos c
  WHERE c.telefone IS NOT NULL
    AND public.telefone_br_match(c.telefone, p_telefone)
  ORDER BY c.created_at ASC
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
    -- Existente: canonicaliza telefone, atualiza instancia se vier, marca ADS se for o caso
    UPDATE public.contatos
    SET ultima_interacao = COALESCE(ultima_interacao, 'start'),
        canal_origem     = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_origem END,
        canal_atual      = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_atual END,
        instancia_id     = COALESCE(p_instancia_id, instancia_id),
        telefone         = v_normalized,
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

-- ---------------------------------------------------------------------------
-- 3) create_contato — DROP antes pra evitar conflito de assinatura
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_contato(text, text, text, text, text, text, text, text, text, text, text, uuid, uuid);
DROP FUNCTION IF EXISTS public.create_contato(text, text, text, text, text, text, text, text, text, text, text, uuid);

CREATE OR REPLACE FUNCTION public.create_contato(
  p_nome             text,
  p_canal_origem     text,
  p_telefone         text DEFAULT NULL,
  p_cpf              text DEFAULT NULL,
  p_endereco         text DEFAULT NULL,
  p_complemento      text DEFAULT NULL,
  p_bairro           text DEFAULT NULL,
  p_cidade_uf        text DEFAULT NULL,
  p_cep              text DEFAULT NULL,
  p_cidade           text DEFAULT NULL,
  p_uf               text DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL,
  p_instancia_id     uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id       uuid;
  v_tel      text;
  v_existing uuid;
BEGIN
  v_tel := public.normalize_telefone_br(p_telefone);

  -- Bloqueia duplicata por equivalência BR (exceto C-REP que pode ter linha duplicada)
  IF v_tel IS NOT NULL AND p_canal_origem IS DISTINCT FROM 'C-REP' THEN
    SELECT c.id INTO v_existing
    FROM public.contatos c
    WHERE c.telefone IS NOT NULL
      AND c.canal_origem IS DISTINCT FROM 'C-REP'
      AND public.telefone_br_match(c.telefone, v_tel)
    ORDER BY c.created_at ASC
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
      RAISE EXCEPTION 'telefone já cadastrado (contato %)', v_existing
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;

  INSERT INTO contatos (
    nome, canal_origem, canal_atual, telefone, cpf, endereco, complemento,
    bairro, cidade_uf, cep, cidade, uf, representante_id, instancia_id
  ) VALUES (
    p_nome, p_canal_origem, p_canal_origem, v_tel, p_cpf, p_endereco, p_complemento,
    p_bairro, p_cidade_uf, p_cep, p_cidade, p_uf, p_representante_id, p_instancia_id
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_contato(text, text, text, text, text, text, text, text, text, text, text, uuid, uuid)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Backfill defensivo: canonicaliza telefones existentes.
--    EXCEPTION handler engole conflito UNIQUE (alguns contatos já têm
--    o telefone canônico em outra linha — esses ficam pra dedup manual).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_target TEXT;
  v_count_updated INT := 0;
  v_count_skipped INT := 0;
BEGIN
  FOR r IN
    SELECT id, telefone
      FROM public.contatos
     WHERE telefone IS NOT NULL
  LOOP
    v_target := public.normalize_telefone_br(r.telefone);
    IF v_target IS NULL OR length(v_target) < 10 OR r.telefone = v_target THEN
      CONTINUE;
    END IF;

    BEGIN
      UPDATE public.contatos
         SET telefone = v_target, updated_at = NOW()
       WHERE id = r.id;
      v_count_updated := v_count_updated + 1;
    EXCEPTION WHEN unique_violation THEN
      v_count_skipped := v_count_skipped + 1;
    END;
  END LOOP;
  RAISE NOTICE 'Backfill telefones: % atualizados, % pulados (dup).', v_count_updated, v_count_skipped;
END $$;

NOTIFY pgrst, 'reload schema';

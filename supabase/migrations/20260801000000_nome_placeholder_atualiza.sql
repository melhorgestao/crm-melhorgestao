-- ============================================================================
-- Nome placeholder atualiza quando chega pushName real.
--
-- CONTEXTO: contato criado via comando /start (fromMe) nasce sem nome real —
-- o pushName de mensagem fromMe é o do NOSSO chip ("Santa Flor"), então o
-- router passa p_nome vazio e o contato fica com nome = telefone (placeholder).
-- Porém get_or_create_contato NUNCA atualizava o nome de contato existente:
-- quando o lead mandasse mensagem (pushName real), o placeholder ficava.
--
-- FIX:
--   1) No UPDATE de contato existente: se chegou p_nome real E o nome atual é
--      placeholder (NULL, = telefone, ou "Santa Flor" gravado por engano nos
--      /start antigos), atualiza pro pushName do lead.
--   2) One-off: conserta contatos já gravados com nome "Santa Flor" (pushName
--      do nosso chip) → volta pro placeholder telefone (o pushName real
--      corrige sozinho na próxima mensagem do lead).
-- ============================================================================

-- 2) one-off: contatos batizados errado com o pushName do chip
UPDATE public.contatos
   SET nome = telefone, updated_at = NOW()
 WHERE nome = 'Santa Flor';

-- 1) RPC: atualiza nome placeholder quando chega pushName real
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
      -- Corrida ou variante extrema: alguém já inseriu equivalente. Re-seleciona.
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

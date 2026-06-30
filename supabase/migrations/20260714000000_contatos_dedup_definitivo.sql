-- ============================================================================
-- FIX DEFINITIVO: contatos duplicados — garantia no nível do banco.
--
-- Causa-raiz: a normalização vivia só nas RPCs (get_or_create_contato,
-- create_contato). Inserts diretos (frontend KanbanRepPage, SQL manual, ou
-- variações extremas de número) escapavam → duplicatas.
--
-- Solução em 4 camadas, INDEPENDENTE do caminho de inserção:
--   1) telefone_canonico_br(): forma canônica forte (strip 55 + dropa 9º
--      dígito) — usada SÓ pra comparação de unicidade.
--   2) TRIGGER BEFORE INSERT/UPDATE: normaliza telefone (dialável) em QUALQUER
--      escrita (exceto C-REP, que pode compartilhar número com o REP).
--   3) MERGE das duplicatas canônicas existentes (repoint dinâmico de TODAS
--      as FKs via introspecção do catálogo + delete dos perdedores).
--   4) UNIQUE INDEX no telefone canônico → duplicata vira IMPOSSÍVEL.
--
-- Casos cobertos: com/sem 55, com/sem 9º dígito, (DDD), espaços, hífens.
-- NÃO cobre: números genuinamente diferentes pro mesmo contato (artefato de
-- LID do WhatsApp) — esses precisam de merge manual (ver diagnóstico no fim).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Canônico forte (strip 55 + dropa 9º dígito móvel). IMMUTABLE p/ index.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.telefone_canonico_br(p_telefone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  d TEXT;
BEGIN
  d := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  IF d = '' THEN RETURN NULL; END IF;
  -- strip código país 55 (12 ou 13 dígitos)
  IF length(d) IN (12, 13) AND left(d, 2) = '55' THEN
    d := substring(d FROM 3);
  END IF;
  -- colapsa 9º dígito móvel: DDD + 9 + 8core → DDD + 8core
  -- (o core de móvel começa em 6-9; landline começa em 2-5 → sem colisão)
  IF length(d) = 11 AND substring(d, 3, 1) = '9' THEN
    d := substring(d, 1, 2) || substring(d FROM 4);
  END IF;
  RETURN d;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2) Helper de MERGE: repoint dinâmico de TODAS as FKs que apontam pra
--    contatos(id), depois deleta o perdedor. Introspecção via pg_constraint
--    garante que nenhuma tabela filha é esquecida (pedidos, lancamentos,
--    follow_up, mensagens_buffer, eventos_contato, representante_id, etc).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.merge_contato(p_keeper UUID, p_loser UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  fk RECORD;
BEGIN
  IF p_keeper IS NULL OR p_loser IS NULL OR p_keeper = p_loser THEN
    RETURN;
  END IF;

  FOR fk IN
    SELECT c.conrelid::regclass AS child_table, a.attname AS child_col
    FROM pg_constraint c
    JOIN pg_attribute a
      ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.contype = 'f'
      AND c.confrelid = 'public.contatos'::regclass
  LOOP
    EXECUTE format(
      'UPDATE %s SET %I = $1 WHERE %I = $2',
      fk.child_table, fk.child_col, fk.child_col
    ) USING p_keeper, p_loser;
  END LOOP;

  DELETE FROM public.contatos WHERE id = p_loser;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merge_contato(UUID, UUID) TO service_role;

-- ----------------------------------------------------------------------------
-- 3) MERGE das duplicatas canônicas existentes.
--    Keeper = quem comprou > quem é mais antigo. Perdedores mergeados nele.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  grp    RECORD;
  keeper UUID;
  i      INT;
  merged INT := 0;
  failed INT := 0;
BEGIN
  FOR grp IN
    SELECT public.telefone_canonico_br(telefone) AS canon,
           array_agg(id ORDER BY ja_comprou DESC NULLS LAST, created_at ASC) AS ids
    FROM public.contatos
    WHERE telefone IS NOT NULL
      AND canal_origem IS DISTINCT FROM 'C-REP'
      AND canal_origem IS DISTINCT FROM 'INTERNO'
      AND public.telefone_canonico_br(telefone) IS NOT NULL
      AND length(public.telefone_canonico_br(telefone)) >= 10
    GROUP BY public.telefone_canonico_br(telefone)
    HAVING count(*) > 1
  LOOP
    keeper := grp.ids[1];
    FOR i IN 2 .. array_length(grp.ids, 1) LOOP
      BEGIN
        PERFORM public.merge_contato(keeper, grp.ids[i]);
        merged := merged + 1;
      EXCEPTION WHEN OTHERS THEN
        failed := failed + 1;
        RAISE NOTICE 'merge falhou keeper=% loser=%: %', keeper, grp.ids[i], SQLERRM;
      END;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'Dedup canônico: % mergeados, % falharam.', merged, failed;
END $$;

-- ----------------------------------------------------------------------------
-- 4) Caso específico: DELETA o contato duplicado "Snoop" (5180511911).
--    Número genuinamente diferente do VK (artefato LID) → não pega no dedup
--    canônico acima. User confirmou: APAGAR Snoop (não mergear).
--    FK-safe: nula a self-ref representante_id antes; buffer/eventos/follow_up
--    saem por CASCADE; pedidos/lancamentos viram contato_id=NULL (SET NULL).
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_snoop UUID;
BEGIN
  SELECT id INTO v_snoop
    FROM public.contatos
   WHERE nome ILIKE 'snoop'
     AND regexp_replace(coalesce(telefone,''), '[^0-9]', '', 'g') = '5180511911'
   ORDER BY created_at ASC LIMIT 1;

  IF v_snoop IS NOT NULL THEN
    -- caso Snoop seja representante de algum C-REP, solta a referência
    UPDATE public.contatos SET representante_id = NULL WHERE representante_id = v_snoop;
    DELETE FROM public.contatos WHERE id = v_snoop;
    RAISE NOTICE 'Snoop (%) DELETADO.', v_snoop;
  ELSE
    RAISE NOTICE 'Snoop não encontrado (nome=snoop, tel=5180511911) — nada feito.';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5) TRIGGER: normaliza telefone (dialável) em QUALQUER insert/update.
--    Usa normalize_telefone_br (strip 55 + formatação, MANTÉM 9º dígito —
--    número segue dialável). C-REP é poupado (compartilha número com o REP).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normaliza_telefone_contato()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.telefone IS NOT NULL
     AND NEW.canal_origem IS DISTINCT FROM 'C-REP' THEN
    NEW.telefone := public.normalize_telefone_br(NEW.telefone);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normaliza_telefone_contato ON public.contatos;
CREATE TRIGGER trg_normaliza_telefone_contato
  BEFORE INSERT OR UPDATE OF telefone
  ON public.contatos
  FOR EACH ROW
  EXECUTE FUNCTION public.normaliza_telefone_contato();

-- ----------------------------------------------------------------------------
-- 6) UNIQUE INDEX no canônico → duplicata IMPOSSÍVEL (exceto C-REP/INTERNO).
--    Se ainda restar dup (merge falhou por conflito de FK), o índice não cria
--    e emite NOTICE — rode o diagnóstico do rodapé.
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS public.contatos_telefone_unique_partial;  -- substituído pelo canônico

DO $$
BEGIN
  CREATE UNIQUE INDEX contatos_telefone_canonico_unique
    ON public.contatos (public.telefone_canonico_br(telefone))
    WHERE telefone IS NOT NULL
      AND canal_origem IS DISTINCT FROM 'C-REP'
      AND canal_origem IS DISTINCT FROM 'INTERNO';
  RAISE NOTICE 'UNIQUE INDEX canônico criado — duplicatas agora impossíveis.';
EXCEPTION WHEN unique_violation OR duplicate_table THEN
  RAISE NOTICE 'Index canônico NÃO criado (ainda há duplicatas). Rode o diagnóstico.';
END $$;

-- ----------------------------------------------------------------------------
-- 7) Hardening: get_or_create_contato trata unique_violation (corrida) —
--    se o INSERT colidir, re-seleciona por equivalência e segue.
-- ----------------------------------------------------------------------------
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

-- ============================================================================
-- DIAGNÓSTICO (rodar à parte) — lista dups por LID que precisam merge manual:
--
--   SELECT public.telefone_canonico_br(telefone) AS canon,
--          array_agg(nome ORDER BY created_at) AS nomes,
--          array_agg(telefone ORDER BY created_at) AS telefones,
--          count(*)
--   FROM public.contatos
--   WHERE telefone IS NOT NULL AND canal_origem NOT IN ('C-REP','INTERNO')
--   GROUP BY 1 HAVING count(*) > 1;
--
-- Pra mergear manual: SELECT public.merge_contato('<keeper_id>','<loser_id>');
-- ============================================================================

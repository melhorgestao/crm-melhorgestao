-- ============================================================================
-- Unifica endereço de contatos: fonte de verdade vira rua+numero (separados).
--
-- CONTEXTO: 3 colunas conviviam (endereco, rua, numero) em estados parciais:
--  - UI CRM (ContatosPage/LogisticaPage) salvava em 'endereco' (rua+nº juntos)
--    deixando rua/numero NULL.
--  - agent-closing (WhatsApp) salvava em rua+numero deixando endereco NULL.
--  - Resultado: contato editado pelo CRM = bot pedia endereço de novo; contato
--    gerado pelo bot = UI mostrava endereço vazio.
--
-- AGORA:
--  1) BACKFILL: splita 'endereco' em rua+numero onde estes estavam vazios.
--  2) TRIGGER: mantém 'endereco' sincronizado quando rua/numero mudam (pra
--     RPCs antigas que ainda leem 'endereco' continuarem funcionando).
--  3) NÃO drop ainda — vamos confirmar tudo OK por uma semana antes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) BACKFILL: splita endereco em rua+numero quando esses estão NULL/vazios
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_partes text[];
  v_rua text;
  v_numero text;
  v_count int := 0;
BEGIN
  FOR r IN
    SELECT id, endereco FROM public.contatos
     WHERE endereco IS NOT NULL AND TRIM(endereco) != ''
       AND (rua IS NULL OR TRIM(rua) = '' OR numero IS NULL OR TRIM(numero) = '')
  LOOP
    -- Tenta separar por ", " (formato salvo pela UI: "Rua X, 123")
    v_partes := string_to_array(r.endereco, ', ');
    IF array_length(v_partes, 1) >= 2 THEN
      v_rua    := TRIM(array_to_string(v_partes[1:array_length(v_partes,1)-1], ', '));
      v_numero := TRIM(v_partes[array_length(v_partes, 1)]);
    ELSE
      -- Fallback: tenta achar o último número solto no fim ("Rua X 123")
      v_rua    := TRIM(regexp_replace(r.endereco, '\s+\d+\s*$', ''));
      v_numero := TRIM(COALESCE(substring(r.endereco from '\s+(\d+)\s*$'), 'SN'));
      IF v_rua = r.endereco THEN
        -- Não tem número detectável: usa tudo como rua, número SN
        v_rua    := TRIM(r.endereco);
        v_numero := 'SN';
      END IF;
    END IF;

    UPDATE public.contatos
       SET rua    = COALESCE(NULLIF(TRIM(rua), ''), v_rua),
           numero = COALESCE(NULLIF(TRIM(numero), ''), v_numero),
           updated_at = NOW()
     WHERE id = r.id;
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE 'Backfill: % contatos com rua/numero populados a partir de endereco.', v_count;
END $$;

-- ----------------------------------------------------------------------------
-- 2) TRIGGER: mantém 'endereco' = "rua, numero" sincronizado
--    Compat: RPCs antigas que leem 'endereco' continuam funcionando.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_sync_endereco_rua_numero()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_partes text[];
  v_rua_split text;
  v_num_split text;
BEGIN
  -- ↓↓↓ CAMINHO A: chegou endereco mas rua/numero vazios → splita
  IF NEW.endereco IS NOT NULL AND TRIM(NEW.endereco) != ''
     AND (NEW.rua IS NULL OR TRIM(NEW.rua) = '')
     AND (NEW.numero IS NULL OR TRIM(NEW.numero) = '')
  THEN
    v_partes := string_to_array(NEW.endereco, ', ');
    IF array_length(v_partes, 1) >= 2 THEN
      v_rua_split := TRIM(array_to_string(v_partes[1:array_length(v_partes,1)-1], ', '));
      v_num_split := TRIM(v_partes[array_length(v_partes, 1)]);
    ELSE
      v_rua_split := TRIM(regexp_replace(NEW.endereco, '\s+\d+\s*$', ''));
      v_num_split := TRIM(COALESCE(substring(NEW.endereco from '\s+(\d+)\s*$'), 'SN'));
      IF v_rua_split = NEW.endereco THEN
        v_rua_split := TRIM(NEW.endereco);
        v_num_split := 'SN';
      END IF;
    END IF;
    NEW.rua    := v_rua_split;
    NEW.numero := v_num_split;
  END IF;

  -- ↑↑↑ CAMINHO B: rua/numero preenchidos → regenera endereco
  IF NEW.rua IS NOT NULL AND TRIM(NEW.rua) != '' THEN
    NEW.endereco := CASE
      WHEN NEW.numero IS NOT NULL AND TRIM(NEW.numero) != ''
        THEN TRIM(NEW.rua) || ', ' || TRIM(NEW.numero)
      ELSE TRIM(NEW.rua)
    END;
    NEW.rua_numero := NEW.endereco;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_sync_endereco_rua_numero ON public.contatos;
CREATE TRIGGER trg_sync_endereco_rua_numero
  BEFORE INSERT OR UPDATE OF endereco, rua, numero ON public.contatos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_sync_endereco_rua_numero();

-- ----------------------------------------------------------------------------
-- 3) Atualiza endereco/rua_numero pra reflectir rua+numero existentes
--    (re-sincronização imediata, sem precisar de novo UPDATE)
-- ----------------------------------------------------------------------------
UPDATE public.contatos
   SET endereco   = TRIM(rua) || ', ' || TRIM(numero),
       rua_numero = TRIM(rua) || ', ' || TRIM(numero)
 WHERE rua IS NOT NULL AND TRIM(rua) != ''
   AND numero IS NOT NULL AND TRIM(numero) != ''
   AND (endereco IS NULL OR endereco != TRIM(rua) || ', ' || TRIM(numero));

NOTIFY pgrst, 'reload schema';

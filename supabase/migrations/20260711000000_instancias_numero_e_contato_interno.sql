-- ============================================================================
-- Rename instancias.numero_final → instancias.numero
-- Auto-sync de contato INTERNO por instância (pra alertas)
-- Atualiza os 2 chips: Instancia 1 = 45998510512, Instancia 2 = 45991082763
-- Atualiza alerta_telefone da instância admin pra 55+chip da Instancia 1
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Expande canal_origem pra incluir 'INTERNO' (se ainda não tiver)
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;
ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check
  CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'INTERNO'));

-- ----------------------------------------------------------------------------
-- 2) Rename da coluna
-- ----------------------------------------------------------------------------
ALTER TABLE public.instancias RENAME COLUMN numero_final TO numero;

COMMENT ON COLUMN public.instancias.numero IS
  'Número do chip WhatsApp completo (DDD + número, só dígitos). Ex: 45998510512.
   Ao salvar, dispara trigger que cria/atualiza contato INTERNO correspondente
   pra fins de alertas internos do sistema.';

-- ----------------------------------------------------------------------------
-- 3) Trigger: ao salvar numero na instância, upsert contato INTERNO
--    - nome  = nome da instância (ex: "Instancia 1")
--    - telefone = numero (só dígitos)
--    - canal_origem/canal_atual = INTERNO
--    - ultima_interacao = NULL (NÃO aparece no Kanban, NÃO chama agente)
--    - instancia_id = id
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_contato_interno_instancia()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tel_norm TEXT;
  v_existing UUID;
BEGIN
  -- Sai se numero ficou NULL
  IF NEW.numero IS NULL OR TRIM(NEW.numero) = '' THEN
    RETURN NEW;
  END IF;

  v_tel_norm := REGEXP_REPLACE(NEW.numero, '\D', '', 'g');

  -- Procura contato existente já vinculado a esta instância como INTERNO
  SELECT id INTO v_existing
  FROM public.contatos
  WHERE instancia_id = NEW.id
    AND canal_origem = 'INTERNO'
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    -- Atualiza telefone se mudou, força ultima_interacao=NULL
    UPDATE public.contatos
       SET telefone = v_tel_norm,
           nome = COALESCE(NULLIF(TRIM(nome), ''), 'Instancia ' || NEW.nome),
           canal_atual = 'INTERNO',
           ultima_interacao = NULL,
           updated_at = NOW()
     WHERE id = v_existing;
  ELSE
    -- Cria novo. ON CONFLICT NÃO usado: índice unique é parcial e o INTERNO
    -- está nele — se houver telefone duplicado entre instâncias, é bug a
    -- corrigir manualmente (não silenciar).
    INSERT INTO public.contatos (
      nome, telefone, canal_origem, canal_atual,
      instancia_id, ultima_interacao, created_at, updated_at
    ) VALUES (
      'Instancia ' || NEW.nome,
      v_tel_norm,
      'INTERNO', 'INTERNO',
      NEW.id, NULL, NOW(), NOW()
    );
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_sync_contato_interno_instancia ON public.instancias;
CREATE TRIGGER trg_sync_contato_interno_instancia
  AFTER INSERT OR UPDATE OF numero, nome
  ON public.instancias
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_contato_interno_instancia();

-- ----------------------------------------------------------------------------
-- 4) Seed: atualiza os chips atuais. O trigger dispara → cria contatos INTERNO.
-- ----------------------------------------------------------------------------
UPDATE public.instancias SET numero = '45998510512' WHERE nome = '1';
UPDATE public.instancias SET numero = '45991082763' WHERE nome = '2';

-- ----------------------------------------------------------------------------
-- 5) Atualiza alerta_telefone da instância admin pra 55 + chip da Instancia 1
--    Formato esperado pelo workflow Evolution: dígitos com 55 na frente.
-- ----------------------------------------------------------------------------
UPDATE public.instancias
   SET alerta_telefone = '5545998510512'
 WHERE alerta_admin = true;

NOTIFY pgrst, 'reload schema';

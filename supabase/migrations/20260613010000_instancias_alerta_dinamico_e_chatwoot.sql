-- ============================================================================
-- 1) Telefone destino dos alertas (dinâmico, configurado pela instância admin).
-- 2) Coroa única: trigger auto-desmarca outras quando marcar uma como admin.
-- 3) Integração Chatwoot: campos + slots de config global.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Telefone do destinatário dos alertas (na instância admin)
-- ----------------------------------------------------------------------------
ALTER TABLE public.instancias
  ADD COLUMN IF NOT EXISTS alerta_telefone text;

-- Seed: instância marcada como admin recebe o telefone histórico hardcoded
UPDATE public.instancias
   SET alerta_telefone = COALESCE(alerta_telefone, '5511991282579')
 WHERE alerta_admin = true;

-- ----------------------------------------------------------------------------
-- 2) Coroa única (auto-shift)
-- ----------------------------------------------------------------------------
-- Remove o UNIQUE INDEX rígido (bloqueava) — vamos usar trigger pra auto-shift
DROP INDEX IF EXISTS public.instancias_alerta_admin_unico;

CREATE OR REPLACE FUNCTION public.trigger_unique_alerta_admin()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.alerta_admin = true AND (TG_OP = 'INSERT' OR OLD.alerta_admin IS DISTINCT FROM true) THEN
    UPDATE public.instancias
       SET alerta_admin = false
     WHERE id <> NEW.id
       AND alerta_admin = true;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS instancias_unique_admin ON public.instancias;
CREATE TRIGGER instancias_unique_admin
  AFTER INSERT OR UPDATE OF alerta_admin
  ON public.instancias
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_unique_alerta_admin();

-- ----------------------------------------------------------------------------
-- 3) Chatwoot — colunas na instância + slots de config global
-- ----------------------------------------------------------------------------
ALTER TABLE public.instancias
  ADD COLUMN IF NOT EXISTS chatwoot_inbox_id  text,
  ADD COLUMN IF NOT EXISTS chatwoot_integrated boolean NOT NULL DEFAULT false;

-- Config global Chatwoot
INSERT INTO public.configuracoes (chave, valor) VALUES
  ('chatwoot_url', ''),
  ('chatwoot_account_id', ''),
  ('chatwoot_api_token', '')
ON CONFLICT (chave) DO NOTHING;

NOTIFY pgrst, 'reload schema';

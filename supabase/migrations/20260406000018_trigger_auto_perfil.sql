-- ============================================================
-- Major Update V2 - Trigger auto-criacao de perfil
-- ============================================================
-- Quando um novo user é criado no Auth, trigger cria perfil automaticamente.
-- Isso permite criar usuarios 100% pelo CRM, sem SQL manual.

BEGIN;

-- Funcao que cria perfil automaticamente
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.perfis_usuario (
    user_id,
    nome,
    acesso_kanban,
    ver_menu,
    pode_excluir_card,
    tipo_usuario,
    socio_key,
    email
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'apelido', split_part(NEW.email, '@', 1)),
    'todos',
    ARRAY['todos']::text[],
    true,
    COALESCE(NEW.raw_user_meta_data->>'tipo_usuario', 'admin'),
    COALESCE(NEW.raw_user_meta_data->>'socio_key', NULL),
    NEW.email
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Trigger no auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

COMMIT;

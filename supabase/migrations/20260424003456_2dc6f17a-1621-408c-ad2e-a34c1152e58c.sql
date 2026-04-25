-- Backfill dos 2 admins já em auth.users (idempotente)
INSERT INTO public.perfis_usuario
  (user_id, nome, email, acesso_kanban, ver_menu, pode_excluir_card, tipo_usuario, socio_key)
VALUES
  ('44aa68b2-8cea-42c8-8fb0-3093926e2b35', 'V', 'v@santaflor.com',
   'todos', '["todos"]'::jsonb, true, 'admin', 'V'),
  ('61b22ba5-6df4-493f-ad6a-cd51c95bb5c4', 'A', 'a@santaflor.com',
   'todos', '["todos"]'::jsonb, true, 'admin', 'A')
ON CONFLICT (user_id) DO UPDATE SET
  tipo_usuario = 'admin',
  acesso_kanban = 'todos',
  ver_menu = '["todos"]'::jsonb,
  pode_excluir_card = true,
  socio_key = EXCLUDED.socio_key,
  email = EXCLUDED.email;

-- Backfill genérico: qualquer auth.user sem perfil ganha um
INSERT INTO public.perfis_usuario (user_id, nome, email, acesso_kanban, ver_menu, pode_excluir_card, tipo_usuario, socio_key)
SELECT u.id,
       COALESCE(u.raw_user_meta_data->>'apelido', split_part(u.email,'@',1)),
       u.email,
       'todos',
       '["todos"]'::jsonb,
       true,
       COALESCE(u.raw_user_meta_data->>'tipo_usuario','admin'),
       COALESCE(u.raw_user_meta_data->>'socio_key', UPPER(LEFT(split_part(u.email,'@',1),1)))
FROM auth.users u
LEFT JOIN public.perfis_usuario p ON p.user_id = u.id
WHERE p.user_id IS NULL;

-- Policy de INSERT (faltando) — permite frontend autenticado criar perfil próprio
CREATE POLICY "Users can insert own profile"
ON public.perfis_usuario FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);
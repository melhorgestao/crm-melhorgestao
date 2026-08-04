-- ============================================================================
-- FIX: upload no bucket "Start" bloqueado por RLS ("new row violates row-level
-- security policy") ao trocar a foto do BLOCO 4 (apresentação) e ao subir arte
-- de produto (EstoquePage). O bucket existia com leitura pública, mas SEM
-- políticas de INSERT/UPDATE/DELETE em storage.objects.
--
-- FIX: garante o bucket público + políticas de escrita pra usuários logados
-- (staff do CRM). Leitura segue pública (as artes/fotos são exibidas no bot).
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
  VALUES ('Start', 'Start', true)
  ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "Public read Start"   ON storage.objects;
DROP POLICY IF EXISTS "Auth upload Start"   ON storage.objects;
DROP POLICY IF EXISTS "Auth update Start"   ON storage.objects;
DROP POLICY IF EXISTS "Auth delete Start"   ON storage.objects;

CREATE POLICY "Public read Start" ON storage.objects FOR SELECT
  USING (bucket_id = 'Start');

CREATE POLICY "Auth upload Start" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'Start');

CREATE POLICY "Auth update Start" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'Start')
  WITH CHECK (bucket_id = 'Start');

CREATE POLICY "Auth delete Start" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'Start');

-- ============================================================
-- Fix: lancamentos_socios.data timezone + backfill
-- ============================================================

-- Fix column default to use Sao Paulo timezone
ALTER TABLE public.lancamentos_socios ALTER COLUMN data SET DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo')::date;

-- Backfill: fix existing records with wrong dates (shifted by +1 day due to UTC)
UPDATE public.lancamentos_socios
SET data = data - INTERVAL '1 day'
WHERE data > (now() AT TIME ZONE 'America/Sao_Paulo')::date;

-- ============================================================
-- Admin: adicionar email em perfis_usuario
-- ============================================================

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS email text;

-- Popula emails dos usuarios existentes via auth.users
UPDATE public.perfis_usuario
SET email = au.email
FROM auth.users au
WHERE perfis_usuario.user_id = au.id
AND perfis_usuario.email IS NULL;


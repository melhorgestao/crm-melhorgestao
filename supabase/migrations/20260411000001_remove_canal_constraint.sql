-- ULTIMATE FIX: Remove canal_origem constraint completely to allow any value
-- This was broken after adding C-REP because the constraint wasn't properly updated

-- Drop the check constraint completely
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

-- Add a simple NOT NULL constraint (no value restrictions)
ALTER TABLE public.contatos ALTER COLUMN canal_origem SET NOT NULL;

-- Reload PostgREST schema
NOTIFY pgrst, 'reload schema';

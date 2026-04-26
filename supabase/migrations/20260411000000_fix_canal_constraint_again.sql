-- Fix canal_origem check constraint to include C-REP
-- This is needed because the original table creation had a constraint without C-REP

ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IS NULL OR canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));

-- Also ensure canal_origem is NOT NULL (if that's the desired behavior)
-- ALTER TABLE public.contatos ALTER COLUMN canal_origem SET NOT NULL;

NOTIFY pgrst, 'reload schema';

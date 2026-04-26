-- Fix: Ensure C-REP is in canal_origem constraint
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;
ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));

-- Rastreia fotos de produto já enviadas pra evitar repetir.
-- agent-start lê e popula. agent-closing nem mexe (não envia foto).
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS fotos_enviadas TEXT[] NOT NULL DEFAULT '{}';

NOTIFY pgrst, 'reload schema';

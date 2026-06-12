-- ============================================================================
-- contatos_telefone_unique impedia C-REP de compartilhar telefone com seu REP.
-- Substituído por índice parcial que ignora C-REP (intencionalmente duplicado).
-- ============================================================================

ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_telefone_unique;

-- Unique parcial: telefone único entre BASE/ADS/REP/INTERNO/PROS/etc.,
-- mas C-REP pode repetir (= telefone do REP responsável)
CREATE UNIQUE INDEX IF NOT EXISTS contatos_telefone_unique_partial
  ON public.contatos (telefone)
  WHERE telefone IS NOT NULL
    AND canal_origem <> 'C-REP';

NOTIFY pgrst, 'reload schema';

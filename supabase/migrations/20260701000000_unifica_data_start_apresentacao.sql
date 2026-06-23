-- ============================================================================
-- Unifica data_start ⇄ apresentacao_enviada_em.
--
-- DIAGNÓSTICO:
--  - data_start (TIMESTAMPTZ) existe, crons usam pra timeout 24h, Kanban lê.
--    Porém NINGUÉM escrevia → sempre NULL → cron de 24h nunca disparava.
--  - apresentacao_enviada_em (TIMESTAMPTZ) foi criado depois pra controlar
--    reapresentação. Agent-start preenche. Tem uso ativo.
--  - Semanticamente são a MESMA coisa: lead entra em 'start' uma vez,
--    quando recebe apresentação, depois vai pra wait_follow_up.
--
-- AÇÕES:
--  1) BACKFILL: data_start = COALESCE(data_start, apresentacao_enviada_em)
--  2) DROP apresentacao_enviada_em
--  3) Trigger BEFORE UPDATE: ao mudar ultima_interacao pra 'start', seta
--     data_start = NOW() se ainda NULL (defensivo).
--  4) get_or_create_contato: garante que novo contato com ultima_interacao
--     'start' nasce com data_start = NOW().
-- ============================================================================

-- 1) BACKFILL: copia apresentacao_enviada_em pra data_start se data_start NULL
UPDATE public.contatos
   SET data_start = apresentacao_enviada_em,
       updated_at = NOW()
 WHERE data_start IS NULL
   AND apresentacao_enviada_em IS NOT NULL;

-- 2) DROP apresentacao_enviada_em (com index parcial que tinha)
DROP INDEX IF EXISTS public.idx_contatos_apresentacao_pendente;
ALTER TABLE public.contatos DROP COLUMN IF EXISTS apresentacao_enviada_em;

-- 3) Trigger defensivo: ao virar 'start' sem data_start, popula
CREATE OR REPLACE FUNCTION public.trigger_data_start_default()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ultima_interacao = 'start' AND NEW.data_start IS NULL THEN
    NEW.data_start := NOW();
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_data_start_default ON public.contatos;
CREATE TRIGGER trg_data_start_default
  BEFORE INSERT OR UPDATE OF ultima_interacao ON public.contatos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_data_start_default();

-- 4) Índice parcial pra leads aguardando apresentação (substitui o dropado)
CREATE INDEX IF NOT EXISTS idx_contatos_sem_apresentacao
  ON public.contatos (id)
  WHERE data_start IS NULL AND ja_comprou = false;

NOTIFY pgrst, 'reload schema';

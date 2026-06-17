-- ============================================================================
-- Cron de safety pro process-buffer.
--
-- Dispara process-buffer?mode=cron a cada 1 minuto pra recuperar mensagens
-- órfãs no mensagens_buffer (caso o n8n cai, time-out, etc).
-- A função processa apenas mensagens em 'in' não-processadas com >180s de idade.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net  WITH SCHEMA extensions;

DO $$
BEGIN
  PERFORM cron.unschedule('process-buffer-safety-1min');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$
BEGIN
  PERFORM cron.unschedule('process-buffer-safety-5min');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Roda a cada 5 minutos e só pega mensagens órfãs há mais de 10 minutos.
-- Evita disparar duplicado em cima do fluxo normal (n8n + Wait 12s).
SELECT cron.schedule(
  'process-buffer-safety-5min',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://epreaawpvxrpqqthcczu.supabase.co/functions/v1/process-buffer?mode=cron',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMjM5MDIsImV4cCI6MjA5MjY5OTkwMn0.VEQb1fk7JRIB1KXtHZGcmLKKMWJvkpG1fINB3mdPn0E"}'::jsonb,
    body := '{"max_idade_seg": 600}'::jsonb
  );
  $$
);

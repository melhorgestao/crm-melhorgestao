-- ============================================================================
-- Cron health-check de instâncias Evolution.
--
-- Roda check-instance-health a cada 5 min. Pausa automaticamente:
--   • Instância com state != 'open' (close/connecting) → 6h
--   • Instância retornando 401/403 (apikey inválida ou ban) → 24h
--
-- Após o tempo, cron diário 'auto-reativar-instancias-pausadas' (existente)
-- reabilita pra nova checagem.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net  WITH SCHEMA extensions;

DO $$
BEGIN
  PERFORM cron.unschedule('check-instance-health-5min');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'check-instance-health-5min',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://epreaawpvxrpqqthcczu.supabase.co/functions/v1/check-instance-health',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMjM5MDIsImV4cCI6MjA5MjY5OTkwMn0.VEQb1fk7JRIB1KXtHZGcmLKKMWJvkpG1fINB3mdPn0E"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);

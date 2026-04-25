-- Garante extensões pg_cron / pg_net
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Remove agendamento anterior (se existir) para evitar duplicidade
DO $$
BEGIN
  PERFORM cron.unschedule('superfrete-sync-every-5min');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Agenda chamada à edge function superfrete-sync a cada 5 minutos
SELECT cron.schedule(
  'superfrete-sync-every-5min',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://seplijmbdrbfbtdmjubg.supabase.co/functions/v1/superfrete-sync',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
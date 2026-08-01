-- ============================================================================
-- Cron do CINTO DE SEGURANÇA de pagamento (poll-deflow-deposits).
--
-- A cada 2 min, chama o edge poll-deflow-deposits, que pergunta pra DeFlow o
-- status de cada PIX pendente e fecha o pedido se estiver pago — sem depender
-- do webhook. Usa a MESMA RPC idempotente (processar_webhook_deflow), então
-- roda junto com o webhook sem duplicar.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'poll-deflow-deposits') THEN
    PERFORM cron.unschedule('poll-deflow-deposits');
  END IF;
  PERFORM cron.schedule(
    'poll-deflow-deposits',
    '*/2 * * * *',
    $cmd$
      SELECT net.http_post(
        url := 'https://epreaawpvxrpqqthcczu.supabase.co/functions/v1/poll-deflow-deposits',
        headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMjM5MDIsImV4cCI6MjA5MjY5OTkwMn0.VEQb1fk7JRIB1KXtHZGcmLKKMWJvkpG1fINB3mdPn0E"}'::jsonb,
        body := '{}'::jsonb,
        timeout_milliseconds := 30000
      );
    $cmd$
  );
END $$;

NOTIFY pgrst, 'reload schema';

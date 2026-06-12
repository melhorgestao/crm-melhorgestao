-- ============================================================================
-- Cron auto-reativar refeito com semântica realista:
--
-- - desconectado: precisa QR code (Mostrar QR no /instancias)        → manual
-- - banido:       WhatsApp baniu, número morto                       → manual (delete)
-- - pausado_admin: admin pausou com timer, expira sozinho            → AUTO ✓
--
-- O cron antigo tentava reativar todos três indiscriminadamente — sem efeito
-- prático nos dois primeiros (a instância continuaria sem conexão).
-- ============================================================================

-- Remove o agendamento antigo
SELECT cron.unschedule('auto-reativar-instancias-pausadas')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-reativar-instancias-pausadas');

-- Recria com filtro semanticamente correto
SELECT cron.schedule(
  'auto-reativar-pausas-admin-expiradas',
  '0 3 * * *',
  $$
  UPDATE public.instancias
     SET status       = 'ativo',
         pausado_ate  = NULL,
         motivo_pausa = NULL
   WHERE status = 'pausado_admin'
     AND pausado_ate IS NOT NULL
     AND pausado_ate < NOW();
  $$
);

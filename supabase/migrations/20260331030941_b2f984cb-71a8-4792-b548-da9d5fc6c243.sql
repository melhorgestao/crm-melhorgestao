
SELECT cron.schedule(
  'archive-stale-kanban-daily',
  '0 3 * * *',
  $$SELECT public.archive_stale_kanban_cards()$$
);

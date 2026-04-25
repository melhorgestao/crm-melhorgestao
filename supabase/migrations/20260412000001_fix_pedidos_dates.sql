-- Fix pedidos created between 21h-00h UTC that got wrong date (UTC vs Brasilia -3h)
-- Pedidos created after 21h Brasilia got next day's date in UTC
-- Move them back one day if they were created between 21h-00h UTC (midnight-3am Brasilia)

UPDATE pedidos
SET data = (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date
WHERE data <> (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date;

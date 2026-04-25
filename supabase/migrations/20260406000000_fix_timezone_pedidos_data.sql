-- Fix timezone: pedidos.data must use America/Sao_Paulo date, not UTC
-- This ensures orders placed after 21h SP time get the correct Brazil date

-- 1. Change DEFAULT of pedidos.data to use Sao Paulo timezone
ALTER TABLE public.pedidos ALTER COLUMN data SET DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo')::date;

-- 2. Fix existing data that has wrong date
UPDATE pedidos
SET data = (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date
WHERE data <> (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date;

-- 3. Fix trigger: ultima_venda_em must use Sao Paulo date from created_at
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    UPDATE contatos SET ultima_venda_em = (NEW.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

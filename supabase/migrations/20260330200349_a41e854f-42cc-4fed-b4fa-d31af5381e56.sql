
-- Add columns to contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS cpf text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS data_nascimento date;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS utm_origem text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS como_conheceu text;

-- Rename cidade to cidade_uf
ALTER TABLE public.contatos RENAME COLUMN cidade TO cidade_uf;

-- Add columns to pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS produto_id uuid REFERENCES public.produtos(id);
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS preco_unitario numeric;
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

-- Create lotes table
CREATE TABLE public.lotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  produto_id uuid NOT NULL REFERENCES public.produtos(id),
  uf text NOT NULL,
  quantidade_inicial integer NOT NULL,
  quantidade_atual integer NOT NULL,
  data_producao date NOT NULL DEFAULT CURRENT_DATE,
  lote_codigo text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.lotes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read lotes" ON public.lotes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage lotes" ON public.lotes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Add columns to estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS lote_id uuid REFERENCES public.lotes(id);
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS uf_origem text;

-- Add snapshot columns to lancamentos_socios
ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS snapshot_saldo_v numeric;
ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS snapshot_saldo_a numeric;

-- Drop configuracoes table
DROP TABLE IF EXISTS public.configuracoes;

-- Enable realtime on lotes
ALTER PUBLICATION supabase_realtime ADD TABLE public.lotes;

-- Create pg_cron extension for archiving
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Create archiving function
CREATE OR REPLACE FUNCTION public.archive_stale_kanban_cards()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Archive BASE "Comprou Há X dias" cards where payment > 60 days ago
  UPDATE public.contatos
  SET status_kanban = 'arquivado', updated_at = now()
  WHERE status_kanban = 'Comprou Há X dias'
    AND updated_at < now() - interval '60 days';

  -- Archive ADS "Sumiu" cards older than 60 days
  UPDATE public.contatos
  SET status_kanban = 'arquivado_sumiu', updated_at = now()
  WHERE status_kanban LIKE '%Sumiu%'
    AND updated_at < now() - interval '60 days';
END;
$$;

-- Schedule daily archiving at 3 AM
SELECT cron.schedule(
  'archive-stale-kanban-cards',
  '0 3 * * *',
  $$SELECT public.archive_stale_kanban_cards()$$
);

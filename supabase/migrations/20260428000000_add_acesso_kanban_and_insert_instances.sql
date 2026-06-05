-- Migration: Add acesso_kanban column to instancias and insert base/ads instances

-- 1. Add acesso_kanban column if it doesn't exist
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='instancias' AND column_name='acesso_kanban') THEN
        ALTER TABLE public.instancias ADD COLUMN acesso_kanban text DEFAULT 'todos' CHECK (acesso_kanban IN ('ads', 'base', 'todos'));
    END IF;
END $$;

-- 2. Insert requested instances
-- We use a subquery to avoid duplicates if the migration is run twice
INSERT INTO public.instancias (nome, tipo, numero_final, ativo, is_default_base, dono_tipo, acesso_kanban)
SELECT 'Instancia BASE', 'base', '0512', true, true, 'admin', 'todos'
WHERE NOT EXISTS (SELECT 1 FROM public.instancias WHERE nome = 'Instancia BASE');

INSERT INTO public.instancias (nome, tipo, numero_final, ativo, is_default_base, dono_tipo, acesso_kanban)
SELECT 'Instancia ADS', 'ads', '2579', true, false, 'admin', 'todos'
WHERE NOT EXISTS (SELECT 1 FROM public.instancias WHERE nome = 'Instancia ADS');

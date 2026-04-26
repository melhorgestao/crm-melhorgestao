-- Rename primeira_venda_em to ultima_venda_em and add FK
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='contatos' AND column_name='primeira_venda_em') THEN
      ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;
  END IF;
END $$;

-- Add FK to ensure data integrity (references itself for representantes)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'contatos_representante_id_fkey'
  ) THEN
    ALTER TABLE public.contatos 
    ADD CONSTRAINT contatos_representante_id_fkey 
    FOREIGN KEY (representante_id) REFERENCES public.contatos(id);
  END IF;
END $$;

-- FORCE SCHEMA RELOAD
NOTIFY pgrst, 'reload schema';
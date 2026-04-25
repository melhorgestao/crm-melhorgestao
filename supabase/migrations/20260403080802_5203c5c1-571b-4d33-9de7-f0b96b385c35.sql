
-- Add representante_id to contatos (references another contato REP)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS representante_id uuid;

-- Add primeira_venda_em to contatos (used by midnight migration function)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS primeira_venda_em timestamptz;

-- Add observacao to pedidos (for notes/obs on pending orders)
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS observacao text;

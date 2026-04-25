-- Adicionar colunas para products customizáveis
BEGIN;

-- 1. Criar tabela de grupos de produtos (se não existir)
CREATE TABLE IF NOT EXISTS public.produtos_grupos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  cor_grupo text,
  ordem integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 2. RLS para grupos (se não existir)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can manage produtos_grupos' AND tablename = 'produtos_grupos'
  ) THEN
    ALTER TABLE public.produtos_grupos ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Authenticated users can manage produtos_grupos" ON public.produtos_grupos FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END
$$;

-- 3. Adicionar coluna grupo_id (opcional, para agrupamento)
ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS grupo_id uuid REFERENCES public.produtos_grupos(id);

-- 4. Adicionar coluna limite_estoque (quantos produtos quer em estoque)
ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS limite_estoque integer DEFAULT 0;

COMMIT;
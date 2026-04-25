-- Adiciona campos de peso e dimensoes aos produtos
ALTER TABLE public.produtos 
ADD COLUMN IF NOT EXISTS peso integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS largura_caixa numeric DEFAULT 11,
ADD COLUMN IF NOT EXISTS altura_caixa numeric DEFAULT 2,
ADD COLUMN IF NOT EXISTS comprimento_caixa numeric DEFAULT 16;

-- Atualiza produtos existentes com peso padrao (300g por unidade)
UPDATE public.produtos SET peso = 300 WHERE peso = 0 OR peso IS NULL;

-- cria indice para performance
CREATE INDEX IF NOT EXISTS idx_produtos_peso ON public.produtos(peso);
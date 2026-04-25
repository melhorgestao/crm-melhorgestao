-- CORRIGIR: uf_cliente em pedidos deve vir da UF do contato
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Verificar se coluna uf_cliente existe em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

-- 2. Popular uf_cliente com a UF do contato (da tabela contatos)
UPDATE public.pedidos p
SET uf_cliente = c.uf
FROM public.contatos c
WHERE p.contato_id = c.id
AND c.uf IS NOT NULL
AND p.uf_cliente IS NULL;

-- 3. Para pedidos sem contato, usar uf_postagem como fallback
UPDATE public.pedidos p
SET uf_cliente = p.uf_postagem
WHERE p.uf_cliente IS NULL
AND p.uf_postagem IS NOT NULL;

-- 4. Verificar resultado
SELECT 
  p.id,
  p.uf_cliente,
  p.uf_postagem,
  c.nome as nome_contato,
  c.uf as uf_contato
FROM public.pedidos p
LEFT JOIN public.contatos c ON c.id = p.contato_id
ORDER BY p.created_at DESC
LIMIT 20;

-- 5. Contagem
SELECT 
  COUNT(*) as total,
  COUNT(uf_cliente) as com_uf_cliente,
  COUNT(uf_postagem) as com_uf_postagem
FROM public.pedidos;

COMMIT;
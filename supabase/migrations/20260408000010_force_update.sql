-- SQL direto para forçar atualização da coluna ultima_venda_em
-- Rode este SQL no Supabase SQL Editor

-- 1. Verifica se a coluna existe
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'contatos' AND column_name = 'ultima_venda_em';

-- 2. Verifica se há pedidos para contatos
SELECT c.id, c.nome, c.canal_origem, c.ultima_venda_em, 
       (SELECT MAX(p.created_at) FROM pedidos p WHERE p.contato_id = c.id) as ultimo_pedido
FROM contatos c
WHERE c.canal_origem IN ('REP', 'C-REP', 'BASE')
LIMIT 20;

-- 3. FORÇA atualização de todos os contatos que têm pedido
UPDATE public.contatos c
SET ultima_venda_em = sub.max_date
FROM (
    SELECT contato_id, MAX(created_at)::date as max_date
    FROM public.pedidos
    GROUP BY contato_id
) sub
WHERE c.id = sub.contato_id;

-- 4. Verifica se atualizou
SELECT c.id, c.nome, c.canal_origem, c.ultima_venda_em
FROM contatos c
WHERE c.canal_origem IN ('REP', 'C-REP', 'BASE') AND c.ultima_venda_em IS NOT NULL
LIMIT 20;
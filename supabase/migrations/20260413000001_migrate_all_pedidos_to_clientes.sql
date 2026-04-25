-- ============================================================
-- Migration Final: Todos os contatos com pedidos -> Clientes
-- Rodar no Supabase SQL Editor
-- ============================================================

-- 1. Primeiro, ver quantos contatos têm pedidos
SELECT 
    'Total de contatos com pedidos pagos' as descricao,
    count(distinct contato_id) as total
FROM pedidos 
WHERE contato_id IS NOT NULL AND status_pagamento = 'pago';

-- 2. Ver quantos estão em cada status_kanban
SELECT 
    canal_origem, 
    canal_atual, 
    status_kanban, 
    count(*) as total
FROM contatos 
WHERE id IN (SELECT contato_id FROM pedidos WHERE status_pagamento = 'pago' AND contato_id IS NOT NULL)
GROUP BY canal_origem, canal_atual, status_kanban
ORDER BY canal_origem, canal_atual, status_kanban;

-- 3. Migra TODOS os contatos com pedidos pagos para Clientes na BASE
-- Isso inclui qualquer canal_origem (ADS, BASE, REP, C-REP, etc)
UPDATE public.contatos
SET 
    status_kanban = 'Clientes',
    -- Se já tem canal_atual, mantém. Se não, usa canal_origem
    canal_atual = COALESCE(NULLIF(canal_atual, ''), canal_origem),
    is_novo = true,
    novo_ate = (CURRENT_DATE + 1)::timestamptz,
    updated_at = now()
WHERE 
    id IN (
        SELECT DISTINCT contato_id 
        FROM public.pedidos 
        WHERE status_pagamento = 'pago' 
        AND contato_id IS NOT NULL
    )
    AND status_kanban != 'Clientes';

-- 4. Ver resultado após migração
SELECT 
    canal_origem, 
    canal_atual, 
    status_kanban, 
    count(*) as total
FROM contatos 
WHERE id IN (SELECT contato_id FROM pedidos WHERE status_pagamento = 'pago' AND contato_id IS NOT NULL)
GROUP BY canal_origem, canal_atual, status_kanban
ORDER BY canal_origem, canal_atual, status_kanban;

-- 5. Verifica total em Clientes vs total com pedidos
SELECT 
    'Contatos com pedidos pagos' as tipo,
    count(distinct contato_id) as total
FROM pedidos 
WHERE contato_id IS NOT NULL AND status_pagamento = 'pago'
UNION ALL
SELECT 
    'Contatos em Clientes' as tipo,
    count(*) as total
FROM contatos 
WHERE status_kanban = 'Clientes';

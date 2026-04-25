-- Recalcular estoque baseado em movimentacoes (entradas - saidas)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Criar tabela de snapshot do estoque atual (backup)
CREATE TABLE IF NOT EXISTS public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id uuid REFERENCES public.produtos(id),
  uf text,
  quantidade_anterior integer,
  quantidade_nova integer,
  diferenca integer,
  created_at timestamptz DEFAULT now()
);

-- 2. Gravar snapshot antes da correcao (backup)
INSERT INTO public.estoque_snapshot (produto_id, uf, quantidade_anterior, quantidade_nova, diferenca)
SELECT 
  l.produto_id,
  l.uf,
  l.quantidade_atual,
  0,
  -l.quantidade_atual
FROM public.lotes l
WHERE l.quantidade_atual > 0;

-- 3. Corrigir movimentacoes negativas (saidas sem entrada correspondente)
-- Primeiro, criar temp table com saldo por produto+UF
CREATE TEMP TABLE estoque_movimentado AS
SELECT 
  produto_id,
  uf_origem,
  SUM(CASE WHEN tipo = 'entrada' THEN quantidade ELSE 0 END) as entradas,
  SUM(CASE WHEN tipo = 'saida' THEN quantidade ELSE 0 END) as saidas,
  SUM(CASE WHEN tipo = 'entrada' THEN quantidade ELSE -quantidade END) as saldo
FROM public.estoque_movimentacoes
WHERE uf_origem IS NOT NULL
GROUP BY produto_id, uf_origem;

-- 4. Atualizar lotes com saldo correto (nao pode ser negativo)
UPDATE public.lotes l
SET quantidade_atual = GREATEST(COALESCE(ec.saldo, 0), 0)
FROM estoque_movimentado ec
WHERE l.produto_id = ec.produto_id AND l.uf = ec.uf_origem;

-- 5. Criar novos lotes para UFs que nao existem mas tem saldo positivo
INSERT INTO public.lotes (produto_id, uf, quantidade_inicial, quantidade_atual, data_producao, lote_codigo, created_at)
SELECT 
  ec.produto_id,
  ec.uf_origem,
  ec.saldo,
  ec.saldo,
  now()::date,
  'AUTO-' || ec.uf_origem || '-' || now()::text,
  now()
FROM estoque_movimentado ec
WHERE ec.saldo > 0
AND NOT EXISTS (SELECT 1 FROM public.lotes l WHERE l.produto_id = ec.produto_id AND l.uf = ec.uf_origem);

-- 6. Excluir lotes com estoque zero ou negativo que nao tem movimentacao
DELETE FROM public.lotes 
WHERE quantidade_atual <= 0 
AND id NOT IN (
  SELECT DISTINCT lote_id FROM public.estoque_movimentacoes WHERE lote_id IS NOT NULL
);

-- 7. Atualizar estoque_atual na tabela produtos (soma total por produto)
UPDATE public.produtos p
SET estoque_atual = COALESCE((
  SELECT SUM(quantidade_atual) 
  FROM public.lotes 
  WHERE produto_id = p.id
), 0);

-- 8. Gravar snapshot apos correcao
INSERT INTO public.estoque_snapshot (produto_id, uf, quantidade_anterior, quantidade_nova, diferenca)
SELECT 
  l.produto_id,
  l.uf,
  es.quantidade_anterior,
  l.quantidade_atual,
  l.quantidade_atual - COALESCE(es.quantidade_anterior, 0)
FROM public.lotes l
LEFT JOIN (
  SELECT produto_id, uf, quantidade_anterior 
  FROM public.estoque_snapshot 
  WHERE quantidade_nova = 0
) es ON l.produto_id = es.produto_id AND l.uf = es.uf
WHERE es.quantidade_anterior IS NOT NULL;

-- 9. Verificar consistencia final
SELECT 
  p.nome_oficial as produto,
  l.uf,
  l.quantidade_atual as estoque_lote,
  COALESCE(em.entradas, 0) as entradas,
  COALESCE(em.saidas, 0) as saidas,
  COALESCE(em.saldo, 0) as saldo_movimentacoes,
  CASE WHEN l.quantidade_atual != COALESCE(em.saldo, 0) THEN 'DIFERENTE' ELSE 'OK' END as status
FROM public.produtos p
LEFT JOIN public.lotes l ON l.produto_id = p.id
LEFT JOIN estoque_movimentado em ON em.produto_id = p.id AND em.uf_origem = l.uf
WHERE l.quantidade_atual > 0 OR em.saldo != 0
ORDER BY p.nome_oficial, l.uf;

COMMIT;
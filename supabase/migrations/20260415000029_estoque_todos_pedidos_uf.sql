-- ESTOQUE DEFINITIVO - TODOS OS PEDIDOS + DIVISÃO POR UF + NEGATIVO
-- Executar TODO de uma vez no Supabase SQL Editor

BEGIN;

-- 0. Dropar funções existentes
DROP FUNCTION IF EXISTS public.get_estoque_completo();

-- 1. Limpar tudo
DELETE FROM estoque_movimentacoes WHERE tipo = 'saida';

-- 2. Criar função que calcula estoque DIRETO da tabela pedidos (TODOS os status)
-- Retorna: estado, entrada, saida, saldo (sem prod_id - agrega por UF)
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada integer,
  saida integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  -- Para cada produto ativo, calcular entrada (lotes) - saida (pedidos) por UF
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas_lotes AS (
    SELECT 
      l.produto_id as pid,
      COALESCE(l.uf, 'SP') as uf_lote,
      SUM(l.quantidade_atual)::integer as total_entrada
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas_pedidos AS (
    SELECT 
      pi.produto_id as pid,
      COALESCE(p.uf_postagem, 'SP') as uf_pedido,
      SUM(pi.quantidade)::integer as total_saida
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  -- Resultado: entrada - saida (pode ser negativo!) por produto + UF
  SELECT 
    COALESCE(el.pid, sp.pid, pa.pid) as prod_id,
    pa.pnome as prod_nome,
    COALESCE(el.uf_lote, sp.uf_pedido, 'SP') as estado,
    COALESCE(el.total_entrada, 0) as entrada,
    COALESCE(sp.total_saida, 0) as saida,
    (COALESCE(el.total_entrada, 0) - COALESCE(sp.total_saida, 0)) as saldo
  FROM produtos_ativos pa
  LEFT JOIN entradas_lotes el ON el.pid = pa.pid
  LEFT JOIN saidas_pedidos sp ON sp.pid = pa.pid
  WHERE el.total_entrada > 0 OR sp.total_saida > 0
  ORDER BY pa.pnome, COALESCE(el.uf_lote, sp.uf_pedido, 'SP');
END;
$$;

-- 3. Testar
SELECT * FROM get_estoque_completo();

-- 4. Ver quantos pedidos foram considerados (TODOS!)
SELECT 
  status_pagamento,
  COUNT(*) as pedidos,
  SUM(quantidade) as total_itens
FROM pedidos 
WHERE produto IS NOT NULL AND produto <> 'geral'
GROUP BY status_pagamento;

-- 5. Ver por UF
SELECT 
  uf_postagem,
  status_pagamento,
  SUM(quantidade) as total
FROM pedidos 
WHERE produto IS NOT NULL AND produto <> 'geral'
GROUP BY uf_postagem, status_pagamento
ORDER BY uf_postagem, status_pagamento;

COMMIT;
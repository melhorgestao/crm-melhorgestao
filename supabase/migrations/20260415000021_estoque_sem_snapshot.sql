-- ESTOQUE SEM SNAPSHOT - Puxa TODOS os pedidos agora (sem cache)
-- Executar no Supabase SQL Editor

BEGIN;

-- 0. Permitir nulo
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado DROP NOT NULL;
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado SET DEFAULT false;

-- Função que calcula direto (SEM snapshot) - lotes - TODOS os pedidos
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
  -- 1. Todos os produtos ativos
  WITH produtos AS (
    SELECT pr.id as pid, pr.nome_oficial as pnome
    FROM public.produtos pr
    WHERE pr.ativo = true
  ),
  -- 2. Todos os lotes por produto+UF
  lotes AS (
    SELECT 
      l.produto_id as pid_lote,
      l.uf as uf_lote,
      SUM(l.quantidade_atual)::integer as qtd_entrada
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, l.uf
  ),
  -- 3. TODOS os pedidos por produto+UF (pagos E pendentes)
  pedidos AS (
    SELECT 
      pi.produto_id as pid_pedido,
      COALESCE(p.uf_postagem, 'SP') as uf_pedido,
      SUM(pi.quantidade)::integer as qtd_saida
    FROM public.pedido_itens pi
    INNER JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  -- Resultado: para CADA produto, mostrar entradas - saidas
  SELECT 
    COALESCE(l.pid_lote, ped.pid_pedido, pr.pid) as prod_id,
    pr.pnome as prod_nome,
    COALESCE(l.uf_lote, ped.uf_pedido, 'SP') as estado,
    COALESCE(l.qtd_entrada, 0)::integer as entrada,
    COALESCE(ped.qtd_saida, 0)::integer as saida,
    (COALESCE(l.qtd_entrada, 0) - COALESCE(ped.qtd_saida, 0))::integer as saldo
  FROM produtos pr
  LEFT JOIN lotes l ON l.pid_lote = pr.pid
  LEFT JOIN pedidos ped ON ped.pid_pedido = pr.pid
  WHERE l.qtd_entrada > 0 OR ped.qtd_saida > 0
  ORDER BY pr.pnome, COALESCE(l.uf_lote, ped.uf_pedido, 'SP');
END;
$$;

-- Testar agora - sem snapshot!
SELECT * FROM get_estoque_completo();

-- Ver quantos pedidos foram considerados
SELECT 
  COUNT(DISTINCT p.id) as total_pedidos,
  SUM(pi.quantidade) as total_itens
FROM public.pedidos p
INNER JOIN public.pedido_itens pi ON pi.pedido_id = p.id
WHERE p.status_pagamento IS NOT NULL;

COMMIT;
-- ============================================================================
-- unidades_por_grupo: unidades por grupo × canal × free (aba Operacional).
--
-- Alimenta PRODUTOS por grupo (Total, ADS, Base, Rep, Free) e o CPA Un. ADS
-- por grupo (ADS_grupo ÷ unidades ADS do grupo).
--
-- Definições alinhadas às Métricas atuais:
--   • pago = itens de pedidos NÃO-free, status pago|pendente, por `data`,
--     item.is_free = false → contam por canal (ADS/BASE/REP).
--   • free = itens de reposição (item.is_free em pedido normal) + TODOS os
--     itens de pedidos WHOLE-FREE (por `data_pago`, como o Prod. Free global).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.unidades_por_grupo(p_inicio text, p_fim text)
RETURNS TABLE (grupo_id uuid, ads numeric, base numeric, rep numeric, free numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH venda AS (  -- itens de pedidos NÃO-free (pago|pendente), por data
    SELECT pr.grupo_id, p.canal, pi.is_free, pi.quantidade AS qtd
      FROM public.pedido_itens pi
      JOIN public.pedidos  p  ON p.id  = pi.pedido_id
      JOIN public.produtos pr ON pr.id = pi.produto_id
     WHERE p.is_free IS DISTINCT FROM true
       AND p.status_pagamento IN ('pago', 'pendente')
       AND p.data::date >= p_inicio::date
       AND p.data::date <  p_fim::date
  ),
  free_order AS (  -- itens de pedidos WHOLE-FREE, por data_pago
    SELECT pr.grupo_id, pi.quantidade AS qtd
      FROM public.pedido_itens pi
      JOIN public.pedidos  p  ON p.id  = pi.pedido_id
      JOIN public.produtos pr ON pr.id = pi.produto_id
     WHERE p.is_free = true
       AND p.data_pago::date >= p_inicio::date
       AND p.data_pago::date <  p_fim::date
  ),
  agg AS (
    SELECT grupo_id,
           SUM(CASE WHEN NOT is_free AND canal = 'ADS'  THEN qtd ELSE 0 END) AS ads,
           SUM(CASE WHEN NOT is_free AND canal = 'BASE' THEN qtd ELSE 0 END) AS base,
           SUM(CASE WHEN NOT is_free AND canal = 'REP'  THEN qtd ELSE 0 END) AS rep,
           SUM(CASE WHEN is_free THEN qtd ELSE 0 END) AS free_mix
      FROM venda GROUP BY grupo_id
  ),
  fo AS (
    SELECT grupo_id, SUM(qtd) AS free_ord FROM free_order GROUP BY grupo_id
  )
  SELECT COALESCE(a.grupo_id, fo.grupo_id)                       AS grupo_id,
         COALESCE(a.ads, 0)::numeric                              AS ads,
         COALESCE(a.base, 0)::numeric                             AS base,
         COALESCE(a.rep, 0)::numeric                              AS rep,
         (COALESCE(a.free_mix, 0) + COALESCE(fo.free_ord, 0))::numeric AS free
    FROM agg a
    FULL OUTER JOIN fo ON fo.grupo_id = a.grupo_id;
$$;

GRANT EXECUTE ON FUNCTION public.unidades_por_grupo(text, text)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- CUSTO E LUCRO POR GRUPO DE PRODUTO
--
-- Grupos (produtos_grupos) já existem. Este passo liga CUSTO e RECEITA a eles.
--
-- Regras (definidas com o dono):
--   • MATERIAL: custo divisível — lançado com grupo obrigatório (financeiro.grupo_id).
--   • ADS, Etiqueta, Logística, Influencer, Infra: COMPARTILHADOS — rateados por
--     RECEITA entre os grupos (feito no cliente/Métricas, não aqui).
--   • Lucro_grupo = Receita_grupo − Material_grupo − (Compartilhado × Receita_grupo/Receita_total).
--     Assim Σ Lucro_grupo = Lucro_total (rateio proporcional, sem inflar).
--
-- IMPORTANTE (achado): pedido_itens.preco é gravado como 0 no fluxo principal —
-- não serve pra valorizar item. Então a receita por grupo é atribuída pelo PESO
-- de produtos.preco × quantidade dos itens do pedido (fallback: quantidade).
-- O valor distribuído é a venda real do pedido (valor_original − desconto_total),
-- então o desconto já entra rateado e Σ receita_grupo = Faturamento do período.
-- ============================================================================

-- 1) Coluna de grupo no financeiro (só material usa; resto fica NULL) ---------
ALTER TABLE public.financeiro
  ADD COLUMN IF NOT EXISTS grupo_id uuid REFERENCES public.produtos_grupos(id);

CREATE INDEX IF NOT EXISTS idx_financeiro_grupo
  ON public.financeiro (grupo_id)
  WHERE grupo_id IS NOT NULL;

COMMENT ON COLUMN public.financeiro.grupo_id IS
  'Grupo de produto do custo. Preenchido só em MATERIAL (obrigatório na UI). ADS/etiqueta/logística/etc são compartilhados e ficam NULL.';

-- 2) Backfill: material histórico sem grupo → grupo "Medicinal" ---------------
DO $$
DECLARE v_medicinal uuid; v_n int;
BEGIN
  SELECT id INTO v_medicinal
    FROM public.produtos_grupos
   WHERE lower(btrim(nome)) = 'medicinal'
   ORDER BY created_at ASC LIMIT 1;

  IF v_medicinal IS NULL THEN
    RAISE NOTICE 'Grupo "Medicinal" não encontrado — backfill de material pulado.';
  ELSE
    UPDATE public.financeiro
       SET grupo_id = v_medicinal
     WHERE categoria = 'material'
       AND grupo_id IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'Backfill material→Medicinal: % lançamentos.', v_n;
  END IF;
END $$;

-- 3) RPC: receita (e unidades) por grupo no período --------------------------
--    Mesmos filtros das Métricas (is_free!=true, status pago|pendente, por data).
--    Distribui a venda real de cada pedido entre grupos por peso preco×qtd.
CREATE OR REPLACE FUNCTION public.receita_por_grupo(p_inicio text, p_fim text)
RETURNS TABLE (grupo_id uuid, grupo_nome text, receita numeric, unidades numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH ped_ok AS (
    SELECT p.id,
           (COALESCE(p.valor_original, p.valor, 0) - COALESCE(p.desconto_total, 0)) AS venda_real
      FROM public.pedidos p
     WHERE p.is_free IS DISTINCT FROM true
       AND p.status_pagamento IN ('pago', 'pendente')
       AND p.data::date >= p_inicio::date
       AND p.data::date <  p_fim::date
       AND (COALESCE(p.valor_original, p.valor, 0) - COALESCE(p.desconto_total, 0)) > 0
  ),
  -- itens do pedido: pedido_itens; fallback pro produto_id do próprio pedido
  -- quando o pedido não tem itens (pedidos legados).
  itens AS (
    SELECT pi.pedido_id, pi.produto_id, pi.quantidade
      FROM public.pedido_itens pi
     WHERE pi.pedido_id IN (SELECT id FROM ped_ok)
    UNION ALL
    SELECT po.id, p.produto_id, COALESCE(p.quantidade, 1)
      FROM ped_ok po
      JOIN public.pedidos p ON p.id = po.id
     WHERE p.produto_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi2 WHERE pi2.pedido_id = po.id)
  ),
  grp AS (   -- peso por pedido × grupo
    SELECT it.pedido_id,
           pr.grupo_id,
           SUM(COALESCE(pr.preco, 0) * it.quantidade) AS peso,
           SUM(it.quantidade)                          AS qtd
      FROM itens it
      JOIN public.produtos pr ON pr.id = it.produto_id
     GROUP BY it.pedido_id, pr.grupo_id
  ),
  tot AS (   -- total por pedido (pra achar a fração do grupo)
    SELECT pedido_id, SUM(peso) AS peso_total, SUM(qtd) AS qtd_total
      FROM grp GROUP BY pedido_id
  )
  SELECT grp.grupo_id,
         COALESCE(g.nome, 'Sem grupo') AS grupo_nome,
         SUM(
           po.venda_real *
           CASE WHEN tot.peso_total > 0 THEN grp.peso / tot.peso_total
                WHEN tot.qtd_total  > 0 THEN grp.qtd::numeric / tot.qtd_total
                ELSE 0 END
         )::numeric AS receita,
         SUM(grp.qtd)::numeric AS unidades
    FROM grp
    JOIN tot   ON tot.pedido_id = grp.pedido_id
    JOIN ped_ok po ON po.id     = grp.pedido_id
    LEFT JOIN public.produtos_grupos g ON g.id = grp.grupo_id
   GROUP BY grp.grupo_id, g.nome
   ORDER BY receita DESC;
$$;

GRANT EXECUTE ON FUNCTION public.receita_por_grupo(text, text)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

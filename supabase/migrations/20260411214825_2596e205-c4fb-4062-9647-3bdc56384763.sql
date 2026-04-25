
-- 1. Fix atualizar_estoque_snapshot: column is "updated_at" not "atualizado_em"
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
  SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now() FROM public.calcular_estoque();
  UPDATE public.produtos p SET estoque_atual = COALESCE((SELECT SUM(saldo) FROM public.estoque_snapshot WHERE prod_id = p.id), 0) WHERE p.id IS NOT NULL;
END;
$function$;

-- 2. Remove duplicate triggers that cause double stock deductions
DROP TRIGGER IF EXISTS tg_abate_estoque_pedido ON public.pedidos;
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;

-- 3. Fix calcular_estoque to use estoque_movimentacoes as single source of truth
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH movimentacao_resumo AS (
    SELECT 
      em.produto_id as pid,
      TRIM(UPPER(COALESCE(em.uf_origem, em.posse, 'SP'))) as uff,
      SUM(CASE WHEN em.tipo = 'entrada' THEN em.quantidade ELSE 0 END)::int as qtd_ent,
      SUM(CASE WHEN em.tipo = 'saida' THEN em.quantidade ELSE 0 END)::int as qtd_sai
    FROM public.estoque_movimentacoes em
    WHERE em.produto_id IS NOT NULL 
      AND em.quantidade > 0
    GROUP BY em.produto_id, TRIM(UPPER(COALESCE(em.uf_origem, em.posse, 'SP')))
  )
  SELECT 
    mr.pid as prod_id,
    p.nome_oficial as prod_nome,
    mr.uff as estado,
    mr.qtd_ent as entrada,
    mr.qtd_sai as saida,
    (mr.qtd_ent - mr.qtd_sai) as saldo
  FROM movimentacao_resumo mr
  JOIN public.produtos p ON p.id = mr.pid
  WHERE p.ativo = true
    AND (mr.qtd_ent <> 0 OR mr.qtd_sai <> 0)
  ORDER BY p.nome_oficial, mr.uff;
END;
$function$;

-- 4. Recalculate all products stock from movements
DO $$
DECLARE
  v_prod record;
  v_entradas numeric;
  v_saidas numeric;
BEGIN
  FOR v_prod IN SELECT id FROM public.produtos LOOP
    SELECT COALESCE(SUM(quantidade), 0) INTO v_entradas FROM public.estoque_movimentacoes WHERE produto_id = v_prod.id AND tipo = 'entrada';
    SELECT COALESCE(SUM(quantidade), 0) INTO v_saidas FROM public.estoque_movimentacoes WHERE produto_id = v_prod.id AND tipo = 'saida';
    UPDATE public.produtos SET estoque_atual = v_entradas - v_saidas WHERE id = v_prod.id;
  END LOOP;
END $$;

-- 5. Refresh snapshot
SELECT public.atualizar_estoque_snapshot();

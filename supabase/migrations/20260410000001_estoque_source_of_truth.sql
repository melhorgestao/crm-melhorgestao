-- ESTOQUE: FONTE DA VERDADE ÚNICA (MOVIMENTAÇÕES)
-- 1. Normaliza siglas de UF (remove espaços e padroniza maiúsculas)
-- 2. Reescreve get_estoque_completo para usar APENAS estoque_movimentacoes
-- 3. Garante que os cards batam 100% com a lista de movimentações

BEGIN;

-- 1. NORMALIZAÇÃO: Limpa sujeira nas siglas de UF
UPDATE public.estoque_movimentacoes SET uf_origem = TRIM(UPPER(uf_origem)) WHERE uf_origem IS NOT NULL;
UPDATE public.estoque_movimentacoes SET posse = TRIM(UPPER(posse)) WHERE posse IS NOT NULL;
UPDATE public.lotes SET uf = TRIM(UPPER(uf)) WHERE uf IS NOT NULL;
UPDATE public.pedidos SET uf_postagem = TRIM(UPPER(uf_postagem)) WHERE uf_postagem IS NOT NULL;

-- 2. REESCRITA DA FUNÇÃO: get_estoque_completo
-- Agora baseada 100% no histórico de movimentações para evitar "lançamentos fantasma" ou divergências
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
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
$$;

-- 3. REPROCESSO: Atualiza estoque_atual dos produtos e snapshot
DO $$
DECLARE
  v_rec record;
BEGIN
  FOR v_rec IN SELECT id FROM public.produtos LOOP
    UPDATE public.produtos p
    SET estoque_atual = (
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = 'entrada'), 0) -
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = 'saida'), 0)
    )
    WHERE p.id = v_rec.id;
  END LOOP;
END $$;

-- 4. SNAPSHOT: Recria a tabela de snapshot para garantir consistência total
DROP TABLE IF EXISTS public.estoque_snapshot;
CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  prod_id uuid REFERENCES public.produtos(id),
  prod_nome text,
  estado text,
  entrada integer DEFAULT 0,
  saida integer DEFAULT 0,
  saldo integer DEFAULT 0,
  updated_at timestamptz DEFAULT now()
);

-- Popular snapshot
INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now() FROM get_estoque_completo();

COMMIT;

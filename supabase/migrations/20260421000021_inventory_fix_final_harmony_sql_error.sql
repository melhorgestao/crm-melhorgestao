-- INVENTORY FIX V17 FINAL HARMONY E SNAPSHOT (CORRECAO SCHEMA E DADOS)
-- Esta versão unifica de vez o Card com a Lista (7 CBDs) corrigindo os nomes das colunas da tabela de snapshot.

BEGIN;

-- 1. GARANTIR A FUNÇÃO DE SNAPSHOT (Performance Futura)
-- Ajusta para os nomes reais de colunas em estoque_snapshot: prod_id, prod_nome, estado, etc.
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM public.estoque_snapshot;
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    SELECT 
        m.produto_id,
        (SELECT nome_oficial FROM public.produtos WHERE id = m.produto_id),
        LEFT(UPPER(TRIM(COALESCE(m.uf_origem, 'SP'))), 2) as uff,
        SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END)::int as qtd_ent,
        SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END)::int as qtd_sai,
        (SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END) - SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END))::int as saldo_final,
        NOW()
    FROM public.estoque_movimentacoes m
    WHERE m.produto_id IS NOT NULL
    GROUP BY m.produto_id, uff;
END;
$$;

-- 2. UNIFICAR CARDS COM A LISTA CERTA (Fim da divergência)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT m.prod_id, m.prod_nome, m.estado, m.entrada::int, m.saida::int, m.saldo::int
  FROM public.estoque_snapshot m
  ORDER BY m.prod_nome, m.estado;
END;
$$;

-- 3. AJUSTE NA ORDENAÇÃO DOS PEDIDOs (Para o frontend pegar a data correta)
-- Garante que o campo 'data' sempre exista para ordenação se for null
ALTER TABLE public.estoque_movimentacoes ALTER COLUMN data SET DEFAULT NOW();
UPDATE public.estoque_movimentacoes SET data = created_at WHERE data IS NULL;

-- Executa a atualização inicial para o card bater com a lista IMEDIATAMENTE
SELECT public.atualizar_estoque_snapshot();

COMMIT;

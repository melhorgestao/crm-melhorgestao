-- INVENTORY FIX V17 - HARMONIA FINAL E SNAPSHOTS
-- Esta versão unifica de vez o Card com a Lista (7 CBDs) e prepara para alta performance.

BEGIN;

-- 1. GARANTIR A FUNÇÃO DE SNAPSHOT (Performance Futura)
-- Esta função consolida as movimentações em um saldo fixo para leitura rápida.
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Limpa o snapshot atual
    DELETE FROM public.estoque_snapshot;

    -- Insere o novo saldo calculado a partir da tabela estoque_movimentacoes (A nova fonte da verdade)
    INSERT INTO public.estoque_snapshot (produto_id, uf, entrada, saida, saldo, last_updated)
    SELECT 
        m.produto_id,
        LEFT(UPPER(TRIM(COALESCE(m.uf_origem, 'SP'))), 2) as uff,
        SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END)::int as qtd_ent,
        SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END)::int as qtd_sai,
        (SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END) - SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END))::int as saldo_final,
        NOW()
    FROM public.estoque_movimentacoes m
    GROUP BY m.produto_id, uff;
END;
$$;

-- 2. UNIFICAÇÃO DO RPC DOS CARDS COM O SNAPSHOT/MOVIMENTAÇÕES
-- Como a lista de movimentações agora está 100% correta (7 CBDs), os cards devem lê-la diretamente.
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as prod_id,
    p.nome_oficial as prod_nome,
    m.uf as estado,
    m.entrada::int as entrada,
    m.saida::int as saida,
    m.saldo::int as saldo
  FROM public.estoque_snapshot m
  JOIN public.produtos p ON p.id = m.produto_id
  ORDER BY p.nome_oficial, m.uf;
END;
$$;

-- 3. AJUSTE NA ORDENAÇÃO DOS PEDIDOs (Para o frontend pegar a data correta)
-- Garante que o campo 'data' sempre exista para ordenação
ALTER TABLE public.estoque_movimentacoes ALTER COLUMN data SET DEFAULT NOW();

-- Executa a atualização inicial para o card bater com a lista IMEDIATAMENTE
SELECT public.atualizar_estoque_snapshot();

COMMIT;

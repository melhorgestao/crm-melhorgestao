-- CRIAR LISTA DE SAÍDA AUTOMATICAMENTE + ESTOQUE
-- Executar TODO de uma vez no Supabase SQL Editor

BEGIN;

-- 0. Dropar funções existentes
DROP FUNCTION IF EXISTS public.gerar_movimentacoes_saida();
DROP FUNCTION IF EXISTS public.get_estoque_completo();

-- 1. Limpar movimentações de saída existentes
DELETE FROM estoque_movimentacoes WHERE tipo = 'saida';

-- 2. Criar função que gera movimentações de saída de TODOS os pedidos
CREATE OR REPLACE FUNCTION public.gerar_movimentacoes_saida()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido RECORD;
  v_uf TEXT;
BEGIN
  -- Para cada pedido pago, criar uma movimentação de saída
  FOR v_pedido IN
    SELECT id, uf_postagem, quantidade, produto
    FROM pedidos
    WHERE status_pagamento = 'pago'
    AND produto IS NOT NULL
    AND produto <> 'geral'
  LOOP
    -- Determinar UF
    v_uf := COALESCE(v_pedido.uf_postagem, 'SP');
    
    -- Inserir movimentação de saída
    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
    SELECT 
      p.id as produto_id,
      v_pedido.quantidade as quantidade,
      'saida' as tipo,
      'Venda' as posse,
      v_uf as uf_origem,
      v_pedido.id as pedido_id,
      'Pedido #' || v_pedido.id::text as observacao
    FROM produtos p
    WHERE p.ativo = true
    LIMIT 1;
  END LOOP;
END;
$$;

-- 3. Criar função get_estoque_completo que lê das movimentações
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH ent AS (
    SELECT COALESCE(uf, 'SP') as uff, SUM(quantidade_atual)::int as qtd
    FROM lotes WHERE quantidade_atual > 0 GROUP BY COALESCE(uf, 'SP')
  ),
  sai AS (
    SELECT COALESCE(uf_origem, 'SP') as uff, SUM(quantidade)::int as qtd
    FROM estoque_movimentacoes WHERE tipo = 'saida' GROUP BY COALESCE(uf_origem, 'SP')
  )
  SELECT e.uff, e.qtd, COALESCE(s.qtd, 0), (e.qtd - COALESCE(s.qtd, 0))
  FROM ent e LEFT JOIN sai s ON s.uff = e.uff;
END;
$$;

-- 4. Gerar movimentações de saída
SELECT public.gerar_movimentacoes_saida();

-- 5. Ver resultado - lista de movimentações
SELECT * FROM estoque_movimentacoes WHERE tipo = 'saida' ORDER BY created_at DESC;

-- 6. Ver estoque
SELECT * FROM get_estoque_completo();

COMMIT;
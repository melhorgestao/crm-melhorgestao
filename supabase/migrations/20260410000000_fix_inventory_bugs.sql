-- CORREÇÃO DE BUGS NO ESTOQUE E SCHEMA DE MOVIMENTAÇÕES
-- 1. Adiciona coluna criado_por
-- 2. Corrige get_estoque_completo (JOIN por UF)
-- 3. Atualiza criar_lote_estoque (nome do criador)
-- 4. Reprocessa estoque_atual e snapshot

BEGIN;

-- 1. SCHEMA: Adiciona coluna criado_por em estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS criado_por text;

-- 2. RPC: get_estoque_completo (CORREGIDA PARA NÃO DUPLICAR UF)
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_atual)::int as qtd_ent
    FROM public.lotes l 
    WHERE l.quantidade_atual > 0 
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas_produto_id AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, p.quantidade as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL
  ),
  itens_json AS (
    SELECT 
      (jsonb_array_elements(p.produto::jsonb)->>'produto_id')::uuid as pid,
      COALESCE(p.uf_postagem, 'SP') as uff,
      (jsonb_array_elements(p.produto::jsonb)->>'quantidade')::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto LIKE '[%'
  ),
  todas_saidas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM saidas_produto_id WHERE pid IS NOT NULL GROUP BY pid, uff
    UNION ALL
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM itens_json WHERE pid IS NOT NULL GROUP BY pid, uff
  ),
  saidas AS (
    SELECT pid, uff, SUM(qtd_sai)::int as qtd_sai FROM todas_saidas GROUP BY pid, uff
  ),
  estoque_por_uf AS (
    SELECT 
      COALESCE(e.pid, s.pid) as pid,
      COALESCE(e.uff, s.uff) as uff,
      COALESCE(e.qtd_ent, 0) as qtd_ent,
      COALESCE(s.qtd_sai, 0) as qtd_sai
    FROM entradas e
    FULL OUTER JOIN saidas s ON e.pid = s.pid AND e.uff = s.uff
  )
  SELECT 
    epu.pid as prod_id,
    pr.pnome as prod_nome,
    epu.uff as estado,
    epu.qtd_ent::int as entrada,
    epu.qtd_sai::int as saida,
    (epu.qtd_ent - epu.qtd_sai)::int as saldo
  FROM estoque_por_uf epu
  JOIN produtos_ativos pr ON pr.pid = epu.pid
  WHERE epu.qtd_ent > 0 OR epu.qtd_sai > 0
  ORDER BY pr.pnome, epu.uff;
END;
$$;

-- 3. RPC: criar_lote_estoque (SUPORTE A CRIADO_POR)
CREATE OR REPLACE FUNCTION public.criar_lote_estoque(
  p_produto_id uuid,
  p_uf text,
  p_quantidade integer,
  p_criado_por text DEFAULT 'Sistema'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_lote_id uuid;
  v_lote_codigo text;
  v_today text;
  v_seq integer;
  v_last text;
  v_prod record;
BEGIN
  -- Gerar codigo do lote
  v_today := to_char(now(), 'YYYYMMDD');
  SELECT COALESCE(MAX(lote_codigo), '') INTO v_last FROM lotes WHERE lote_codigo LIKE 'LOTE-' || v_today || '-%';
  IF v_last <> '' THEN
    v_seq := COALESCE(NULLIF(split_part(v_last, '-', 3), '')::integer, 0) + 1;
  ELSE
    v_seq := 1;
  END IF;
  v_lote_codigo := 'LOTE-' || v_today || '-' || lpad(v_seq::text, 3, '0');

  -- Buscar produto
  SELECT * INTO v_prod FROM produtos WHERE id = p_produto_id;
  IF v_prod IS NULL THEN
    RETURN jsonb_build_object('error', 'produto nao encontrado');
  END IF;

  -- Criar lote
  INSERT INTO lotes (produto_id, uf, quantidade_inicial, quantidade_atual, lote_codigo)
  VALUES (p_produto_id, p_uf, p_quantidade, p_quantidade, v_lote_codigo)
  RETURNING id INTO v_lote_id;

  -- Atualizar estoque real do produto (vai ser recalculado abaixo mas mantemos o padrao)
  UPDATE produtos SET estoque_atual = estoque_atual + p_quantidade WHERE id = p_produto_id;

  -- Registrar movimentacao com criado_por
  INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, lote_id, criado_por)
  VALUES (p_produto_id, p_quantidade, 'entrada', p_uf, p_uf, v_lote_id, p_criado_por);

  RETURN jsonb_build_object('status', 'ok', 'lote_codigo', v_lote_codigo, 'lote_id', v_lote_id::text);
END;
$$;

-- 4. DATA FIX: Vincular Pedido #9 se estiver sem vínculo
UPDATE public.estoque_movimentacoes em
SET pedido_id = p.id
FROM public.pedidos p
WHERE em.pedido_id IS NULL 
  AND (em.observacao LIKE '%Pedido #9%' OR em.observacao LIKE '%#9%')
  AND p.order_number = '9';

-- 5. MANUTENÇÃO: Recalcular estoque_atual baseado em movimentações reais
-- Isso limpa erros de conta acumulados
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

-- 6. SNAPSHOT: Atualizar tabela de snapshot se existir
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'estoque_snapshot') THEN
    DELETE FROM public.estoque_snapshot;
    INSERT INTO public.estoque_snapshot (produto_id, estado, entrada, saida, saldo, updated_at)
    SELECT prod_id, estado, entrada, saida, saldo, now() FROM get_estoque_completo();
  END IF;
END $$;

COMMIT;

-- ESTOQUE COMPLETO: TODOS os pedidos + TODOS os produtos do JSON array + TRIGGER AUTOMÁTICO
-- Executar TODO no Supabase SQL Editor

BEGIN;

-- 1. Resetar estoque_processado
UPDATE public.pedidos SET estoque_processado = false;

-- 2. Dropar função existente
DROP FUNCTION IF EXISTS public.get_estoque_completo();

-- 3. Criar função get_estoque_completo()
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
  -- Todas as saídas: produto_id direto + TODOS itens do JSON
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
  )
  SELECT 
    COALESCE(e.pid, s.pid) as prod_id,
    pr.pnome as prod_nome,
    COALESCE(e.uff, s.uff, 'SP') as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM produtos_ativos pr
  LEFT JOIN entradas e ON e.pid = pr.pid
  LEFT JOIN saidas s ON s.pid = pr.pid
  WHERE COALESCE(e.qtd_ent, 0) > 0 OR COALESCE(s.qtd_sai, 0) > 0
  ORDER BY pr.pnome, COALESCE(e.uff, s.uff, 'SP');
END;
$$;

-- 4. Criar trigger automático para novos pedidos
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque();
CREATE OR REPLACE FUNCTION public.trigger_novo_pedido_estoque()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_item jsonb;
  v_produto_id uuid;
  v_qtd integer;
  v_uf text;
BEGIN
  -- Verificar se é INSERT e se tem produto
  IF TG_OP = 'INSERT' AND NEW.produto IS NOT NULL AND NEW.produto <> 'geral' THEN
    v_uf := COALESCE(NEW.uf_postagem, 'SP');
    
    -- Se tem produto_id direto (1 item)
    IF NEW.produto_id IS NOT NULL THEN
      INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
      VALUES (NEW.produto_id, NEW.quantidade, 'saida', 'Venda', v_uf, NEW.id, 'Pedido #' || NEW.id::text);
    
    -- Se tem JSON array (múltiplos itens)
    ELSIF NEW.produto LIKE '[%' THEN
      FOR v_item IN SELECT jsonb_array_elements(NEW.produto::jsonb)
      LOOP
        v_produto_id := (v_item->>'produto_id')::uuid;
        v_qtd := (v_item->>'quantidade')::int;
        
        IF v_produto_id IS NOT NULL THEN
          INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
          VALUES (v_produto_id, v_qtd, 'saida', 'Venda', v_uf, NEW.id, 'Pedido #' || NEW.id::text);
        END IF;
      END LOOP;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 5. Criar/atualizar trigger
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
CREATE TRIGGER trg_novo_pedido_estoque
  AFTER INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_novo_pedido_estoque();

-- 6. Criar movimentações históricas (executar uma vez)
CREATE OR REPLACE FUNCTION public.criar_movimentacoes_saida()
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido record;
  v_item jsonb;
  v_produto_id uuid;
  v_qtd integer;
  v_uf text;
  v_encontrado boolean;
BEGIN
  FOR v_pedido IN
    SELECT p.id, p.produto, p.produto_id, p.quantidade, COALESCE(p.uf_postagem, 'SP') as uf
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL 
      AND p.produto IS NOT NULL 
      AND p.produto <> 'geral'
  LOOP
    v_uf := v_pedido.uf;
    
    IF v_pedido.produto_id IS NOT NULL THEN
      SELECT EXISTS (
        SELECT 1 FROM public.estoque_movimentacoes em 
        WHERE em.observacao LIKE 'Pedido #' || v_pedido.id::text
      ) INTO v_encontrado;
      
      IF NOT v_encontrado THEN
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
        VALUES (v_pedido.produto_id, v_pedido.quantidade, 'saida', 'Venda', v_uf, v_pedido.id, 'Pedido #' || v_pedido.id::text);
      END IF;
    
    ELSIF v_pedido.produto LIKE '[%' THEN
      FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb)
      LOOP
        v_produto_id := (v_item->>'produto_id')::uuid;
        v_qtd := (v_item->>'quantidade')::int;
        
        SELECT EXISTS (
          SELECT 1 FROM public.estoque_movimentacoes em 
          WHERE em.observacao LIKE 'Pedido #' || v_pedido.id::text
        ) INTO v_encontrado;
        
        IF NOT v_encontrado AND v_produto_id IS NOT NULL THEN
          INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
          VALUES (v_produto_id, v_qtd, 'saida', 'Venda', v_uf, v_pedido.id, 'Pedido #' || v_pedido.id::text);
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- 7. Executar criação de movimentações históricas
SELECT criar_movimentacoes_saida();

-- 8. Testar
SELECT * FROM get_estoque_completo() ORDER BY prod_nome, estado;

SELECT tipo, COUNT(*) FROM public.estoque_movimentacoes GROUP BY tipo;

COMMIT;
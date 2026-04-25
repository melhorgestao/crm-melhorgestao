-- LIMPAR COMPLETAMENTE ESTOQUE E RECRIAR FLUXO
-- Executar no Supabase SQL Editor

BEGIN;

-- 0. Deletar tabela snapshot se existir
DROP TABLE IF EXISTS public.estoque_snapshot;

-- 1. LIMPAR todas as movimentacoes de estoque
TRUNCATE public.estoque_movimentacoes RESTART IDENTITY CASCADE;

-- 2. LIMPAR lotes (zerar estoque)
TRUNCATE public.lotes RESTART IDENTITY CASCADE;

-- 3. Atualizar produtos para estoque_atual = 0
UPDATE public.produtos SET estoque_atual = 0;

-- 4. Criar tabela de controle para saber quais pedidos ja processaram estoque
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean DEFAULT false;

-- 5. Criar trigger function para abater estoque ao criar pedido
CREATE OR REPLACE FUNCTION public.trigger_abate_estoque_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_postagem text;
  v_mov_exists boolean;
BEGIN
  -- So processa se ainda nao foi processado
  IF NEW.estoque_processado = true OR NEW.estoque_processado IS NULL THEN
    RETURN NEW;
  END IF;

  -- Busca UF de postagem do pedido
  v_uf_postagem := NEW.uf_postagem;
  
  IF v_uf_postagem IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_postagem
    FROM contatos ct
    WHERE ct.id = NEW.contato_id;
  END IF;

  -- Loop nos itens do pedido
  FOR v_item IN
    SELECT * FROM pedido_itens WHERE pedido_id = NEW.id
  LOOP
    -- IDEMPOTENCIA: verifica se ja existe movimentacao
    SELECT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id
    ) INTO v_mov_exists;
    
    IF v_mov_exists THEN
      CONTINUE;
    END IF;

    -- FIFO deduction dos lotes (prioriza UF do cliente)
    v_remaining := v_item.quantidade;
    
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_postagem, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN
        EXIT;
      END IF;
      
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      
      -- Atualiza lote
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      
      -- Registra movimentacao
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, pedido_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, NEW.id, 'Pedido #' || NEW.id::text);
      
      v_remaining := v_remaining - v_deduct;
    END LOOP;
  END LOOP;

  -- Marcar como processado
  NEW.estoque_processado := true;
  
  RETURN NEW;
END;
$$;

-- 6. Criar trigger
DROP TRIGGER IF EXISTS tg_abate_estoque_pedido ON public.pedidos;
CREATE TRIGGER tg_abate_estoque_pedido
  BEFORE INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_abate_estoque_pedido();

-- 7. Recriar funcao processar_pedido_estoque_trigger para uso manual
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(p_pedido_id uuid, p_uf_postagem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_total_items integer := 0;
  v_processed_items integer := 0;
BEGIN
  v_uf_cliente := p_uf_postagem;
  
  IF v_uf_cliente IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct
    WHERE ct.id = (SELECT contato_id FROM pedidos WHERE id = p_pedido_id);
  END IF;

  FOR v_item IN
    SELECT * FROM pedido_itens WHERE pedido_id = p_pedido_id
  LOOP
    v_total_items := v_total_items + 1;

    SELECT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id
    ) INTO v_mov_exists;

    IF v_mov_exists THEN
      CONTINUE;
    END IF;

    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, pedido_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, p_pedido_id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    v_processed_items := v_processed_items + 1;
  END LOOP;

  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'total_items', v_total_items,
    'processed', v_processed_items
  );
END;
$$;

COMMIT;

-- Verificar resultado
SELECT 'estoque_movimentacoes' as tabela, COUNT(*) as total FROM public.estoque_movimentacoes
UNION ALL
SELECT 'lotes', COUNT(*) FROM public.lotes
UNION ALL
SELECT 'produtos com estoque_atual=0', COUNT(*) FROM public.produtos WHERE estoque_atual = 0;
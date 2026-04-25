-- REGENERAR MOVIMENTAÇÕES DE MUDANÇA DE UF (Histórico)
-- Executar NO Supabase SQL Editor

BEGIN;

-- 1. Criar função para detectar mudanças de UF via logs ou histórico
-- Como não temos logs, vamos verificar se há pedidos que mudaram de UF
-- Mas se o trigger não disparou, não há como saber... 

-- 2. Criar função para registrar mudança de UF manualmente
CREATE OR REPLACE FUNCTION public.registrar_mudanca_uf(
  p_pedido_id uuid,
  p_uf_antiga text,
  p_uf_nova text
)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $BODY$
DECLARE
  v_item jsonb; v_prod_id uuid; v_qty integer;
BEGIN
  -- Entrada (devolução) na UF antiga
  FOR v_item IN SELECT * FROM jsonb_array_elements((SELECT produto FROM pedidos WHERE id = p_pedido_id)::jsonb) LOOP
    v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
    v_qty := (v_item->>'quantidade')::integer;
    IF v_prod_id IS NOT NULL AND v_qty > 0 THEN
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
      VALUES (v_prod_id, v_qty, 'entrada', 'Devolução', p_uf_antiga, p_pedido_id, 'Mudança UF: ' || p_uf_antiga || ' → ' || p_uf_nova);
    END IF;
  END LOOP;
  
  -- Saída na UF nova
  FOR v_item IN SELECT * FROM jsonb_array_elements((SELECT produto FROM pedidos WHERE id = p_pedido_id)::jsonb) LOOP
    v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
    v_qty := (v_item->>'quantidade')::integer;
    IF v_prod_id IS NOT NULL AND v_qty > 0 THEN
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
      VALUES (v_prod_id, v_qty, 'saida', p_uf_nova, p_uf_nova, p_pedido_id, 'Pedido #' || p_pedido_id::text);
    END IF;
  END LOOP;
  
  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;
END;
$BODY$;

-- 3. Como não temos histórico de mudanças de UF, o usuário precisa informar manualmente
-- Se souber o ID do pedido e as UFs, pode executar:
-- SELECT registrar_mudanca_uf('UUID_DO_PEDIDO', 'UF_ANTIGA', 'UF_NOVA');

-- 4. Verificar movimentações existentes de "Mudança UF"
SELECT * FROM estoque_movimentacoes 
WHERE observacao LIKE 'Mudança UF%'
ORDER BY created_at DESC;

COMMIT;
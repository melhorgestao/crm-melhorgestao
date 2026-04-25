-- Drop data_nascimento from contatos
ALTER TABLE public.contatos DROP COLUMN IF EXISTS data_nascimento;

-- Recreate process_venda to create 1 single pedido with JSON produtos array
CREATE OR REPLACE FUNCTION public.process_venda(p_socio text, p_canal text, p_valor numeric, p_contato_id uuid, p_produtos jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
BEGIN
  -- Build the JSON array of products for the single pedido
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    produtos_array := produtos_array || jsonb_build_array(jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    ));

    -- Deduct stock per product
    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;

    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse)
    VALUES (prod_id, prod_qty, 'saida', 'Venda');
  END LOOP;

  -- 1 lancamento
  INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade)
  VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty);

  -- 1 single pedido with all products as JSON
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, produto_id, preco_unitario)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', NULL, NULL);

  -- 1 financeiro
  INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);

  -- Update kanban
  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$function$;
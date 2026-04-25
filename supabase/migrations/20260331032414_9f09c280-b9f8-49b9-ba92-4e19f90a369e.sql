-- 1. Drop como_conheceu column
ALTER TABLE public.contatos DROP COLUMN IF EXISTS como_conheceu;

-- 2. Create metas_mensais table for dashboard monthly goals
CREATE TABLE IF NOT EXISTS public.metas_mensais (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  ano integer NOT NULL,
  mes integer NOT NULL,
  valor numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, ano, mes)
);
ALTER TABLE public.metas_mensais ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own metas" ON public.metas_mensais FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 3. Create atomic VENDA function
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  prod_endereco text;
  prod_count integer;
BEGIN
  prod_count := jsonb_array_length(p_produtos);

  INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade)
  VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id,
    (SELECT COALESCE(SUM((p->>'quantidade')::int), 0) FROM jsonb_array_elements(p_produtos) p));

  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    prod_endereco := prod->>'endereco_entrega';

    INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, endereco_entrega, produto_id, preco_unitario)
    VALUES (p_contato_id, prod_nome, prod_qty, p_valor / prod_count, p_canal, 'aguardando_rastreio', prod_endereco, prod_id, prod_preco);

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;

    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse)
    VALUES (prod_id, prod_qty, 'saida', 'Venda');
  END LOOP;

  INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);

  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$$;
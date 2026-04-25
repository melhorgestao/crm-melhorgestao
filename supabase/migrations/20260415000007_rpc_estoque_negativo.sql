-- Criar funcao RPC para buscar estoque com negativo (chamada do frontend)
CREATE OR REPLACE FUNCTION public.buscar_estoque_completo()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT 
      produto_id,
      produto_nome,
      uf,
      entradas,
      saidas_pedidos,
      saldo
    FROM public.get_estoque_completo()
  ) t;
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- Criar funcao para somar estoque negativo nos cards do frontend
CREATE OR REPLACE FUNCTION public.get_estoque_total_por_produto()
RETURNS TABLE(produto_id uuid, produto_nome text, saldo_total integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    produto_id,
    produto_nome,
    SUM(saldo)::integer as saldo_total
  FROM public.get_estoque_completo()
  GROUP BY produto_id, produto_nome
  ORDER BY produto_nome;
END;
$$;
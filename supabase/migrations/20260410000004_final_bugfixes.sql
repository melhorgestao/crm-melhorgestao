-- REFINAMENTO FINAL: REGIONALIZAÇÃO
-- Garante que TODA nova região criada tenha um registro em remetentes_uf
-- (Copia do remetente da UF base ou gera um em branco)

BEGIN;

CREATE OR REPLACE FUNCTION public.criar_regiao_uf(p_uf text, p_tag text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_seq integer;
  v_codigo text;
  v_regiao_id uuid;
  v_is_first boolean;
BEGIN
  -- 1. Descobrir o próximo sequencial
  SELECT COALESCE(MAX(sequencial), 0) + 1 INTO v_seq FROM uf_regioes WHERE uf = p_uf;
  v_codigo := p_uf || v_seq::text;
  v_is_first := (v_seq = 1);

  -- 2. Criar a região
  INSERT INTO uf_regioes (uf, tag, codigo, sequencial)
  VALUES (p_uf, p_tag, v_codigo, v_seq)
  RETURNING id INTO v_regiao_id;

  -- 3. Se for a primeira região, MIGRAR dados da UF base para UF1
  IF v_is_first THEN
    -- estoque_movimentacoes
    UPDATE estoque_movimentacoes SET uf_origem = v_codigo WHERE uf_origem = p_uf;
    UPDATE estoque_movimentacoes SET posse = v_codigo WHERE posse = p_uf;
    
    -- lotes
    UPDATE lotes SET uf = v_codigo WHERE uf = p_uf;
    
    -- pedidos
    UPDATE pedidos SET uf_postagem = v_codigo WHERE uf_postagem = p_uf;
    UPDATE pedidos SET uf_cliente = v_codigo WHERE uf_cliente = p_uf;

    -- remetentes_uf (IMPORTANTE PARA LOGÍSTICA)
    -- Migra o remetente atual da UF base para a nova região operacional
    UPDATE remetentes_uf SET uf = v_codigo WHERE uf = p_uf;

    -- snapshot
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'estoque_snapshot') THEN
       UPDATE estoque_snapshot SET estado = v_codigo WHERE estado = p_uf;
    END IF;
  ELSE
    -- 4. Para regiões subsequentes (RS2, RS3...), criar um remetente em branco ou cópia
    -- Isso evita erro de "Remetente não configurado" na Logística
    IF NOT EXISTS (SELECT 1 FROM remetentes_uf WHERE uf = v_codigo) THEN
        INSERT INTO remetentes_uf (uf, nome_remetente, cep_origem)
        SELECT v_codigo, nome_remetente || ' (' || p_tag || ')', cep_origem
        FROM remetentes_uf
        WHERE uf LIKE p_uf || '%'
        ORDER BY uf ASC
        LIMIT 1;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'id', v_regiao_id,
    'codigo', v_codigo,
    'migrado', v_is_first
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

COMMIT;

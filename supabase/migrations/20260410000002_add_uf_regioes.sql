-- REGIONALIZAÇÃO DE UFS - SCHEMA E MIGRAÇÃO
-- 1. Cria tabela uf_regioes
-- 2. Sistema de geração de código automático (RS1, RS2)
-- 3. Lógica de migração automática UF -> UF1 no primeiro cadastro

BEGIN;

-- 1. TABELA DE REGIÕES
CREATE TABLE IF NOT EXISTS public.uf_regioes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uf text NOT NULL REFERENCES public.estoque_ufs(uf) ON DELETE CASCADE,
  tag text NOT NULL, -- Nome amigável (ex: Alvorada)
  codigo text UNIQUE NOT NULL, -- O código operacional (ex: RS1)
  sequencial integer NOT NULL, -- 1, 2, 3...
  criado_em timestamptz DEFAULT now(),
  UNIQUE(uf, tag)
);

-- Habilitar RLS
ALTER TABLE public.uf_regioes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read uf_regioes" ON public.uf_regioes
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can insert uf_regioes" ON public.uf_regioes
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated can delete uf_regioes" ON public.uf_regioes
  FOR DELETE TO authenticated USING (true);

-- 2. FUNÇÃO: Geração de Código e Migração Automática
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

    -- snapshot
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'estoque_snapshot') THEN
       UPDATE estoque_snapshot SET estado = v_codigo WHERE estado = p_uf;
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

-- ============================================================================
-- Hotfix: knowledge_chunks pode ter sido criada parcial em tentativa anterior.
-- DROP CASCADE + recriação limpa (user confirmou que tabela está vazia/inutilizada).
-- ============================================================================

DROP TABLE IF EXISTS public.knowledge_chunks CASCADE;

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE public.knowledge_chunks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo      text NOT NULL,
  categoria   text NOT NULL CHECK (categoria IN (
                'tabela','sobre_produtos','bonus','argumentos_venda','faq'
              )),
  conteudo    text NOT NULL,
  embedding   vector(1536),
  ativo       boolean NOT NULL DEFAULT true,
  observacao  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_knowledge_chunks_embedding
  ON public.knowledge_chunks USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

CREATE INDEX idx_knowledge_chunks_categoria
  ON public.knowledge_chunks (categoria) WHERE ativo = true;

ALTER TABLE public.knowledge_chunks ENABLE ROW LEVEL SECURITY;
CREATE POLICY knowledge_admin_all ON public.knowledge_chunks
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

NOTIFY pgrst, 'reload schema';

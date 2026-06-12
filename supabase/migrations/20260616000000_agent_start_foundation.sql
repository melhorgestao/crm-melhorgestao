-- ============================================================================
-- AGENT_START Foundation
-- ============================================================================
-- Tabelas: knowledge_chunks (RAG)
-- RPCs:    buscar_conhecimento, consultar_pedidos_contato,
--          consultar_rastreio_contato, marcar_contato_suporte,
--          obter_config_frete
-- Configs: openai_api_key, openrouter_api_key
-- Extensão: pgvector
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- ----------------------------------------------------------------------------
-- 1) Tabela knowledge_chunks (RAG)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.knowledge_chunks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo      text NOT NULL,
  categoria   text NOT NULL CHECK (categoria IN (
                'tabela',           -- nome oficial + preço por produto
                'sobre_produtos',   -- descrição ampla, características, uso
                'bonus',            -- regras de bônus (ex: 4 produtos = +1 grátis)
                'argumentos_venda', -- benefícios, custo-benefício, diferencial
                'faq'               -- interações, golpe, efeitos colaterais, etc
              )),
  conteudo    text NOT NULL,
  embedding   vector(1536),
  ativo       boolean NOT NULL DEFAULT true,
  observacao  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_embedding
  ON public.knowledge_chunks USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100)
  WHERE ativo = true AND embedding IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_categoria
  ON public.knowledge_chunks (categoria) WHERE ativo = true;

ALTER TABLE public.knowledge_chunks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS knowledge_admin_all ON public.knowledge_chunks;
CREATE POLICY knowledge_admin_all ON public.knowledge_chunks
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------------------
-- 2) Slots de configuração (API keys)
-- ----------------------------------------------------------------------------
INSERT INTO public.configuracoes (chave, valor) VALUES
  ('openai_api_key',      ''),
  ('openrouter_api_key',  ''),
  ('agent_modelo_llm',    'meta-llama/llama-3.3-70b-instruct:free'),
  ('agent_peso_unitario_g', '300')
ON CONFLICT (chave) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 3) RPC buscar_conhecimento — top-k por similaridade cosine
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.buscar_conhecimento(
  p_embedding vector(1536),
  p_categoria text DEFAULT NULL,
  p_limit     integer DEFAULT 5
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'titulo',       t.titulo,
      'categoria',    t.categoria,
      'conteudo',     t.conteudo,
      'similaridade', round((1 - (t.embedding <=> p_embedding))::numeric, 3)
    ))
    FROM (
      SELECT titulo, categoria, conteudo, embedding
        FROM public.knowledge_chunks
       WHERE ativo = true
         AND embedding IS NOT NULL
         AND (p_categoria IS NULL OR categoria = p_categoria)
       ORDER BY embedding <=> p_embedding
       LIMIT p_limit
    ) t
  ), '[]'::jsonb);
END $$;

GRANT EXECUTE ON FUNCTION public.buscar_conhecimento(vector, text, integer)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4) RPC consultar_pedidos_contato
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consultar_pedidos_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'order_number',    p.order_number,
      'data',            p.data,
      'status_pedido',   p.status_pedido,
      'status_pagamento', p.status_pagamento,
      'valor',           p.valor,
      'produto',         p.produto,
      'quantidade',      p.quantidade,
      'canal',           p.canal,
      'link_rastreio',   p.link_rastreio,
      'codigo_rastreio', p.codigo_rastreio
    ) ORDER BY p.data DESC)
    FROM (
      SELECT *
        FROM public.pedidos
       WHERE contato_id = p_contato_id
       ORDER BY data DESC
       LIMIT 5
    ) p
  ), '[]'::jsonb);
END $$;

GRANT EXECUTE ON FUNCTION public.consultar_pedidos_contato(uuid)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5) RPC consultar_rastreio_contato
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consultar_rastreio_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'order_number',    p.order_number,
      'data',            p.data,
      'status_pedido',   p.status_pedido,
      'link_rastreio',   p.link_rastreio,
      'codigo_rastreio', p.codigo_rastreio,
      'rastreio_enviado_em', p.rastreio_enviado_em
    ) ORDER BY p.data DESC)
    FROM (
      SELECT *
        FROM public.pedidos
       WHERE contato_id = p_contato_id
         AND link_rastreio IS NOT NULL
       ORDER BY data DESC
       LIMIT 5
    ) p
  ), '[]'::jsonb);
END $$;

GRANT EXECUTE ON FUNCTION public.consultar_rastreio_contato(uuid)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6) RPC marcar_contato_suporte — escala pro Kanban Suporte
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marcar_contato_suporte(
  p_contato_id uuid,
  p_motivo     text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.contatos
     SET ultima_interacao = 'suporte',
         data_suporte     = NOW(),
         suporte_motivo   = p_motivo,
         updated_at       = NOW()
   WHERE id = p_contato_id;

  -- Best-effort: registra no eventos_contato se a tabela existir
  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, metadata)
    VALUES (p_contato_id, 'escalado_suporte_agent', jsonb_build_object('motivo', p_motivo));
  EXCEPTION WHEN undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'escalado_em', NOW());
END $$;

GRANT EXECUTE ON FUNCTION public.marcar_contato_suporte(uuid, text)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 7) RPC obter_config_frete — usada pela edge consultar-frete-agent
--    Retorna CEP de origem + peso unitário default em gramas
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.obter_config_frete(p_to_cep text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cep_origem text;
  v_peso_g     int;
BEGIN
  -- Pega primeiro remetente cadastrado (MVP — pode evoluir pra picar por UF)
  BEGIN
    SELECT cep_origem INTO v_cep_origem
      FROM public.remetentes_uf
     WHERE cep_origem IS NOT NULL
     ORDER BY created_at ASC
     LIMIT 1;
  EXCEPTION WHEN undefined_table THEN NULL; END;

  SELECT NULLIF(valor,'')::int INTO v_peso_g
    FROM public.configuracoes
   WHERE chave = 'agent_peso_unitario_g';

  RETURN jsonb_build_object(
    'from_cep',         COALESCE(v_cep_origem, '05010000'),
    'peso_unitario_g',  COALESCE(v_peso_g, 300)
  );
END $$;

GRANT EXECUTE ON FUNCTION public.obter_config_frete(text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

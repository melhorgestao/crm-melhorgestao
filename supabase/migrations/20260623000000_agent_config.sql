-- ============================================================================
-- agent_config: configurações dos agentes editáveis pela UI.
-- Sem redeploy: agent lê do banco em cada execução.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.agent_config (
  agent       TEXT NOT NULL CHECK (agent IN ('start', 'closing')),
  chave       TEXT NOT NULL,
  valor       JSONB NOT NULL,
  descricao   TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (agent, chave)
);

ALTER TABLE public.agent_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS agent_config_admin_all ON public.agent_config;
CREATE POLICY agent_config_admin_all ON public.agent_config
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS agent_config_service_select ON public.agent_config;
CREATE POLICY agent_config_service_select ON public.agent_config
  FOR SELECT TO service_role USING (true);

-- updated_at automático
CREATE OR REPLACE FUNCTION public.agent_config_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_agent_config_updated_at ON public.agent_config;
CREATE TRIGGER trg_agent_config_updated_at
  BEFORE UPDATE ON public.agent_config
  FOR EACH ROW EXECUTE FUNCTION public.agent_config_set_updated_at();

-- ----------------------------------------------------------------------------
-- Seeds com defaults (idempotente — INSERT ... ON CONFLICT DO NOTHING)
-- ----------------------------------------------------------------------------
INSERT INTO public.agent_config (agent, chave, valor, descricao) VALUES
  ('start', 'foto_apresentacao_url', '"https://epreaawpvxrpqqthcczu.supabase.co/storage/v1/object/public/Start/TabelaOficial.png"'::jsonb,
   'URL da foto enviada como caption do cardápio na 1ª interação'),

  ('start', 'reapresentar_meses', 'null'::jsonb,
   'Reenvia cardápio se cliente passou X meses sem msg. NULL = nunca reapresenta'),

  ('start', 'texto_apresentacao', $$"Santa Flor possui óleos🥥 Base de TCM, um suplemento nutricional extraído da polpa do coco, extremamente nutritivo e de rápida absorção, o mais indicado pelos médicos.\n\nTodos os produtos possuem:\n\n🌱 Flores de cannabis de genética CBD e THC plantada em estufa livre de pesticidas.\n\nE são produzidos💯 sem solvente (100% natural e sabor real da cannabis)"$$::jsonb,
   'Bloco 1 da apresentação inicial (texto)'),

  ('start', 'cardapio_header', '"📋 *Nosso cardápio:*"'::jsonb,
   'Linha acima da lista de produtos'),

  -- Regras de bônus NÃO ficam aqui — vivem nos chunks RAG (FAQ/bonus).
  -- Quando cliente perguntar, agent chama buscar_conhecimento.

  -- SAUDAÇÕES por canal (usadas só quando 1ª msg é genérica: "oi", "boa noite", etc).
  -- Quando lead já chega com pergunta direta, NÃO usa saudação — agent responde direto.
  ('start', 'saudacao_base',
   '"Como posso te ajudar hoje, {nome}? Tá buscando indicação pra alguma situação específica?"'::jsonb,
   'Saudação canal BASE (lead orgânico). Placeholders: {nome}'),

  ('start', 'saudacao_ads',
   '"Que bom te ver por aqui, {nome}! Como posso te ajudar? Buscando indicação pra alguma situação específica?"'::jsonb,
   'Saudação canal ADS (lead de tráfego pago). Placeholders: {nome}'),

  ('start', 'saudacao_rep',
   '"Salve, {nome}! 🤝 No que posso te ajudar hoje?"'::jsonb,
   'Saudação canal REP (representante). Placeholders: {nome}'),

  ('start', 'saudacao_cliente',
   '"Oi, {nome}! Tudo bem por aí? Em que posso te ajudar hoje?"'::jsonb,
   'Saudação CLIENTE (já comprou — inclui cliente_pendente). Placeholders: {nome}, {saldo} (se cliente_pendente)'),

  ('start', 'llm_temperature', '0.4'::jsonb,
   'Temperature do LLM (0=determinístico, 1=criativo). Default 0.4')
ON CONFLICT (agent, chave) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Helper RPC: pega todos os configs de um agent num jsonb único.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_agent_config(p_agent TEXT)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_object_agg(chave, valor), '{}'::jsonb)
    FROM public.agent_config WHERE agent = p_agent;
$$;

GRANT EXECUTE ON FUNCTION public.get_agent_config(TEXT)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

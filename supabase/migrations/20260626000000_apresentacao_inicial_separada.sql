-- ============================================================================
-- "1ª Apresentação" separada do Agent Start. Sequência de 5 mensagens rígidas:
--   [1] Texto institucional (editável, SEM LLM)
--   [2] Cardápio: header + lista auto produtos + footer (editável, SEM LLM)
--   [3] Bônus (editável, SEM LLM)
--   [4] Foto (mídia separada — melhor leitura no WhatsApp)
--   [5] Saudação por canal OU resposta direta (Agent Start)
-- ============================================================================

-- 1) PRIMEIRO permite agent='apresentacao' no CHECK constraint
ALTER TABLE public.agent_config DROP CONSTRAINT IF EXISTS agent_config_agent_check;
ALTER TABLE public.agent_config
  ADD CONSTRAINT agent_config_agent_check
  CHECK (agent IN ('start', 'closing', 'apresentacao'));

-- 2) DEPOIS insere os seeds
INSERT INTO public.agent_config (agent, chave, valor, descricao) VALUES
  ('apresentacao', 'bloco1_texto',
   $$"Santa Flor possui óleos🥥 Base de TCM, um suplemento nutricional extraído da polpa do coco, extremamente nutritivo e de rápida absorção, o mais indicado pelos médicos.\n\nTodos os produtos possuem:\n\n🌱 Flores de cannabis de genética CBD e THC plantada em estufa livre de pesticidas.\n\nE são produzidos💯 sem solvente (100% natural e sabor real da cannabis)"$$::jsonb,
   'Bloco 1 — texto institucional. Envio direto, SEM LLM.'),

  ('apresentacao', 'bloco2_header',
   '"📋 *Nosso cardápio:*"'::jsonb,
   'Bloco 2 — header acima da lista de produtos.'),

  ('apresentacao', 'bloco2_footer',
   '""'::jsonb,
   'Bloco 2 — footer opcional abaixo da lista. Vazio = não envia.'),

  ('apresentacao', 'bloco3_bonus',
   $$"🎁 *Bônus por quantidade:*\n\n🚚 2 produtos → frete SEDEX grátis\n🎁 4 produtos → ganha 1 brinde do catálogo\n🎁 8 produtos → ganha 2 brindes do catálogo"$$::jsonb,
   'Bloco 3 — regras de bônus.'),

  ('apresentacao', 'bloco4_foto_url',
   '"https://epreaawpvxrpqqthcczu.supabase.co/storage/v1/object/public/Start/TabelaOficial.png"'::jsonb,
   'Bloco 4 — foto enviada como mídia separada (bucket Start).'),

  ('apresentacao', 'reapresentar_meses', 'null'::jsonb,
   'Reenvia apresentação após X meses sem interação. NULL = nunca.')
ON CONFLICT (agent, chave) DO NOTHING;

-- 3) Migra reapresentar_meses de 'start' → 'apresentacao' (se existir)
DO $$
DECLARE v_old jsonb;
BEGIN
  SELECT valor INTO v_old FROM public.agent_config
   WHERE agent = 'start' AND chave = 'reapresentar_meses';
  IF v_old IS NOT NULL AND v_old != 'null'::jsonb THEN
    UPDATE public.agent_config SET valor = v_old
     WHERE agent = 'apresentacao' AND chave = 'reapresentar_meses';
  END IF;
  DELETE FROM public.agent_config WHERE agent = 'start' AND chave = 'reapresentar_meses';
END $$;

NOTIFY pgrst, 'reload schema';

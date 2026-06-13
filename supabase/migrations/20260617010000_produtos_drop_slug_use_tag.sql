-- ============================================================================
-- Reverte produtos.slug (criado por engano) — usar a coluna `tag` existente.
-- Backfill emoji + ordem + atualiza tags pros valores que o AGENT_CLOSING usa.
-- ============================================================================

-- 1) DROP slug se foi criado pela migration anterior
ALTER TABLE public.produtos DROP COLUMN IF EXISTS slug;

-- (UNIQUE index produtos_slug_uk some junto com a coluna)

-- 2) Garante emoji + ordem
ALTER TABLE public.produtos
  ADD COLUMN IF NOT EXISTS emoji text,
  ADD COLUMN IF NOT EXISTS ordem integer NOT NULL DEFAULT 0;

-- 3) Backfill tag + emoji + ordem pros 6 produtos canônicos
--    Critério MATCH por nome (LIKE flexível). Ajuste manual se algum nome divergir.
--    Tags finais usadas pelo AGENT_CLOSING: verde, amarelo, vermelho, gummy, pomada, lub
UPDATE public.produtos SET tag='verde',    emoji='🟩', ordem=1
 WHERE nome_oficial ILIKE '%4.000%' OR nome_oficial ILIKE '%4000%'
    OR nome_oficial ILIKE '%CBD%' AND nome_oficial NOT ILIKE '%1:1%' AND nome_oficial NOT ILIKE '%1:2%'
    OR tag IN ('cbd','full4k');

UPDATE public.produtos SET tag='amarelo',  emoji='🟨', ordem=2
 WHERE nome_oficial ILIKE '%1:1%' OR nome_oficial ILIKE '%6.000%' OR nome_oficial ILIKE '%6000%'
    OR tag = 'full6k';

UPDATE public.produtos SET tag='vermelho', emoji='🟥', ordem=3
 WHERE nome_oficial ILIKE '%1:2%' OR nome_oficial ILIKE '%10.000%' OR nome_oficial ILIKE '%10000%'
    OR tag = 'full10k';

UPDATE public.produtos SET tag='gummy',    emoji='🍬', ordem=4
 WHERE nome_oficial ILIKE '%gummy%' OR nome_oficial ILIKE '%bear%' OR tag = 'gummy';

UPDATE public.produtos SET tag='pomada',   emoji='🔰', ordem=5
 WHERE nome_oficial ILIKE '%pomada%' OR nome_oficial ILIKE '%cannaderm%' OR tag = 'pomada';

UPDATE public.produtos SET tag='lub',      emoji='🧴', ordem=6
 WHERE nome_oficial ILIKE '%lubrificante%' OR tag IN ('lub','lubrificante');

-- 4) Garante unicidade da tag (necessário pra busca rápida do agent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'produtos_tag_uk_ativo'
  ) THEN
    CREATE UNIQUE INDEX produtos_tag_uk_ativo
      ON public.produtos(tag) WHERE ativo = true;
  END IF;
END $$;

COMMENT ON COLUMN public.produtos.tag   IS 'Identificador interno usado p/ matching da fala do cliente (verde, amarelo, pomada...). NÃO exibir ao cliente.';
COMMENT ON COLUMN public.produtos.emoji IS 'Emoji do produto exibido nos resumos (🟩, 🍬, 🔰...).';
COMMENT ON COLUMN public.produtos.ordem IS 'Ordem fixa de exibição no catálogo (0 = primeiro).';

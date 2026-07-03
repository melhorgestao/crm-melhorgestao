-- ============================================================================
-- Produtos: novas colunas arte_url e foto_url (imagens do produto).
--
-- - arte_url  = arte editada/marketing (mais vendável)
-- - foto_url  = foto real / fundo branco mockup
-- - emoji já existia; só reexpõe no form
--
-- RPCs create_produto / update_produto passam a aceitar os novos campos.
-- Backfill oportunista: se houver arquivo cujo nome (case-insensitive) BATE
-- com o tag/slug do produto no bucket Start, popula arte_url. Nome exato:
-- objetos em storage.objects (bucket_id='Start') com name ILIKE '%<tag>%.png'
-- ou similar. Se nada bater, mantém NULL — usuário sobe manual pelo form.
-- ============================================================================

ALTER TABLE public.produtos
  ADD COLUMN IF NOT EXISTS arte_url text,
  ADD COLUMN IF NOT EXISTS foto_url text;

COMMENT ON COLUMN public.produtos.arte_url IS 'URL pública da ARTE do produto (imagem editada de marketing, mais vendável).';
COMMENT ON COLUMN public.produtos.foto_url IS 'URL pública da FOTO do produto (foto real / mockup fundo branco).';

-- ----------------------------------------------------------------------------
-- update_produto v2 — aceita arte_url e foto_url
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.update_produto(uuid,text,text,text,text,integer,uuid,text,integer,integer,numeric);

CREATE OR REPLACE FUNCTION public.update_produto(
  p_id             uuid,
  p_nome_oficial   text,
  p_tag            text,
  p_cor_card       text,
  p_cor_texto      text,
  p_limite_estoque integer,
  p_grupo_id       uuid,
  p_box_size       text,
  p_box_qty_max    integer,
  p_peso           integer DEFAULT 300,
  p_preco          numeric DEFAULT NULL,
  p_emoji          text    DEFAULT NULL,
  p_arte_url       text    DEFAULT NULL,
  p_foto_url       text    DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.produtos SET
    nome_oficial   = p_nome_oficial,
    tag            = p_tag,
    cor_card       = p_cor_card,
    cor_texto      = p_cor_texto,
    limite_estoque = p_limite_estoque,
    grupo_id       = p_grupo_id,
    box_size       = p_box_size,
    box_qty_max    = p_box_qty_max,
    peso           = p_peso,
    preco          = COALESCE(p_preco, preco),
    emoji          = COALESCE(p_emoji, emoji),
    arte_url       = COALESCE(p_arte_url, arte_url),
    foto_url       = COALESCE(p_foto_url, foto_url)
  WHERE id = p_id;
END $$;

GRANT EXECUTE ON FUNCTION public.update_produto(uuid,text,text,text,text,integer,uuid,text,integer,integer,numeric,text,text,text)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- create_produto v2
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_produto(text,text,text,text,integer,uuid,text,integer,integer,numeric);

CREATE OR REPLACE FUNCTION public.create_produto(
  p_nome_oficial   text,
  p_tag            text,
  p_cor_card       text,
  p_cor_texto      text,
  p_limite_estoque integer,
  p_grupo_id       uuid,
  p_box_size       text,
  p_box_qty_max    integer,
  p_peso           integer DEFAULT 300,
  p_preco          numeric DEFAULT NULL,
  p_emoji          text    DEFAULT NULL,
  p_arte_url       text    DEFAULT NULL,
  p_foto_url       text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.produtos (
    nome_oficial, tag, cor_card, cor_texto,
    limite_estoque, grupo_id, box_size, box_qty_max, peso, preco,
    emoji, arte_url, foto_url
  ) VALUES (
    p_nome_oficial, p_tag, p_cor_card, p_cor_texto,
    p_limite_estoque, p_grupo_id, p_box_size, p_box_qty_max, p_peso, p_preco,
    p_emoji, p_arte_url, p_foto_url
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.create_produto(text,text,text,text,integer,uuid,text,integer,integer,numeric,text,text,text)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- BACKFILL: tenta popular arte_url pros produtos existentes.
-- Estratégia: procura objeto em storage.objects (bucket_id='Start') cujo
-- nome contenha o tag OU o slug do nome_oficial do produto. Se achar, monta
-- a URL pública. É "best effort" — usuário edita manual pelo modal depois
-- pra corrigir/subir a Foto (fundo branco).
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_prod       RECORD;
  v_obj_name   text;
  v_url_base   text;
  v_normalized text;
BEGIN
  -- URL base do storage público — deriva da SUPABASE_URL via config, fallback pro projeto atual
  BEGIN
    SELECT current_setting('app.supabase_url', true) INTO v_url_base;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  IF v_url_base IS NULL OR v_url_base = '' THEN
    v_url_base := 'https://epreaawpvxrpqqthcczu.supabase.co';
  END IF;

  FOR v_prod IN
    SELECT id, tag, nome_oficial FROM public.produtos WHERE arte_url IS NULL
  LOOP
    v_normalized := lower(regexp_replace(COALESCE(v_prod.tag, ''), '[^a-z0-9]', '', 'gi'));

    SELECT name INTO v_obj_name
      FROM storage.objects
     WHERE bucket_id = 'Start'
       AND (
            lower(regexp_replace(name, '[^a-z0-9]', '', 'gi')) LIKE '%' || v_normalized || '%'
         OR lower(regexp_replace(name, '[^a-z0-9]', '', 'gi')) LIKE '%' ||
              lower(regexp_replace(COALESCE(v_prod.nome_oficial,''), '[^a-z0-9]', '', 'gi')) || '%'
       )
       AND (name ILIKE '%.jpg' OR name ILIKE '%.jpeg' OR name ILIKE '%.png' OR name ILIKE '%.webp')
     ORDER BY length(name) ASC
     LIMIT 1;

    IF v_obj_name IS NOT NULL THEN
      UPDATE public.produtos
         SET arte_url = v_url_base || '/storage/v1/object/public/Start/' || v_obj_name
       WHERE id = v_prod.id;
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

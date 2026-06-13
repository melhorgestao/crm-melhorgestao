-- ============================================================================
-- create_produto / update_produto agora aceitam p_preco (numeric)
-- Coluna preco já existia em produtos, mas RPCs ignoravam o campo.
-- ============================================================================

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
  p_preco          numeric DEFAULT NULL
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
    preco          = COALESCE(p_preco, preco)
  WHERE id = p_id;
END $$;

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
  p_preco          numeric DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.produtos (
    nome_oficial, tag, cor_card, cor_texto,
    limite_estoque, grupo_id, box_size, box_qty_max, peso, preco
  ) VALUES (
    p_nome_oficial, p_tag, p_cor_card, p_cor_texto,
    p_limite_estoque, p_grupo_id, p_box_size, p_box_qty_max, p_peso, p_preco
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.update_produto(uuid,text,text,text,text,integer,uuid,text,integer,integer,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_produto(text,text,text,text,integer,uuid,text,integer,integer,numeric)      TO authenticated;

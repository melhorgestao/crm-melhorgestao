-- SQL para adicionar peso aos produtos e atualizar funções RPC
-- Execute no Supabase SQL Editor

-- 1. Adiciona coluna peso aos produtos
ALTER TABLE public.produtos 
ADD COLUMN IF NOT EXISTS peso integer DEFAULT 300;

-- 2. Atualiza produtos com peso padrão
UPDATE public.produtos SET peso = 300 WHERE peso IS NULL OR peso = 0;

-- 3. Recria função update_produto com peso
CREATE OR REPLACE FUNCTION update_produto(
  p_id uuid,
  p_nome_oficial text,
  p_tag text,
  p_cor_card text,
  p_cor_texto text,
  p_limite_estoque integer,
  p_grupo_id uuid,
  p_box_size text,
  p_box_qty_max integer,
  p_peso integer DEFAULT 300
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.produtos SET
    nome_oficial = p_nome_oficial,
    tag = p_tag,
    cor_card = p_cor_card,
    cor_texto = p_cor_texto,
    limite_estoque = p_limite_estoque,
    grupo_id = p_grupo_id,
    box_size = p_box_size,
    box_qty_max = p_box_qty_max,
    peso = p_peso
  WHERE id = p_id;
END;
$$;

-- 4. Recria função create_produto com peso
CREATE OR REPLACE FUNCTION create_produto(
  p_nome_oficial text,
  p_tag text,
  p_cor_card text,
  p_cor_texto text,
  p_limite_estoque integer,
  p_grupo_id uuid,
  p_box_size text,
  p_box_qty_max integer,
  p_peso integer DEFAULT 300
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.produtos (
    nome_oficial, tag, cor_card, cor_texto, 
    limite_estoque, grupo_id, box_size, box_qty_max, peso
  ) VALUES (
    p_nome_oficial, p_tag, p_cor_card, p_cor_texto,
    p_limite_estoque, p_grupo_id, p_box_size, p_box_qty_max, p_peso
  )
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;
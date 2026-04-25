-- Criar funções RPC para gerenciamento de produtos
BEGIN;

-- Função para criar produto
CREATE OR REPLACE FUNCTION create_produto(
  p_nome_oficial text,
  p_tag text,
  p_cor_card text DEFAULT '#ffffff',
  p_cor_texto text DEFAULT '#000000',
  p_limite_estoque integer DEFAULT 0,
  p_grupo_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO produtos (
    nome_oficial,
    tag,
    cor_card,
    cor_texto,
    limite_estoque,
    grupo_id,
    ativo
  ) VALUES (
    p_nome_oficial,
    p_tag,
    p_cor_card,
    p_cor_texto,
    p_limite_estoque,
    p_grupo_id,
    true
  )
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;

-- Função para atualizar produto
CREATE OR REPLACE FUNCTION update_produto(
  p_id uuid,
  p_nome_oficial text,
  p_tag text,
  p_cor_card text,
  p_cor_texto text,
  p_limite_estoque integer,
  p_grupo_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE produtos SET
    nome_oficial = p_nome_oficial,
    tag = p_tag,
    cor_card = p_cor_card,
    cor_texto = p_cor_texto,
    limite_estoque = p_limite_estoque,
    grupo_id = p_grupo_id
  WHERE id = p_id;
END;
$$;

-- Função para excluir produto
CREATE OR REPLACE FUNCTION delete_produto(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM produtos WHERE id = p_id;
END;
$$;

-- Função para criar grupo
CREATE OR REPLACE FUNCTION create_produto_grupo(p_nome text, p_cor text DEFAULT '#ffffff')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO produtos_grupos (nome, cor_grupo) VALUES (p_nome, p_cor)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Função para atualizar grupo
CREATE OR REPLACE FUNCTION update_produto_grupo(p_id uuid, p_nome text, p_cor text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE produtos_grupos SET nome = p_nome, cor_grupo = p_cor WHERE id = p_id;
END;
$$;

-- Função para excluir grupo
CREATE OR REPLACE FUNCTION delete_produto_grupo(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE produtos SET grupo_id = NULL WHERE grupo_id = p_id;
  DELETE FROM produtos_grupos WHERE id = p_id;
END;
$$;

-- Função para atualizar status do produto (ativar/inativar)
CREATE OR REPLACE FUNCTION update_produto_status(p_id uuid, p_ativo boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE produtos SET ativo = p_ativo WHERE id = p_id;
END;
$$;

COMMIT;
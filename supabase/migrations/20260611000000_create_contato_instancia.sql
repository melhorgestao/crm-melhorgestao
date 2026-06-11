-- ============================================================================
-- create_contato agora aceita p_instancia_id para vincular o contato à instância
-- (chip Evolution) responsável pelo atendimento.
-- ============================================================================

-- Drop assinatura anterior (12 params) para permitir nova com 13
DROP FUNCTION IF EXISTS public.create_contato(text, text, text, text, text, text, text, text, text, text, text, uuid);

CREATE OR REPLACE FUNCTION public.create_contato(
  p_nome           text,
  p_canal_origem   text,
  p_telefone       text DEFAULT NULL,
  p_cpf            text DEFAULT NULL,
  p_endereco       text DEFAULT NULL,
  p_complemento    text DEFAULT NULL,
  p_bairro         text DEFAULT NULL,
  p_cidade_uf      text DEFAULT NULL,
  p_cep            text DEFAULT NULL,
  p_cidade         text DEFAULT NULL,
  p_uf             text DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL,
  p_instancia_id   uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO contatos (
    nome, canal_origem, canal_atual, telefone, cpf, endereco, complemento,
    bairro, cidade_uf, cep, cidade, uf, representante_id, instancia_id
  ) VALUES (
    p_nome, p_canal_origem, p_canal_origem, p_telefone, p_cpf, p_endereco, p_complemento,
    p_bairro, p_cidade_uf, p_cep, p_cidade, p_uf, p_representante_id, p_instancia_id
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_contato(text, text, text, text, text, text, text, text, text, text, text, uuid, uuid)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

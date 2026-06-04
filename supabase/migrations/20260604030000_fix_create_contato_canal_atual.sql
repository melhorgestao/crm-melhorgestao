-- ============================================================================
-- Fix: RPC create_contato não setava canal_atual no INSERT.
-- Resultado: contatos criados via formulário "Novo Contato" ficavam com
-- canal_atual = NULL, sumindo do RMKT BASE (que filtra canal_atual='BASE').
--
-- Solução:
--   1. Backfill: NULL → canal_origem
--   2. Recria RPC garantindo canal_atual = p_canal_origem
-- ============================================================================

-- 1) Backfill
UPDATE public.contatos
SET canal_atual = canal_origem, updated_at = NOW()
WHERE canal_atual IS NULL
  AND canal_origem IS NOT NULL;

-- 2) Corrige a RPC pra sempre setar canal_atual
CREATE OR REPLACE FUNCTION public.create_contato(
  p_nome text,
  p_canal_origem text,
  p_telefone text DEFAULT NULL,
  p_cpf text DEFAULT NULL,
  p_endereco text DEFAULT NULL,
  p_complemento text DEFAULT NULL,
  p_bairro text DEFAULT NULL,
  p_cidade_uf text DEFAULT NULL,
  p_cep text DEFAULT NULL,
  p_cidade text DEFAULT NULL,
  p_uf text DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL
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
    bairro, cidade_uf, cep, cidade, uf, representante_id
  ) VALUES (
    p_nome, p_canal_origem, p_canal_origem, p_telefone, p_cpf, p_endereco, p_complemento,
    p_bairro, p_cidade_uf, p_cep, p_cidade, p_uf, p_representante_id
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_contato(text, text, text, text, text, text, text, text, text, text, text, uuid)
  TO anon, authenticated, service_role;

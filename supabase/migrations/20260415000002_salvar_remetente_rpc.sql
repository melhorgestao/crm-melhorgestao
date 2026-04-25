-- RPC para salvar remetente via UPSERT
DROP FUNCTION IF EXISTS salvar_remetente(text,text,text,text,text,text,text,text,text,text,text,numeric);

CREATE OR REPLACE FUNCTION salvar_remetente(
  p_uf_in TEXT,
  p_cep_origem TEXT,
  p_cidade TEXT,
  p_bairro TEXT,
  p_endereco TEXT,
  p_numero TEXT,
  p_complemento TEXT,
  p_nome_remetente TEXT,
  p_contato_remetente TEXT,
  p_cpf TEXT,
  p_descricao_produto TEXT,
  p_valor_unitario NUMERIC
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO remetentes_uf (
    uf, cep_origem, cidade, bairro, endereco, numero, complemento,
    nome_remetente, contato_remetente, cpf, descricao_produto, valor_unitario, updated_at
  )
  VALUES (
    p_uf_in, p_cep_origem, p_cidade, p_bairro, p_endereco, p_numero, p_complemento,
    p_nome_remetente, p_contato_remetente, p_cpf, p_descricao_produto, p_valor_unitario, now()
  )
  ON CONFLICT (uf) DO UPDATE SET
    cep_origem = EXCLUDED.cep_origem,
    cidade = EXCLUDED.cidade,
    bairro = EXCLUDED.bairro,
    endereco = EXCLUDED.endereco,
    numero = EXCLUDED.numero,
    complemento = EXCLUDED.complemento,
    nome_remetente = EXCLUDED.nome_remetente,
    contato_remetente = EXCLUDED.contato_remetente,
    cpf = EXCLUDED.cpf,
    descricao_produto = EXCLUDED.descricao_produto,
    valor_unitario = EXCLUDED.valor_unitario,
    updated_at = now();
END;
$$;
-- ============================================================================
-- create_contato: flag p_ja_comprou pra cadastrar CLIENTE direto (lista antiga).
--
-- Uso: importar clientes antigos que já compraram, atribuindo instância, SEM
-- histórico de pedido. Quando p_ja_comprou = true:
--   - ja_comprou       = true   → conta em instancia_metricas (Clientes) e no
--                                 filtro "Clientes" da aba Contatos.
--   - ultima_interacao = 'cliente' → estado coerente (não vira lead 'start',
--                                 não recebe apresentação/follow-up).
--   - NÃO seta ultima_venda_em → sem venda fake; RMKT não dispara pra esses
--                                 (claim/view exigem ultima_venda_em NOT NULL).
--
-- Mantém toda a lógica anterior (normalização + bloqueio de duplicata BR).
-- Recria a assinatura com o param novo no fim (default false) e dropa a antiga
-- pra evitar overload ambíguo no PostgREST.
-- ============================================================================

DROP FUNCTION IF EXISTS public.create_contato(text, text, text, text, text, text, text, text, text, text, text, uuid, uuid);

CREATE OR REPLACE FUNCTION public.create_contato(
  p_nome             text,
  p_canal_origem     text,
  p_telefone         text DEFAULT NULL,
  p_cpf              text DEFAULT NULL,
  p_endereco         text DEFAULT NULL,
  p_complemento      text DEFAULT NULL,
  p_bairro           text DEFAULT NULL,
  p_cidade_uf        text DEFAULT NULL,
  p_cep              text DEFAULT NULL,
  p_cidade           text DEFAULT NULL,
  p_uf               text DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL,
  p_instancia_id     uuid DEFAULT NULL,
  p_ja_comprou       boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id       uuid;
  v_tel      text;
  v_existing uuid;
  v_cliente  boolean := COALESCE(p_ja_comprou, false);
BEGIN
  v_tel := public.normalize_telefone_br(p_telefone);

  -- Bloqueia duplicata por equivalência BR (exceto C-REP que pode ter linha duplicada)
  IF v_tel IS NOT NULL AND p_canal_origem IS DISTINCT FROM 'C-REP' THEN
    SELECT c.id INTO v_existing
    FROM public.contatos c
    WHERE c.telefone IS NOT NULL
      AND c.canal_origem IS DISTINCT FROM 'C-REP'
      AND public.telefone_br_match(c.telefone, v_tel)
    ORDER BY c.created_at ASC
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
      RAISE EXCEPTION 'telefone já cadastrado (contato %)', v_existing
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;

  INSERT INTO contatos (
    nome, canal_origem, canal_atual, telefone, cpf, endereco, complemento,
    bairro, cidade_uf, cep, cidade, uf, representante_id, instancia_id,
    ja_comprou, ultima_interacao
  ) VALUES (
    p_nome, p_canal_origem, p_canal_origem, v_tel, p_cpf, p_endereco, p_complemento,
    p_bairro, p_cidade_uf, p_cep, p_cidade, p_uf, p_representante_id, p_instancia_id,
    v_cliente,
    CASE WHEN v_cliente THEN 'cliente' ELSE NULL END
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_contato(text, text, text, text, text, text, text, text, text, text, text, uuid, uuid, boolean)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

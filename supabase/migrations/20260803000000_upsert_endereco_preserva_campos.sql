-- ============================================================================
-- upsert_endereco_contato: COALESCE-preserva campos vazios.
--
-- BUG: o UPDATE usava rua = NULLIF(trim(p_rua),''), então uma gravação
-- parcial (ex.: só numero+CPF no ESTADO 3, ou só o CEP vindo do consultar_cep)
-- ZERAVA rua/bairro/cidade/uf que já estavam salvos → endereço nunca ficava
-- completo → fechamento travava sem avançar.
--
-- FIX: cada campo passa a preservar o valor atual quando o parâmetro vem
-- vazio: campo = COALESCE(NULLIF(trim(p_x),''), campo). Assim consultar_cep
-- grava rua/bairro/cidade/uf, e o ESTADO 3 completa só numero+CPF sem apagar
-- nada. rua_numero é recomputado a partir dos valores efetivos.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.upsert_endereco_contato(
  p_contato_id  uuid,
  p_cep         text,
  p_rua         text,
  p_numero      text,
  p_complemento text,
  p_bairro      text,
  p_cidade      text,
  p_uf          text,
  p_cpf         text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.contatos
     SET cep          = COALESCE(NULLIF(trim(p_cep),''), cep),
         rua          = COALESCE(NULLIF(trim(p_rua),''), rua),
         numero       = COALESCE(NULLIF(trim(p_numero),''), numero),
         complemento  = COALESCE(NULLIF(trim(COALESCE(p_complemento,'')),''), complemento),
         bairro       = COALESCE(NULLIF(trim(p_bairro),''), bairro),
         cidade       = COALESCE(NULLIF(trim(p_cidade),''), cidade),
         uf           = COALESCE(upper(NULLIF(trim(p_uf),'')), uf),
         cpf          = COALESCE(NULLIF(regexp_replace(COALESCE(p_cpf,''), '\D', '', 'g'), ''), cpf),
         rua_numero   = trim(concat_ws(', ',
                          COALESCE(NULLIF(trim(p_rua),''), rua),
                          COALESCE(NULLIF(trim(p_numero),''), numero))),
         updated_at   = now()
   WHERE id = p_contato_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  RETURN jsonb_build_object('ok', true, 'contato_id', p_contato_id);
END $$;

GRANT EXECUTE ON FUNCTION public.upsert_endereco_contato(uuid,text,text,text,text,text,text,text,text)
  TO service_role, authenticated, anon;

NOTIFY pgrst, 'reload schema';

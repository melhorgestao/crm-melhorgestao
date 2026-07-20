-- ============================================================================
-- HOTFIX: upsert_endereco_contato sem a coluna morta rua_numero.
--
-- BUG (introduzido em 20260803): a versão COALESCE-preserva foi copiada da
-- definição antiga (20260619) que ainda escrevia rua_numero — coluna DROPADA
-- em prod (renomeada pra 'endereco' e mantida em sync pelo trigger
-- trg_sync_endereco_rua_numero de 20260630). Como plpgsql só valida coluna
-- na EXECUÇÃO, a migration aplicou sem erro e TODA gravação de endereço
-- passou a falhar com 42703 ("column rua_numero does not exist"):
-- consultar_cep não persistia e salvar_endereco travava o fechamento no
-- passo número+CPF ("problemas para salvar" / bot mudo).
--
-- FIX: recria SEM rua_numero. O espelho 'endereco' ("rua, numero") é mantido
-- pelo trigger — não precisa escrever aqui. Mantém o COALESCE-preserva.
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

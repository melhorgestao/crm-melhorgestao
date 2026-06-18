-- ============================================================================
-- Inclui CPF na coleta do agent-closing + snapshot no pedido pra etiqueta.
-- ============================================================================

-- 1) Garante coluna pedidos.cpf (snapshot do CPF na hora do pedido)
ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS cpf TEXT;

COMMENT ON COLUMN public.pedidos.cpf IS
  'CPF do cliente no momento da venda. Snapshot — não muda se contatos.cpf for alterado depois. Obrigatório pra etiqueta de envio.';

-- 2) Trigger: ao inserir pedido, copia CPF atual do contato pro pedido
CREATE OR REPLACE FUNCTION public.trigger_pedido_snapshot_cpf()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.cpf IS NULL AND NEW.contato_id IS NOT NULL THEN
    SELECT cpf INTO NEW.cpf FROM public.contatos WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_pedido_snapshot_cpf ON public.pedidos;
CREATE TRIGGER trg_pedido_snapshot_cpf
  BEFORE INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_pedido_snapshot_cpf();

-- 3) upsert_endereco_contato agora aceita p_cpf opcional no fim
DROP FUNCTION IF EXISTS public.upsert_endereco_contato(uuid,text,text,text,text,text,text,text);

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
     SET cep          = NULLIF(trim(p_cep),''),
         rua          = NULLIF(trim(p_rua),''),
         numero       = NULLIF(trim(p_numero),''),
         complemento  = NULLIF(trim(COALESCE(p_complemento,'')),''),
         bairro       = NULLIF(trim(p_bairro),''),
         cidade       = NULLIF(trim(p_cidade),''),
         uf           = upper(NULLIF(trim(p_uf),'')),
         cpf          = COALESCE(NULLIF(regexp_replace(COALESCE(p_cpf,''), '\D', '', 'g'), ''), cpf),
         rua_numero   = trim(concat_ws(', ', NULLIF(trim(p_rua),''), NULLIF(trim(p_numero),''))),
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

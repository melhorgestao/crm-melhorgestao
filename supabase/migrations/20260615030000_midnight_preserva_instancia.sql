-- ============================================================================
-- Fix: perform_midnight_lead_migration estava sobrescrevendo instancia_id
-- mesmo quando o contato já tinha uma. Task #17 (completed) diz pra preservar.
-- Conserto a ordem do COALESCE: instancia_id existente prevalece sobre default.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_base_instance_id uuid;
  v_migrated_count   integer := 0;
BEGIN
  -- Instância default caso o contato não tenha nenhuma (raro)
  SELECT id INTO v_base_instance_id
    FROM public.instancias
   WHERE ativo = true
     AND status = 'ativo'
     AND nome <> 'Instancia ADMIN'
   ORDER BY alerta_admin DESC, created_at ASC
   LIMIT 1;

  -- Migra canal ADS → BASE preservando instancia_id existente
  WITH updated AS (
    UPDATE public.contatos
       SET canal_origem = 'BASE',
           instancia_id = COALESCE(instancia_id, v_base_instance_id),  -- preserva existente
           updated_at   = NOW()
     WHERE canal_origem = 'ADS'
       AND ultima_venda_em = CURRENT_DATE - 1
     RETURNING id
  )
  SELECT count(*) INTO v_migrated_count FROM updated;

  INSERT INTO public.configuracoes (chave, valor)
       VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

  RETURN json_build_object(
    'success', true,
    'migrated_count', v_migrated_count,
    'fallback_instance_id', v_base_instance_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.perform_midnight_lead_migration()
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Fix midnight-lead-migration: função antiga referenciava colunas dropadas
-- (is_default_base, status_kanban). Reescrevo usando alerta_admin=true
-- como instância destino default e sem status_kanban.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_base_instance_id uuid;
  v_migrated_count   integer := 0;
BEGIN
  -- Instância destino: a marcada como alerta_admin=true (primária).
  -- Fallback: qualquer instância ativa não-admin.
  SELECT id INTO v_base_instance_id
    FROM public.instancias
   WHERE ativo = true
     AND status = 'ativo'
     AND nome <> 'Instancia ADMIN'
   ORDER BY alerta_admin DESC, created_at ASC
   LIMIT 1;

  -- Migra ADS → BASE: contatos que compraram ontem viram base
  WITH updated AS (
    UPDATE public.contatos
       SET canal_origem = 'BASE',
           instancia_id = COALESCE(v_base_instance_id, instancia_id),
           updated_at   = NOW()
     WHERE canal_origem = 'ADS'
       AND ultima_venda_em = CURRENT_DATE - 1
     RETURNING id
  )
  SELECT count(*) INTO v_migrated_count FROM updated;

  -- Marca data da última execução
  INSERT INTO public.configuracoes (chave, valor)
       VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

  RETURN json_build_object(
    'success', true,
    'migrated_count', v_migrated_count,
    'target_instance_id', v_base_instance_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.perform_midnight_lead_migration()
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

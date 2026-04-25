-- 1. Unify 'Comprou Há X dias' to 'Clientes' in the database
UPDATE public.contatos SET status_kanban = 'Clientes' WHERE status_kanban = 'Comprou Há X dias';

-- 2. Update metadata in configuracoes for migration tracking
INSERT INTO public.configuracoes (chave, valor) 
VALUES ('ultimo_auto_lead_migration', '2000-01-01')
ON CONFLICT (chave) DO NOTHING;

-- 3. Update archiving function (30 days for Clientes)
CREATE OR REPLACE FUNCTION public.archive_stale_kanban_cards()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Archive BASE "Clientes" cards where payment/activity > 30 days ago
  UPDATE public.contatos
  SET status_kanban = 'arquivado', updated_at = now()
  WHERE status_kanban = 'Clientes'
    AND updated_at < now() - interval '30 days';

  -- Archive ADS "Sumiu" cards older than 60 days (kept as 60 per original rule)
  UPDATE public.contatos
  SET status_kanban = 'arquivado_sumiu', updated_at = now()
  WHERE status_kanban LIKE '%Sumiu%'
    AND updated_at < now() - interval '60 days';
END;
$$;

-- 4. Refine perform_midnight_lead_migration to update status and track execution
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_base_instance_id uuid;
    v_migrated_count integer := 0;
BEGIN
    -- Find the target BASE instance
    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- Update contacts: ADS -> BASE migration
    -- Also sets status to 'Clientes' for newly migrated base customers
    UPDATE public.contatos
    SET 
        canal_origem = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1;

    -- Update the last execution date in configuracoes
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

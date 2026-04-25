-- Update perform_midnight_lead_migration to also handle REP and C-REP paid customers
-- REP and C-REP use the BASE instance (is_default_base)
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_base_instance_id uuid;
    v_migrated_count integer := 0;
BEGIN
    -- Find the target BASE instance (includes is_default_base=true)
    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- ADS -> BASE migration: customers who paid yesterday move to BASE Clientes
    UPDATE public.contatos
    SET 
        canal_origem = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1;

    -- REP: customers who paid yesterday move to Clientes (same BASE instance)
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'REP' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    -- C-REP: customers who paid yesterday move to Clientes (same BASE instance)
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'C-REP' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

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

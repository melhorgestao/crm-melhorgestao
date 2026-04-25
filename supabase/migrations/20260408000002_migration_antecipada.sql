-- SQL para rodar migração antecipada (midnight migration manual)
-- Migra clientes que pagaram ontem (ultima_venda_em = CURRENT_DATE - 1)
-- ADS Pagou → BASE Clientes
-- BASE Pagou → BASE Clientes  
-- REP Pagou → BASE Clientes
-- C-REP Pagou → BASE Clientes

DO $$
DECLARE
    v_base_instance_id uuid;
    v_ads_count integer := 0;
    v_base_count integer := 0;
    v_rep_count integer := 0;
    v_crep_count integer := 0;
BEGIN
    -- Find the target BASE instance
    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- ADS -> BASE: migrate leads who paid yesterday
    UPDATE public.contatos
    SET 
        canal_origem = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1
    RETURNING count(*) INTO v_ads_count;

    -- BASE Pagou -> BASE Clientes
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        updated_at = now()
    WHERE 
        canal_origem = 'BASE' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND status_kanban = 'Pagou'
    RETURNING count(*) INTO v_base_count;

    -- REP: customers who paid yesterday move to Clientes
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'REP' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND (status_kanban != 'Clientes' OR status_kanban IS NULL)
    RETURNING count(*) INTO v_rep_count;

    -- C-REP: customers who paid yesterday move to Clientes
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'C-REP' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND (status_kanban != 'Clientes' OR status_kanban IS NULL)
    RETURNING count(*) INTO v_crep_count;

    RAISE NOTICE 'Migrated: ADS->BASE: %, BASE Pagou->Clientes: %, REP: %, C-REP: %', v_ads_count, v_base_count, v_rep_count, v_crep_count;
END $$;
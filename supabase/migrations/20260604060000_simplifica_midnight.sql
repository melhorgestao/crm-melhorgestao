-- ============================================================================
-- Simplifica midnight cron: remove dependência de tipo='base'.
-- Agora usa apenas is_default_base = true.
--
-- Razão: com 2+ chips operando ambos como "BASE" (recebem ADS + dispatcham
-- RMKT), tipo perde função operacional. is_default_base é o marcador real
-- de qual chip é o "fallback" pra leads sem claim.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_default_instance_id uuid;
BEGIN
    -- Pega a instância marcada como default (fallback pra leads sem claim)
    SELECT id INTO v_default_instance_id
    FROM public.instancias
    WHERE is_default_base = true AND ativo = true
    LIMIT 1;

    -- ADS -> BASE: cliente que pagou ontem migra pra Clientes
    -- Preserva instancia_id existente (lead "fica" no chip dono)
    UPDATE public.contatos
    SET canal_origem = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(instancia_id, v_default_instance_id),
        updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;

    UPDATE public.contatos
    SET status_kanban = 'Clientes',
        instancia_id = COALESCE(instancia_id, v_default_instance_id),
        updated_at = now()
    WHERE canal_origem = 'REP'
      AND ultima_venda_em = CURRENT_DATE - 1
      AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    UPDATE public.contatos
    SET status_kanban = 'Clientes',
        instancia_id = COALESCE(instancia_id, v_default_instance_id),
        updated_at = now()
    WHERE canal_origem = 'C-REP'
      AND ultima_venda_em = CURRENT_DATE - 1
      AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    INSERT INTO public.configuracoes (chave, valor)
    VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
    ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

    RETURN json_build_object('success', true);
END;
$$;

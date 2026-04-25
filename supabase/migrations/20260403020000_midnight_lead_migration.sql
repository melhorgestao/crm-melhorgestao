-- 1. Add is_default_base to public.instancias
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='instancias' AND column_name='is_default_base') THEN
        ALTER TABLE public.instancias ADD COLUMN is_default_base boolean DEFAULT false;
    END IF;
END $$;

-- 2. Insert the instances provided by the user
-- ADS: +551199128-2579
INSERT INTO public.instancias (nome, tipo, numero_final, is_default_base)
VALUES ('Instância Tráfego (ADS)', 'ads', '2579', false)
ON CONFLICT (id) DO UPDATE SET 
    nome = EXCLUDED.nome, 
    tipo = EXCLUDED.tipo, 
    numero_final = EXCLUDED.numero_final;

-- BASE: +554599851-0512
INSERT INTO public.instancias (nome, tipo, numero_final, is_default_base)
VALUES ('Instância Recorrência (BASE)', 'base', '0512', true)
ON CONFLICT (id) DO UPDATE SET 
    nome = EXCLUDED.nome, 
    tipo = EXCLUDED.tipo, 
    is_default_base = EXCLUDED.is_default_base,
    numero_final = EXCLUDED.numero_final;

-- 3. Create function to migrate leads from ADS to BASE at midnight
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

    -- Update contacts: Lead must be ADS and have bought BEFORE the current date
    UPDATE public.contatos
    SET 
        canal_origem = 'BASE',
        instancia_id = COALESCE(v_base_instance_id, instancia_id)
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1;

    RETURN json_build_object(
        'success', true,
        'migrated_count', v_migrated_count,
        'target_instance_id', v_base_instance_id
    );
END;
$$;

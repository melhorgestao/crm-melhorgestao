-- Migration: Canal Atual + Tag New para transferência midnight
-- Rode este SQL no Supabase SQL Editor

-- 1. Adiciona coluna canal_atual (canal atual para visualização no Kanban)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS canal_atual text;

-- 2. Adiciona coluna is_novo (para tag "Novo" azul por 24h após transferência)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS is_novo boolean DEFAULT false;

-- 3. Adiciona coluna novo_ate (timestamp até quando a tag "Novo" expira)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS novo_ate timestamptz;

-- 4. Atualiza canal_atual baseado no canal_origem atual (dados existentes)
UPDATE public.contatos SET canal_atual = canal_origem WHERE canal_atual IS NULL;

-- 5. Função de migração midnight: ADS -> BASE
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_base_instance_id uuid;
    v_migrated_count integer := 0;
    v_next_midnight timestamptz;
BEGIN
    v_next_midnight := (CURRENT_DATE + 1)::timestamptz;

    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- ADS -> BASE: canal_atual muda, is_novo = true até próximo midnight
    UPDATE public.contatos
    SET 
        canal_atual = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        is_novo = true,
        novo_ate = v_next_midnight,
        updated_at = now()
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1;

    GET DIAGNOSTICS v_migrated_count = ROW_COUNT;

    -- BASE Pagou -> Clientes
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        is_novo = true,
        novo_ate = v_next_midnight,
        updated_at = now()
    WHERE 
        canal_origem = 'BASE' 
        AND status_kanban = 'Pagou'
        AND ultima_venda_em = CURRENT_DATE - 1;

    -- Desativa tags expiradas
    UPDATE public.contatos 
    SET is_novo = false 
    WHERE is_novo = true 
      AND novo_ate IS NOT NULL 
      AND novo_ate <= now();

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

-- 6. Verificação final
SELECT canal_origem, canal_atual, status_kanban, count(*) as total
FROM contatos GROUP BY canal_origem, canal_atual, status_kanban
ORDER BY canal_origem, canal_atual, status_kanban;
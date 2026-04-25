-- INVENTORY PERFORMANCE SNAPSHOT
-- Tabela para armazenar o saldo calculado e evitar recalcular milhares de pedidos em tempo real.

BEGIN;

CREATE TABLE IF NOT EXISTS public.estoque_snapshot (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    prod_id uuid REFERENCES public.produtos(id),
    prod_nome text,
    estado text,
    entrada int DEFAULT 0,
    saida int DEFAULT 0,
    saldo int DEFAULT 0,
    updated_at timestamptz DEFAULT now()
);

-- Função para atualizar o snapshot a partir da get_estoque_completo()
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Limpa o snapshot atual
    DELETE FROM public.estoque_snapshot;

    -- Insere os dados atualizados vindos da verdade (pedidos + lotes)
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now()
    FROM public.get_estoque_completo();
END;
$$;

-- Executa a primeira carga
SELECT public.atualizar_estoque_snapshot();

COMMIT;

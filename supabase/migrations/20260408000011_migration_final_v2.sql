-- Migration COMPLETA para lacrar de vez o kanban
-- Rode este SQL no Supabase SQL Editor

-- 1. CORRIGE instancia_id para REP, C-REP, BASE (deve ser BASE)
DO $$
DECLARE v_base_instance_id uuid;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- Atualiza REP sem instância
    UPDATE public.contatos SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'REP' AND instancia_id IS NULL;

    -- Atualiza C-REP sem instância
    UPDATE public.contatos SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'C-REP' AND instancia_id IS NULL;

    -- Atualiza BASE sem instância
    UPDATE public.contatos SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'BASE' AND instancia_id IS NULL;

    RAISE NOTICE 'INSTANCIA CORRIGIDA: REP, C-REP e BASE agora são BASE (id: %)', v_base_instance_id;
END $$;

-- 2. Atualiza ultima_venda_em com data+HORA do último pedido
UPDATE public.contatos c
SET ultima_venda_em = sub.max_datetime
FROM (
    SELECT contato_id, MAX(created_at) as max_datetime
    FROM public.pedidos
    GROUP BY contato_id
) sub
WHERE c.id = sub.contato_id;

-- 3. Cria/atualiza trigger para atualizar ultima_venda_em com datetime
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_last_order_datetime timestamptz;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    SELECT MAX(created_at) INTO v_last_order_datetime FROM pedidos WHERE contato_id = NEW.contato_id;
    UPDATE contatos SET ultima_venda_em = v_last_order_datetime WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido 
AFTER INSERT ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 4. Trigger para atualização via lancamentos_socios (VENDA manual)
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = now() WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda 
AFTER INSERT ON public.lancamentos_socios 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- 5. ANTECIPA MIDNIGHT: Move clientes de ONTEM (não precisa esperar meia-noite)
DO $$
DECLARE v_base_instance_id uuid; v_count integer;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE + Clientes (quem pagou anteontem ou antes, baseado na ultima_venda)
    UPDATE public.contatos 
    SET canal_origem = 'BASE', status_kanban = 'Clientes', 
        instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em IS NOT NULL 
    AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'ADS -> BASE Clientes: %', v_count;

    -- BASE Pagou -> Clientes
    UPDATE public.contatos 
    SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em IS NOT NULL 
    AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'BASE Pagou -> Clientes: %', v_count;

    -- REP -> Clientes (independentemente de status_kanban, se tem venda)
    UPDATE public.contatos 
    SET status_kanban = 'Clientes', 
        instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em IS NOT NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'REP -> Clientes: %', v_count;

    -- C-REP -> Clientes
    UPDATE public.contatos 
    SET status_kanban = 'Clientes', 
        instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em IS NOT NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'C-REP -> Clientes: %', v_count;

    RAISE NOTICE 'MIDNIGHT ANTECIPADO CONCLUÍDO! Cards Pagou movidos para Clientes.';
END $$;

-- 6. Verificação final
SELECT 
    canal_origem, 
    status_kanban, 
    count(*) as total,
    count(instancia_id) as com_instancia,
    count(ultima_venda_em) as com_ultima_venda
FROM contatos 
GROUP BY canal_origem, status_kanban
ORDER BY canal_origem, status_kanban;
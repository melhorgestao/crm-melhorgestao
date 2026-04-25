-- Migration completa: corrige ultima_venda_em + instancia + migração
-- Rode este SQL no Supabase SQL Editor

-- 1. Atualiza ultima_venda_em com a data do ÚLTIMO pedido de cada contato
UPDATE public.contatos c
SET ultima_venda_em = (
    SELECT MAX(p.created_at)::date 
    FROM public.pedidos p 
    WHERE p.contato_id = c.id
)
WHERE EXISTS (
    SELECT 1 FROM public.pedidos p WHERE p.contato_id = c.id
);

-- 2. Corrige instância de REP e C-REP que estão com NULL (atribui instância BASE)
DO $$
DECLARE v_base_instance_id uuid;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;
    
    -- Atualiza REP com instância NULL para BASE
    UPDATE public.contatos 
    SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'REP' AND instancia_id IS NULL;
    
    -- Atualiza C-REP com instância NULL para BASE
    UPDATE public.contatos 
    SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'C-REP' AND instancia_id IS NULL;
    
    RAISE NOTICE 'REP/C-REP corrigidos para instância BASE';
END $$;

-- 3. Trigger para atualizar ultima_venda_em quando novo pedido é criado
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_last_order_date date;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    SELECT MAX(created_at)::date INTO v_last_order_date 
    FROM pedidos WHERE contato_id = NEW.contato_id;
    UPDATE contatos SET ultima_venda_em = v_last_order_date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido 
AFTER INSERT ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 4. Trigger para atualizar ultima_venda_em quando lançamento VENDA é criado
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = CURRENT_DATE WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda 
AFTER INSERT ON public.lancamentos_socios 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- 5. Executar migração de clientes que pagaram ontem (para todos canais)
DO $$
DECLARE v_base_instance_id uuid;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE + Clientes
    UPDATE public.contatos SET canal_origem = 'BASE', status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;

    -- BASE Pagou -> Clientes (mantém instância BASE)
    UPDATE public.contatos SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em = CURRENT_DATE - 1 AND status_kanban = 'Pagou';

    -- REP -> Clientes (recebe instância BASE)
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em = CURRENT_DATE - 1;

    -- C-REP -> Clientes (recebe instância BASE)
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em = CURRENT_DATE - 1;

    RAISE NOTICE 'Migração concluída com sucesso!';
END $$;
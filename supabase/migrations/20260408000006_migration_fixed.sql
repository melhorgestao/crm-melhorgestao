-- Migration completa - renomeia coluna + executa migração
-- Rode este SQL no Supabase SQL Editor

-- 1. Renomear coluna
ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;

-- 2. Adicionar triggers
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
CREATE TRIGGER trigger_update_ultima_venda AFTER INSERT ON public.lancamentos_socios
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_last_order_date date;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    SELECT MAX(created_at)::date INTO v_last_order_date FROM pedidos WHERE contato_id = NEW.contato_id;
    UPDATE contatos SET ultima_venda_em = v_last_order_date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido AFTER INSERT ON public.pedidos
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 3. Migrar clientes de ontem (sem RETURNING, usa GET DIAGNOSTICS)
DO $$
DECLARE
    v_base_instance_id uuid;
    v_ads_count integer;
    v_base_count integer;
    v_rep_count integer;
    v_crep_count integer;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE
    UPDATE public.contatos SET canal_origem = 'BASE', status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_ads_count = ROW_COUNT;

    -- BASE Pagou -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em = CURRENT_DATE - 1 AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_base_count = ROW_COUNT;

    -- REP -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_rep_count = ROW_COUNT;

    -- C-REP -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_crep_count = ROW_COUNT;

    RAISE NOTICE 'Migrated: ADS->BASE: %, BASE Pagou->Clientes: %, REP: %, C-REP: %', v_ads_count, v_base_count, v_rep_count, v_crep_count;
END $$;
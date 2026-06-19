-- ============================================================================
-- Fix: contato em em_fechamento que recebe venda manual NÃO virava cliente.
--
-- Diagnóstico:
--  - Trigger trigger_contato_virou_cliente (mig 20260619050000) existe mas
--    pode ter sido aplicado SEM efeito no Claudio (pedido inserido por
--    outro caminho, ou trigger nem rodou em prod).
--  - Cron processar_transicoes_estado_contato bloco 5 só processa
--    em_fechamento APÓS 48h. Claudio tá há 10h → cron não pega.
--
-- Correções:
--  1) BACKFILL imediato — todo contato em em_fechamento COM pedido
--     ativo vira cliente AGORA.
--  2) Re-aplica trigger garantindo idempotência.
--  3) Atualiza cron: bloco 5 ganha condição "OR ja_comprou=true"
--     sem esperar 48h.
-- ============================================================================

-- 1) BACKFILL
UPDATE public.contatos c
   SET ja_comprou         = true,
       ultima_interacao   = 'cliente',
       data_cliente       = COALESCE(data_cliente, NOW()),
       data_em_fechamento = NULL,
       data_aguardando_pagamento = NULL,
       primeira_venda_em  = COALESCE(primeira_venda_em, (SELECT MIN(data) FROM public.pedidos p WHERE p.contato_id = c.id)),
       ultima_venda_em    = COALESCE(ultima_venda_em,   (SELECT MAX(data) FROM public.pedidos p WHERE p.contato_id = c.id)),
       updated_at         = NOW()
 WHERE c.ultima_interacao IN ('em_fechamento','aguardando_pagamento')
   AND EXISTS (
     SELECT 1 FROM public.pedidos p
      WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'
   );

-- 2) Trigger re-aplicado (idempotente)
CREATE OR REPLACE FUNCTION public.trigger_contato_virou_cliente()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.contato_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status_pedido = 'cancelado' THEN RETURN NEW; END IF;

  UPDATE public.contatos
     SET ja_comprou                = true,
         ultima_interacao          = 'cliente',
         data_cliente              = COALESCE(data_cliente, NOW()),
         data_em_fechamento        = NULL,
         data_aguardando_pagamento = NULL,
         primeira_venda_em         = COALESCE(primeira_venda_em, NOW()::date),
         ultima_venda_em           = NOW()::date,
         updated_at                = NOW()
   WHERE id = NEW.contato_id;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_contato_virou_cliente ON public.pedidos;
CREATE TRIGGER trg_contato_virou_cliente
  AFTER INSERT ON public.pedidos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_contato_virou_cliente();

-- 3) Cron de transições: bloco 5 (em_fechamento) ganha condição extra
--    pra contatos que já compraram. Substituição cirúrgica da função.
CREATE OR REPLACE FUNCTION public.processar_transicoes_estado_contato()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ativacao_nunca_mais   INTEGER := 0;
  v_start_timeout         INTEGER := 0;
  v_follow_up_timeout     INTEGER := 0;
  v_wait_expirado         INTEGER := 0;
  v_em_fechamento_timeout INTEGER := 0;
  v_em_fechamento_pago    INTEGER := 0;
  v_rmkt_timeout          INTEGER := 0;
  v_suporte_timeout       INTEGER := 0;
BEGIN
  -- 1) ativacao 3+ tentativas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'ativacao_contatos'
    AND ativacao_tentativas >= 3
    AND data_ultimo_ativacao < NOW() - INTERVAL '3 days';
  GET DIAGNOSTICS v_ativacao_nunca_mais = ROW_COUNT;

  -- 2) start 24h sem interação → wait_follow_up
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up'
      END,
      suporte_motivo = CASE WHEN canal_atual IN ('REP', 'C-REP') THEN 'rep_start_timeout' ELSE suporte_motivo END,
      data_suporte   = CASE WHEN canal_atual IN ('REP', 'C-REP') THEN NOW() ELSE data_suporte END,
      data_wait_follow_up = CASE WHEN NOT ja_comprou AND canal_atual NOT IN ('REP', 'C-REP') THEN NOW() ELSE data_wait_follow_up END,
      updated_at = NOW()
  WHERE ultima_interacao = 'start' AND data_start < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_start_timeout = ROW_COUNT;

  -- 3) follow_up sem resposta 24h → wait_follow_up
  UPDATE public.contatos
  SET ultima_interacao = 'wait_follow_up', data_wait_follow_up = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'follow_up'
    AND data_ultimo_follow_up < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) wait_follow_up 3+ tentativas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE ultima_interacao = 'wait_follow_up' AND follow_up_tentativas >= 3;
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 5a) NOVO: em_fechamento COM ja_comprou=true OU pedido ativo → cliente IMEDIATO
  -- (Sem esperar 48h. Cobre vendas manuais via UI e qualquer outro caminho
  -- que não passou pelo trigger AFTER INSERT pedidos.)
  UPDATE public.contatos c
  SET ultima_interacao   = 'cliente',
      data_cliente       = COALESCE(data_cliente, NOW()),
      data_em_fechamento = NULL,
      ja_comprou         = true,
      ultima_venda_em    = COALESCE(ultima_venda_em, NOW()::date),
      updated_at         = NOW()
  WHERE c.ultima_interacao = 'em_fechamento'
    AND (
      c.ja_comprou = true
      OR EXISTS (
        SELECT 1 FROM public.pedidos p
         WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'
      )
    );
  GET DIAGNOSTICS v_em_fechamento_pago = ROW_COUNT;

  -- 5b) em_fechamento parado 48h SEM venda → fallback
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE
        WHEN NOT ja_comprou AND canal_atual NOT IN ('REP', 'C-REP') THEN NOW()
        ELSE data_wait_follow_up END,
      data_em_fechamento = NULL,
      updated_at = NOW()
  WHERE ultima_interacao = 'em_fechamento'
    AND data_em_fechamento < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  -- 6) rmkt sem resposta 3 dias → cliente
  UPDATE public.contatos
  SET ultima_interacao = 'cliente',
      rmkt_consecutive_silenciosos = rmkt_consecutive_silenciosos + 1,
      updated_at = NOW()
  WHERE ultima_interacao = 'rmkt'
    AND data_ultimo_rmkt < NOW() - INTERVAL '3 days'
    AND rmkt_respondeu_em IS NULL;
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

  -- 7) suporte 48h sem msg → fallback
  UPDATE public.contatos
  SET ultima_interacao = CASE WHEN ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE WHEN NOT ja_comprou THEN NOW() ELSE data_wait_follow_up END,
      estado_antes_suporte = NULL, data_suporte = NULL, suporte_motivo = NULL,
      updated_at = NOW()
  WHERE ultima_interacao = 'suporte'
    AND data_suporte < NOW() - INTERVAL '48 hours'
    AND canal_atual NOT IN ('REP', 'C-REP');
  GET DIAGNOSTICS v_suporte_timeout = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'ativacao_nunca_mais', v_ativacao_nunca_mais,
    'start_timeout', v_start_timeout,
    'follow_up_timeout', v_follow_up_timeout,
    'wait_expirado', v_wait_expirado,
    'em_fechamento_pago_imediato', v_em_fechamento_pago,
    'em_fechamento_timeout', v_em_fechamento_timeout,
    'rmkt_timeout', v_rmkt_timeout,
    'suporte_timeout', v_suporte_timeout
  );
END $$;

GRANT EXECUTE ON FUNCTION public.processar_transicoes_estado_contato()
  TO authenticated, anon, service_role;

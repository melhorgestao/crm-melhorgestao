-- ============================================================================
-- State machine de contato completa — substituí rem_status + colunas legacy
--
-- Estados: NULL, start, wait_follow_up, em_fechamento, rmkt, follow_up,
--          rastreio, cliente, NUNCA_MAIS
--
-- Fluxos:
--   LEAD:    NULL → start → wait_follow_up ⇄ follow_up → em_fechamento → cliente
--   CLIENTE: cliente ⇄ rmkt / rastreio → em_fechamento → cliente
--
-- Aplicado em fases pra não quebrar workflow chip 2 em produção.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- FASE 1: ADICIONA COLUNAS NOVAS (aditivo, zero risco)
-- ----------------------------------------------------------------------------

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS ultima_interacao TEXT,
  ADD COLUMN IF NOT EXISTS ja_comprou BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS data_apresentacao TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_wait_follow_up TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_em_fechamento TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_cliente TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_ultimo_rmkt TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_ultimo_follow_up TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_ultimo_rastreio TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_nunca_mais TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rmkt_respondeu_em TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rmkt_consecutive_silenciosos INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS follow_up_tentativas INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.contatos.ultima_interacao IS
  'Estado canônico atual: NULL | start | wait_follow_up | em_fechamento | rmkt | follow_up | rastreio | cliente | NUNCA_MAIS';
COMMENT ON COLUMN public.contatos.ja_comprou IS
  'true se contato já teve pelo menos 1 pedido pago. Set por trigger.';
COMMENT ON COLUMN public.contatos.rmkt_consecutive_silenciosos IS
  'Quantas RMKT consecutivas o contato não respondeu. Reset quando responde. Excluir de campanha quando >= 3.';
COMMENT ON COLUMN public.contatos.follow_up_tentativas IS
  'Tentativas de Follow-up já feitas (0, 1, 2). Após 3, vai pra NUNCA_MAIS.';

-- ----------------------------------------------------------------------------
-- FASE 2: BACKFILL — popula novas colunas com base no estado atual
-- ----------------------------------------------------------------------------

-- ja_comprou: derive de pedidos pagos
UPDATE public.contatos c
SET ja_comprou = true
WHERE EXISTS (
  SELECT 1 FROM public.pedidos p
  WHERE p.contato_id = c.id AND p.status_pagamento = 'pago'
)
AND ja_comprou = false;

-- ultima_interacao backfill conservador:
-- - ja_comprou = true → 'cliente' (cadastrado, modo escuta)
-- - rem_status = 'enviado' → 'rmkt' (recém-disparado, ainda processando)
-- - rem_status = 'respondeu' → 'em_fechamento' (engajado, dar atenção)
-- - resto → NULL (lead novo, vai pelo Start quando interagir)
UPDATE public.contatos
SET ultima_interacao = CASE
    WHEN ja_comprou = true THEN 'cliente'
    WHEN rem_status = 'enviado' THEN 'rmkt'
    WHEN rem_status = 'respondeu' THEN 'em_fechamento'
    ELSE NULL
END
WHERE ultima_interacao IS NULL;

-- data_cliente backfill: usa última venda
UPDATE public.contatos
SET data_cliente = ultima_venda_em::TIMESTAMPTZ
WHERE ja_comprou = true AND data_cliente IS NULL;

-- ----------------------------------------------------------------------------
-- FASE 3: TRIGGER ja_comprou — atualiza automaticamente
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.trigger_set_ja_comprou()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status_pagamento = 'pago' AND NEW.contato_id IS NOT NULL THEN
    UPDATE public.contatos
    SET ja_comprou = true,
        data_cliente = COALESCE(data_cliente, NOW()),
        ultima_interacao = COALESCE(ultima_interacao, 'cliente'),
        updated_at = NOW()
    WHERE id = NEW.contato_id AND ja_comprou = false;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS pedidos_set_ja_comprou ON public.pedidos;
CREATE TRIGGER pedidos_set_ja_comprou
  AFTER INSERT OR UPDATE OF status_pagamento
  ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_set_ja_comprou();

-- ----------------------------------------------------------------------------
-- FASE 4: ATUALIZA RPC claim_proximo_lead_rmkt — usa novo schema
-- (substitui dependência de rem_status + rem_aguardando_resposta)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id UUID,
  p_dias_gap INTEGER DEFAULT 30
)
RETURNS TABLE (
  id UUID,
  nome TEXT,
  telefone TEXT,
  rem_tem_foto BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao = 'rmkt',
      data_ultimo_rmkt = NOW(),
      instancia_id = p_instancia_id,
      updated_at = NOW()
  WHERE c.id = (
    SELECT c2.id
    FROM public.contatos c2
    WHERE c2.ja_comprou = true                                    -- só cliente recebe RMKT
      AND c2.ultima_interacao = 'cliente'                         -- só os em modo escuta
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.rmkt_consecutive_silenciosos < 3                     -- esgota após 3 sem resposta
      AND (c2.data_ultimo_rmkt IS NULL OR c2.data_ultimo_rmkt < NOW() - (p_dias_gap || ' days')::INTERVAL)
      AND c2.data_cliente < NOW() - (p_dias_gap || ' days')::INTERVAL  -- mín 30d desde virou cliente
    ORDER BY c2.rem_tem_foto DESC NULLS LAST, c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone, c.rem_tem_foto;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(UUID, INTEGER)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- FASE 5: RPC claim_proximo_lead_followup — Follow-up workflow vai usar
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup(
  p_instancia_id UUID
)
RETURNS TABLE (
  id UUID,
  nome TEXT,
  telefone TEXT,
  tentativa INTEGER  -- 1, 2 ou 3 (qual mensagem mandar)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao = 'follow_up',
      data_ultimo_follow_up = NOW(),
      follow_up_tentativas = follow_up_tentativas + 1,
      instancia_id = p_instancia_id,
      updated_at = NOW()
  WHERE c.id = (
    SELECT c2.id
    FROM public.contatos c2
    WHERE c2.ja_comprou = false                              -- só lead recebe Follow-up
      AND c2.ultima_interacao = 'wait_follow_up'             -- só os esperando
      AND c2.telefone IS NOT NULL
      AND c2.follow_up_tentativas < 3                        -- esgota após 3 tentativas
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.data_wait_follow_up < NOW() - CASE c2.follow_up_tentativas
            WHEN 0 THEN INTERVAL '24 hours'    -- 1ª tentativa após 24h
            WHEN 1 THEN INTERVAL '3 days'      -- 2ª após 3d
            WHEN 2 THEN INTERVAL '7 days'      -- 3ª após 7d
            ELSE INTERVAL '100 years'          -- nunca
          END
    ORDER BY c2.rem_tem_foto DESC NULLS LAST, c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone, c.follow_up_tentativas;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(UUID)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- FASE 6: CRON DE TRANSIÇÕES — executa periódicamente (hourly via Supabase cron)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.processar_transicoes_estado_contato()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rmkt_timeout INTEGER;
  v_follow_up_timeout INTEGER;
  v_em_fechamento_timeout INTEGER;
  v_wait_expirado INTEGER;
BEGIN
  -- 1) RMKT sem resposta há 3 dias → volta a 'cliente'
  --    Incrementa silenciosos (pra eventual exclusão futura)
  UPDATE public.contatos
  SET ultima_interacao = 'cliente',
      rmkt_consecutive_silenciosos = rmkt_consecutive_silenciosos + 1,
      updated_at = NOW()
  WHERE ultima_interacao = 'rmkt'
    AND data_ultimo_rmkt < NOW() - INTERVAL '3 days'
    AND rmkt_respondeu_em IS NULL;
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

  -- 2) Follow_up sem resposta há 24h → volta a 'wait_follow_up'
  --    Pronto pra próxima tentativa após intervalo crescente
  UPDATE public.contatos
  SET ultima_interacao = 'wait_follow_up',
      data_wait_follow_up = NOW(),
      updated_at = NOW()
  WHERE ultima_interacao = 'follow_up'
    AND data_ultimo_follow_up < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 3) Follow_up tentativas esgotadas (3 tentativas, sem fechar) → 'NUNCA_MAIS'
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS',
      data_nunca_mais = NOW(),
      updated_at = NOW()
  WHERE ultima_interacao = 'wait_follow_up'
    AND follow_up_tentativas >= 3;
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 4) Em_fechamento parado há 48h → volta ao estado anterior
  --    (cliente se ja_comprou, senão wait_follow_up)
  UPDATE public.contatos
  SET ultima_interacao = CASE WHEN ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE
          WHEN NOT ja_comprou THEN NOW()
          ELSE data_wait_follow_up
      END,
      updated_at = NOW()
  WHERE ultima_interacao = 'em_fechamento'
    AND data_em_fechamento < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  -- Log
  INSERT INTO public.log_atividades (usuario, acao, tabela_afetada, detalhe)
  VALUES (
    'Sistema (cron transições)',
    'Estados atualizados',
    'contatos',
    json_build_object(
      'rmkt_timeout', v_rmkt_timeout,
      'follow_up_timeout', v_follow_up_timeout,
      'em_fechamento_timeout', v_em_fechamento_timeout,
      'tentativas_esgotadas', v_wait_expirado
    )::text
  );

  RETURN jsonb_build_object(
    'success', true,
    'rmkt_timeout', v_rmkt_timeout,
    'follow_up_timeout', v_follow_up_timeout,
    'em_fechamento_timeout', v_em_fechamento_timeout,
    'tentativas_esgotadas', v_wait_expirado
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.processar_transicoes_estado_contato()
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- FASE 7: DROP COLUNAS LEGACY rem_*
-- (rem_tem_foto MANTÉM — usado em ORDER BY workflows)
-- ----------------------------------------------------------------------------

ALTER TABLE public.contatos
  DROP COLUMN IF EXISTS rem_aguardando_resposta,
  DROP COLUMN IF EXISTS rem_campanha,
  DROP COLUMN IF EXISTS rem_enviado_em,
  DROP COLUMN IF EXISTS rem_foto_url,
  DROP COLUMN IF EXISTS rem_instancia_evolution,
  DROP COLUMN IF EXISTS rem_observacoes,
  DROP COLUMN IF EXISTS rem_qualificado_em,
  DROP COLUMN IF EXISTS rem_respondeu_em,
  DROP COLUMN IF EXISTS rem_status,
  DROP COLUMN IF EXISTS rem_tentativas;

-- rem_tem_foto FICA — usado pra priorização

NOTIFY pgrst, 'reload schema';

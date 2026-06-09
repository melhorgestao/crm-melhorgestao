-- ============================================================================
-- Calibração v2: Suporte, ADS/BUYER tags, REP→suporte, simplifica RMKT
--
-- Mudanças:
--   1. Renomeia data_apresentacao → data_start
--   2. Adiciona data_suporte, suporte_motivo, duvidas_consecutivas
--   3. Adiciona data_ultimo_rmkt (NÃO EXISTIA na produção apesar das migrations)
--   4. DROP status_kanban (Kanban derivado de ultima_interacao via frontend)
--   5. RPC touch_data_ultimo_ativacao (1x/dia ao responder lead em ativação)
--   6. Atualiza cron processar_transicoes_estado_contato:
--      - start 24h → fallback por canal (REP→suporte, ADS→wait, demais→ativacao)
--      - em_fechamento 24h → fallback por canal
--      - rmkt 3d sem resposta → cliente
--      - suporte 48h sem msg nova → cliente/wait/ativacao por canal (REP fica)
--   7. RPC claim_proximo_lead_rmkt simplificada (sem rmkt_consecutive_silenciosos)
--   8. compute_tag_kanban com tags ADS e BUYER, sem OFF
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Renomeia data_apresentacao → data_start
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'contatos'
      AND column_name = 'data_apresentacao'
  ) THEN
    ALTER TABLE public.contatos RENAME COLUMN data_apresentacao TO data_start;
  END IF;
END $$;

-- Garante coluna data_start
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS data_start TIMESTAMPTZ;

-- ----------------------------------------------------------------------------
-- 2. Novas colunas: suporte + data_ultimo_rmkt
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS data_suporte         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suporte_motivo       TEXT,
  ADD COLUMN IF NOT EXISTS duvidas_consecutivas INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS data_ultimo_rmkt     TIMESTAMPTZ;

COMMENT ON COLUMN public.contatos.data_suporte IS
  'Timestamp de quando entrou em estado suporte';
COMMENT ON COLUMN public.contatos.suporte_motivo IS
  'Razão da entrada em suporte: pedido_cliente, duvida_complexa, mau_comportamento, cinco_duvidas, rep_start_timeout, rep_fechamento_timeout, comando_dono';
COMMENT ON COLUMN public.contatos.duvidas_consecutivas IS
  'Contador resetado pelo AGENT quando intent != duvida; 5+ → suporte automático';
COMMENT ON COLUMN public.contatos.data_ultimo_rmkt IS
  'Timestamp do último disparo de RMKT (gap de 40d entre disparos)';

-- ----------------------------------------------------------------------------
-- 3. Drop colunas órfãs / não usadas
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos DROP COLUMN IF EXISTS rmkt_consecutive_silenciosos;
ALTER TABLE public.contatos DROP COLUMN IF EXISTS status_kanban;

-- ----------------------------------------------------------------------------
-- 4. RPC touch_data_ultimo_ativacao (1x/dia ao responder em ativação)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_data_ultimo_ativacao(p_contato_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.contatos
  SET data_ultimo_ativacao = NOW(),
      updated_at           = NOW()
  WHERE id = p_contato_id
    AND ultima_interacao = 'ativacao_contatos'
    AND (data_ultimo_ativacao IS NULL
         OR data_ultimo_ativacao::date < CURRENT_DATE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.touch_data_ultimo_ativacao(UUID)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 5. Cron processar_transicoes_estado_contato (versão final)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.processar_transicoes_estado_contato()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ativacao_nunca_mais   INTEGER;
  v_start_timeout         INTEGER;
  v_follow_up_timeout     INTEGER;
  v_wait_expirado         INTEGER;
  v_em_fechamento_timeout INTEGER;
  v_rmkt_timeout          INTEGER;
  v_suporte_timeout       INTEGER;
BEGIN
  -- 1) Ativação >= 3 tentativas + 3 dias sem nova interação → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS',
      data_nunca_mais  = NOW(),
      updated_at       = NOW()
  WHERE ultima_interacao = 'ativacao_contatos'
    AND ativacao_tentativas >= 3
    AND data_ultimo_ativacao < NOW() - INTERVAL '3 days';
  GET DIAGNOSTICS v_ativacao_nunca_mais = ROW_COUNT;

  -- 2) start 24h sem interação → fallback por canal
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        WHEN canal_atual = 'ADS' THEN 'wait_follow_up'
        ELSE 'ativacao_contatos'
      END,
      suporte_motivo = CASE
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'rep_start_timeout'
        ELSE suporte_motivo
      END,
      data_suporte = CASE
        WHEN canal_atual IN ('REP', 'C-REP') THEN NOW()
        ELSE data_suporte
      END,
      data_wait_follow_up = CASE
        WHEN NOT ja_comprou AND canal_atual = 'ADS' THEN NOW()
        ELSE data_wait_follow_up
      END,
      data_ultimo_ativacao = CASE
        WHEN NOT ja_comprou AND canal_atual NOT IN ('ADS', 'REP', 'C-REP') THEN NOW()
        ELSE data_ultimo_ativacao
      END,
      updated_at = NOW()
  WHERE ultima_interacao = 'start'
    AND data_start < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_start_timeout = ROW_COUNT;

  -- 3) follow_up 24h sem resposta → wait_follow_up (reinicia cronômetro de gap)
  UPDATE public.contatos
  SET ultima_interacao     = 'wait_follow_up',
      data_wait_follow_up  = NOW(),
      updated_at           = NOW()
  WHERE ultima_interacao = 'follow_up'
    AND data_ultimo_follow_up < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) wait_follow_up com >= 3 tentativas esgotadas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS',
      data_nunca_mais  = NOW(),
      updated_at       = NOW()
  WHERE ultima_interacao = 'wait_follow_up'
    AND follow_up_tentativas >= 3;
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 5) em_fechamento 24h sem fechar → fallback por canal
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        WHEN canal_atual = 'ADS' THEN 'wait_follow_up'
        ELSE 'ativacao_contatos'
      END,
      suporte_motivo = CASE
        WHEN canal_atual IN ('REP', 'C-REP') THEN 'rep_fechamento_timeout'
        ELSE suporte_motivo
      END,
      data_suporte = CASE
        WHEN canal_atual IN ('REP', 'C-REP') THEN NOW()
        ELSE data_suporte
      END,
      data_wait_follow_up = CASE
        WHEN NOT ja_comprou AND canal_atual = 'ADS' THEN NOW()
        ELSE data_wait_follow_up
      END,
      data_ultimo_ativacao = CASE
        WHEN NOT ja_comprou AND canal_atual NOT IN ('ADS', 'REP', 'C-REP') THEN NOW()
        ELSE data_ultimo_ativacao
      END,
      typebot_closing_session_id = NULL,
      typebot_closing_session_em = NULL,
      updated_at = NOW()
  WHERE ultima_interacao = 'em_fechamento'
    AND data_em_fechamento < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  -- 6) rmkt 3d sem resposta → cliente
  UPDATE public.contatos
  SET ultima_interacao = 'cliente',
      updated_at       = NOW()
  WHERE ultima_interacao = 'rmkt'
    AND data_ultimo_rmkt < NOW() - INTERVAL '3 days';
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

  -- 7) suporte 48h sem mensagem nova → fallback por canal (REP nunca sai automaticamente)
  UPDATE public.contatos
  SET ultima_interacao = CASE
        WHEN ja_comprou THEN 'cliente'
        WHEN canal_atual = 'ADS' THEN 'wait_follow_up'
        ELSE 'ativacao_contatos'
      END,
      duvidas_consecutivas = 0,
      data_wait_follow_up = CASE
        WHEN NOT ja_comprou AND canal_atual = 'ADS' THEN NOW()
        ELSE data_wait_follow_up
      END,
      data_ultimo_ativacao = CASE
        WHEN NOT ja_comprou AND canal_atual NOT IN ('ADS', 'REP', 'C-REP') THEN NOW()
        ELSE data_ultimo_ativacao
      END,
      updated_at = NOW()
  WHERE ultima_interacao = 'suporte'
    AND data_suporte < NOW() - INTERVAL '48 hours'
    AND updated_at    < NOW() - INTERVAL '48 hours'
    AND canal_atual NOT IN ('REP', 'C-REP');
  GET DIAGNOSTICS v_suporte_timeout = ROW_COUNT;

  RETURN jsonb_build_object(
    'ativacao_nunca_mais',    v_ativacao_nunca_mais,
    'start_timeout',          v_start_timeout,
    'follow_up_timeout',      v_follow_up_timeout,
    'tentativas_esgotadas',   v_wait_expirado,
    'em_fechamento_timeout',  v_em_fechamento_timeout,
    'rmkt_timeout',           v_rmkt_timeout,
    'suporte_timeout',        v_suporte_timeout
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.processar_transicoes_estado_contato()
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 6. RPC claim_proximo_lead_rmkt simplificada (sem rmkt_consecutive_silenciosos)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_rmkt(UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id UUID,
  p_dias_gap     INTEGER DEFAULT 40
)
RETURNS TABLE (id UUID, nome TEXT, telefone TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao = 'rmkt',
      data_ultimo_rmkt = NOW(),
      instancia_id     = p_instancia_id,
      updated_at       = NOW()
  WHERE c.id = (
    SELECT c2.id
    FROM public.contatos c2
    WHERE c2.ja_comprou = true
      AND c2.ultima_interacao = 'cliente'
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND (c2.data_ultimo_rmkt IS NULL OR c2.data_ultimo_rmkt < NOW() - (p_dias_gap || ' days')::INTERVAL)
      AND c2.ultima_venda_em < (NOW() - (p_dias_gap || ' days')::INTERVAL)::date
    ORDER BY c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(UUID, INTEGER)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 7. compute_tag_kanban v2: ADS, BUYER, sem OFF
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.compute_tag_kanban(
  p_ultima_interacao TEXT,
  p_canal_origem     TEXT,
  p_ja_comprou       BOOLEAN,
  p_total_pedidos    BIGINT,
  p_created_at       TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- VIP tem prioridade máxima (cliente fiel com 3+ compras)
  IF p_total_pedidos >= 3 THEN
    RETURN 'VIP';
  END IF;

  -- BUYER: já comprou alguma vez (não-VIP)
  IF p_ja_comprou = true THEN
    RETURN 'BUYER';
  END IF;

  -- REP: representantes
  IF p_canal_origem IN ('REP', 'C-REP') THEN
    RETURN 'REP';
  END IF;

  -- ADS: lead que veio de anúncio
  IF p_canal_origem = 'ADS' THEN
    RETURN 'ADS';
  END IF;

  -- NEW: recém-cadastrado em apresentação (< 48h)
  IF (p_ultima_interacao IS NULL OR p_ultima_interacao = 'start')
     AND p_created_at > NOW() - INTERVAL '48 hours' THEN
    RETURN 'NEW';
  END IF;

  RETURN NULL;
END;
$$;

-- Recalcula tag_kanban para todos os contatos com nova função
UPDATE public.contatos c
SET tag_kanban = sub.nova_tag,
    tag_kanban_ate = CASE
      WHEN sub.nova_tag = 'NEW' THEN c.created_at + INTERVAL '48 hours'
      ELSE NULL
    END,
    updated_at = NOW()
FROM (
  SELECT
    c2.id,
    public.compute_tag_kanban(
      c2.ultima_interacao,
      c2.canal_origem,
      c2.ja_comprou,
      COALESCE(p.total_pedidos, 0),
      c2.created_at
    ) AS nova_tag
  FROM public.contatos c2
  LEFT JOIN (
    SELECT contato_id, COUNT(*) AS total_pedidos
    FROM public.pedidos
    WHERE status_pagamento = 'pago'
    GROUP BY contato_id
  ) p ON p.contato_id = c2.id
) sub
WHERE c.id = sub.id
  AND c.tag_kanban IS DISTINCT FROM sub.nova_tag;

NOTIFY pgrst, 'reload schema';

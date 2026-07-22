-- ============================================================================
-- PLANO A + B: primeiro follow-up dentro da janela de 24h + cadência real.
--
-- A) start -> wait_follow_up agora dispara com 4h de SILÊNCIO DO LEAD (não 24h
--    desde o cardápio). Silêncio = mais recente entre (cardápio enviado
--    data_start) e (última resposta do lead data_ultima_entrada). Isso pega
--    o lead ainda quente e IN-WINDOW, e NUNCA move quem está conversando
--    (chatter fica com data_ultima_entrada recente). Cron passa a rodar de
--    hora em hora (só muda estado; o ENVIO respeita horário/coffee/jitter).
--
-- B) Cadência real por tentativa, sem dupla contagem:
--      tentativa 1: sai assim que entra em wait (o 4h já foi no start->wait)
--      tentativa 2: 3 dias APÓS o último envio
--      tentativa 3: 7 dias APÓS o último envio
--    Antes era 24h flat + retorno de 24h = ~48h entre toques (contagem dupla).
--    Agora o gap é medido de data_ultimo_follow_up (último envio real).
--
-- Labels de subcategoria ('24h'/'3d'/'7d') ficam iguais (casam com os
-- templates). O slot '24h' agora dispara em ~4h — edite o CONTEÚDO dele pra
-- um nudge suave in-window ("quer ajuda pra escolher?").
--
-- NÃO muda: data_start (reapresentação + piso do silêncio), em_fechamento 48h,
-- máx 3 tentativas, RMKT, ritmo por chip.
-- ============================================================================

-- A.1) Timestamp da última entrada do lead (silêncio). Carimbado pelo
--      router-ingest a cada inbound do lead.
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS data_ultima_entrada timestamptz;

COMMENT ON COLUMN public.contatos.data_ultima_entrada IS
  'Quando o LEAD respondeu por último (inbound). Base do relógio de silêncio do start->wait. data_start é o piso.';

-- Backfill best-effort a partir do buffer (pra leads atuais em start).
UPDATE public.contatos c
   SET data_ultima_entrada = sub.ult
  FROM (
    SELECT contato_id, MAX(recebida_em) AS ult
      FROM public.mensagens_buffer
     WHERE direcao = 'in'
     GROUP BY contato_id
  ) sub
 WHERE sub.contato_id = c.id
   AND c.data_ultima_entrada IS NULL;

-- ----------------------------------------------------------------------------
-- A.2) State machine: bloco 2 (start->wait) por silêncio de 4h. Resto idêntico.
-- ----------------------------------------------------------------------------
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
  -- 1) Ativação esgotada → NUNCA_MAIS
  UPDATE public.contatos c
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'ativacao_contatos'
    AND c.ativacao_tentativas >= 3
    AND c.data_ultimo_ativacao < NOW() - INTERVAL '3 days'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_ativacao_nunca_mais = ROW_COUNT;

  -- 2) Start com 4h de SILÊNCIO → wait_follow_up / cliente / suporte
  --    Silêncio = GREATEST(data_start, data_ultima_entrada): pega o cardápio
  --    OU a última resposta do lead — o que for mais recente. Chatter ativo
  --    (resposta recente) NÃO é movido. GREATEST ignora NULL.
  UPDATE public.contatos c
  SET ultima_interacao = CASE
        WHEN c.ja_comprou THEN 'cliente'
        WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up'
      END,
      suporte_motivo = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'rep_start_timeout' ELSE c.suporte_motivo END,
      data_suporte   = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN NOW() ELSE c.data_suporte END,
      data_wait_follow_up = CASE WHEN NOT c.ja_comprou AND c.canal_atual NOT IN ('REP', 'C-REP') THEN NOW() ELSE c.data_wait_follow_up END,
      updated_at = NOW()
  WHERE c.ultima_interacao = 'start'
    AND GREATEST(c.data_start, c.data_ultima_entrada) < NOW() - INTERVAL '4 hours'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_start_timeout = ROW_COUNT;

  -- 3) follow_up sem resposta 24h (permanência no estado) → wait_follow_up
  --    (retorna pra pool de claim; o gap real de 3d/7d é medido no claim a
  --    partir de data_ultimo_follow_up, então este retorno NÃO conta duas vezes).
  UPDATE public.contatos c
  SET ultima_interacao = 'wait_follow_up', data_wait_follow_up = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'follow_up'
    AND c.data_ultimo_follow_up < NOW() - INTERVAL '24 hours'
    AND c.canal_atual NOT IN ('REP', 'C-REP')
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 4) wait_follow_up esgotou 3 tentativas → NUNCA_MAIS
  UPDATE public.contatos c
  SET ultima_interacao = 'NUNCA_MAIS', data_nunca_mais = NOW(), updated_at = NOW()
  WHERE c.ultima_interacao = 'wait_follow_up'
    AND c.follow_up_tentativas >= 3
    AND c.canal_atual NOT IN ('REP', 'C-REP')
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 5a) em_fechamento + ja_comprou → cliente IMEDIATO
  UPDATE public.contatos c
  SET ultima_interacao   = 'cliente',
      data_em_fechamento = NULL,
      ja_comprou         = true,
      primeira_venda_em  = COALESCE(c.primeira_venda_em,
                                    (SELECT MIN(created_at) FROM public.pedidos p
                                      WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'),
                                    NOW()),
      ultima_venda_em    = COALESCE(c.ultima_venda_em,
                                    (SELECT MAX(created_at) FROM public.pedidos p
                                      WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'),
                                    NOW()),
      updated_at         = NOW()
  WHERE c.ultima_interacao = 'em_fechamento'
    AND (c.ja_comprou = true
         OR EXISTS (SELECT 1 FROM public.pedidos p
                     WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'))
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_em_fechamento_pago = ROW_COUNT;

  -- 5b) em_fechamento 48h sem venda → wait_follow_up / cliente / suporte
  UPDATE public.contatos c
  SET ultima_interacao = CASE
        WHEN c.ja_comprou THEN 'cliente'
        WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'suporte'
        ELSE 'wait_follow_up' END,
      suporte_motivo = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN 'rep_fechamento_timeout' ELSE c.suporte_motivo END,
      data_suporte   = CASE WHEN c.canal_atual IN ('REP', 'C-REP') THEN NOW() ELSE c.data_suporte END,
      data_wait_follow_up = CASE
        WHEN NOT c.ja_comprou AND c.canal_atual NOT IN ('REP', 'C-REP') THEN NOW()
        ELSE c.data_wait_follow_up END,
      data_em_fechamento = NULL,
      updated_at = NOW()
  WHERE c.ultima_interacao = 'em_fechamento'
    AND c.data_em_fechamento < NOW() - INTERVAL '48 hours'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  -- 6) RMKT 24h de permanência no estado → cliente
  UPDATE public.contatos c
  SET ultima_interacao = 'cliente', updated_at = NOW()
  WHERE c.ultima_interacao = 'rmkt'
    AND c.data_ultimo_rmkt < NOW() - INTERVAL '24 hours'
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_rmkt_timeout = ROW_COUNT;

  -- 7) Suporte 48h sem ação → estado anterior
  UPDATE public.contatos c
  SET ultima_interacao = CASE WHEN c.ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
      data_wait_follow_up = CASE WHEN NOT c.ja_comprou THEN NOW() ELSE c.data_wait_follow_up END,
      estado_antes_suporte = NULL, data_suporte = NULL, suporte_motivo = NULL,
      updated_at = NOW()
  WHERE c.ultima_interacao = 'suporte'
    AND c.data_suporte < NOW() - INTERVAL '48 hours'
    AND c.canal_atual NOT IN ('REP', 'C-REP')
    AND EXISTS (SELECT 1 FROM public.instancias i
                WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
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

-- ----------------------------------------------------------------------------
-- B) Claim de follow-up: cadência por tentativa (0 / 3d / 7d), do último envio.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup(p_instancia_id uuid)
RETURNS TABLE (id uuid, nome text, telefone text, subcategoria text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET follow_up_reservado_ate = NOW() + INTERVAL '5 minutes',
      instancia_id            = p_instancia_id,
      updated_at              = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ultima_interacao = 'wait_follow_up'
      AND c2.ja_comprou = false
      AND c2.telefone IS NOT NULL
      AND COALESCE(c2.ativacao_tentativas, 0) = 0
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.follow_up_tentativas < 3
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
      -- CADÊNCIA POR TENTATIVA (sem dupla contagem):
      --   tent 1 → gap 0 (o 4h de silêncio já foi no start->wait)
      --   tent 2 → 3 dias após o último envio (data_ultimo_follow_up)
      --   tent 3 → 7 dias após o último envio
      AND COALESCE(c2.data_ultimo_follow_up, c2.data_wait_follow_up, NOW() - INTERVAL '999 days') <
          NOW() - CASE (COALESCE(c2.follow_up_tentativas, 0) + 1)
                    WHEN 1 THEN INTERVAL '0'
                    WHEN 2 THEN INTERVAL '3 days'
                    ELSE     INTERVAL '7 days'
                  END
      AND (c2.follow_up_reservado_ate IS NULL OR c2.follow_up_reservado_ate < NOW())
    ORDER BY COALESCE(c2.data_ultimo_follow_up, c2.data_wait_follow_up) ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone,
            CASE (c.follow_up_tentativas + 1) WHEN 1 THEN '24h' WHEN 2 THEN '3d' ELSE '7d' END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- A.3) Cron de hora em hora (só transita estado; envio respeita horário).
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'state-machine-transicoes') THEN
    PERFORM cron.unschedule('state-machine-transicoes');
  END IF;
  PERFORM cron.schedule(
    'state-machine-transicoes',
    '0 * * * *',
    $cmd$ SELECT public.processar_transicoes_estado_contato() $cmd$
  );
END $$;

NOTIFY pgrst, 'reload schema';

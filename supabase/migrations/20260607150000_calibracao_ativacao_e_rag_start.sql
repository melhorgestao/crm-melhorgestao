-- ============================================================================
-- Calibração da Máquina de Estados: Ativação (3 tentativas) + RAG Start (ADS)
--
-- Alterações:
--   1. Renomeia ativacao_consecutive_silenciosos → ativacao_tentativas
--   2. Dropa coluna ativacao_respondeu_em (não usada mais)
--   3. Atualiza RPC claim_proximo_lead_ativacao:
--      - Grava data_ultimo_ativacao
--      - Incrementa ativacao_tentativas
--      - Filtra quem ja tem >= 3 tentativas
--   4. Atualiza RPC processar_transicoes_estado_contato:
--      - Remove transição ativacao → cliente/follow_up (não existe mais)
--      - Adiciona: ativacao com >= 3 tentativas há 3 dias → NUNCA_MAIS
--   5. Atualiza RPC get_or_create_contato:
--      - Novos contatos entram com ultima_interacao = 'start'
--      - Detecta ADS via p_canal_origem ou palavras-chave na mensagem
--      - Parâmetro p_mensagem TEXT adicionado
--   6. Atualiza trigger_set_ja_comprou:
--      - Reseta ativacao_tentativas e follow_up_tentativas ao comprar
--   7. Atualiza perform_midnight_lead_migration:
--      - Deleta permanentemente contatos com NUNCA_MAIS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Renomeia coluna (safe: usa IF EXISTS via DO block)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'contatos'
      AND column_name = 'ativacao_consecutive_silenciosos'
  ) THEN
    ALTER TABLE public.contatos
      RENAME COLUMN ativacao_consecutive_silenciosos TO ativacao_tentativas;
  END IF;
END $$;

-- Garante que a coluna existe com o nome correto e default 0
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS ativacao_tentativas INTEGER NOT NULL DEFAULT 0;

-- ----------------------------------------------------------------------------
-- 2. Drop da coluna ativacao_respondeu_em (não usada)
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  DROP COLUMN IF EXISTS ativacao_respondeu_em;

-- ----------------------------------------------------------------------------
-- 3. Garante existência de data_ultimo_ativacao (usada pela RPC claim)
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS data_ultimo_ativacao TIMESTAMPTZ;

-- ----------------------------------------------------------------------------
-- 4. Atualiza RPC claim_proximo_lead_ativacao
--    - Grava data_ultimo_ativacao = NOW()
--    - Incrementa ativacao_tentativas
--    - Filtra < 3 tentativas
--    - Filtra últimas_interacao NULL ou ativacao_contatos com gap >= p_dias_gap
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_ativacao(
  p_instancia_id UUID,
  p_campanha TEXT DEFAULT NULL,
  p_dias_gap INTEGER DEFAULT 30
)
RETURNS TABLE (id UUID, nome TEXT, telefone TEXT, rem_tem_foto BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao    = 'ativacao_contatos',
      data_ultimo_ativacao = NOW(),
      ultima_campanha     = COALESCE(p_campanha, 'sem_campanha'),
      ativacao_tentativas = ativacao_tentativas + 1,
      instancia_id        = p_instancia_id,
      updated_at          = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ja_comprou = false                                                      -- apenas leads (não clientes)
      AND (
        c2.ultima_interacao IS NULL                                                   -- nulo (primeira ativação)
        OR (
          c2.ultima_interacao = 'ativacao_contatos'
          AND c2.data_ultimo_ativacao < NOW() - (p_dias_gap || ' days')::INTERVAL    -- gap >= dias configurados
        )
      )
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.ativacao_tentativas < 3                                                  -- máximo 3 tentativas
    ORDER BY c2.rem_tem_foto DESC NULLS LAST, c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone, c.rem_tem_foto;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_ativacao(UUID, TEXT, INTEGER)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 5. Atualiza RPC processar_transicoes_estado_contato
--    - Remove transição ativacao → cliente/follow_up (campanhas não vão para clientes)
--    - Adiciona: ativacao >= 3 tentativas e sem interação há 3 dias → NUNCA_MAIS
--    - Mantém follow_up → wait_follow_up e wait_follow_up ≥ 3 → NUNCA_MAIS
--    - Mantém em_fechamento timeout
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.processar_transicoes_estado_contato()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ativacao_nunca_mais    INTEGER;
  v_follow_up_timeout      INTEGER;
  v_em_fechamento_timeout  INTEGER;
  v_wait_expirado          INTEGER;
BEGIN
  -- 1) Ativação com >= 3 tentativas sem nova interação há 3 dias → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS',
      data_nunca_mais  = NOW(),
      updated_at       = NOW()
  WHERE ultima_interacao = 'ativacao_contatos'
    AND ativacao_tentativas >= 3
    AND data_ultimo_ativacao < NOW() - INTERVAL '3 days';
  GET DIAGNOSTICS v_ativacao_nunca_mais = ROW_COUNT;

  -- 2) Follow-up sem resposta 24h → wait_follow_up
  UPDATE public.contatos
  SET ultima_interacao     = 'wait_follow_up',
      data_wait_follow_up  = NOW(),
      updated_at           = NOW()
  WHERE ultima_interacao = 'follow_up'
    AND data_ultimo_follow_up < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS v_follow_up_timeout = ROW_COUNT;

  -- 3) wait_follow_up com >= 3 tentativas esgotadas → NUNCA_MAIS
  UPDATE public.contatos
  SET ultima_interacao = 'NUNCA_MAIS',
      data_nunca_mais  = NOW(),
      updated_at       = NOW()
  WHERE ultima_interacao = 'wait_follow_up'
    AND follow_up_tentativas >= 3;
  GET DIAGNOSTICS v_wait_expirado = ROW_COUNT;

  -- 4) em_fechamento parado 48h → volta para wait_follow_up (ou cliente se ja_comprou)
  UPDATE public.contatos
  SET ultima_interacao           = CASE WHEN ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END,
      data_wait_follow_up        = CASE WHEN NOT ja_comprou THEN NOW() ELSE data_wait_follow_up END,
      typebot_closing_session_id = NULL,
      typebot_closing_session_em = NULL,
      updated_at                 = NOW()
  WHERE ultima_interacao = 'em_fechamento'
    AND data_em_fechamento < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS v_em_fechamento_timeout = ROW_COUNT;

  RETURN jsonb_build_object(
    'ativacao_nunca_mais',    v_ativacao_nunca_mais,
    'follow_up_timeout',      v_follow_up_timeout,
    'tentativas_esgotadas',   v_wait_expirado,
    'em_fechamento_timeout',  v_em_fechamento_timeout
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.processar_transicoes_estado_contato()
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 6. Atualiza RPC get_or_create_contato
--    - Adiciona parâmetro p_mensagem TEXT para detecção de ADS por keyword
--    - Novos contatos entram com ultima_interacao = 'start'
--    - Contatos existentes com ultima_interacao NULL → atualiza para 'start'
--    - Detecta ADS via p_canal_origem = 'ADS' OU palavras-chave na mensagem
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_or_create_contato(
  p_telefone     TEXT,
  p_nome         TEXT DEFAULT NULL,
  p_instancia_id UUID DEFAULT NULL,
  p_canal_origem TEXT DEFAULT 'BASE',
  p_metadata     JSONB DEFAULT NULL,
  p_mensagem     TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized TEXT;
  v_contato_id UUID;
  v_was_created BOOLEAN := false;
  v_result      jsonb;
  v_is_ads      BOOLEAN := false;
BEGIN
  -- Normaliza telefone (só dígitos)
  v_normalized := REGEXP_REPLACE(p_telefone, '\D', '', 'g');

  -- Tenta encontrar contato existente
  SELECT c.id INTO v_contato_id
  FROM public.contatos c
  WHERE REGEXP_REPLACE(COALESCE(c.telefone, ''), '\D', '', 'g') = v_normalized
  LIMIT 1;

  -- Detecta ADS via canal OU palavras-chave da mensagem
  IF p_canal_origem = 'ADS' OR (
    p_mensagem IS NOT NULL AND
    LOWER(TRIM(p_mensagem)) IN ('saber mais', 'quero saber mais', 'quero saber mais!', 'saber mais!')
  ) THEN
    v_is_ads := true;
  END IF;

  -- Cria contato novo
  IF v_contato_id IS NULL THEN
    INSERT INTO public.contatos (
      nome, telefone, canal_origem, canal_atual,
      instancia_id, ultima_interacao, created_at, updated_at
    )
    VALUES (
      COALESCE(NULLIF(TRIM(p_nome), ''), v_normalized),
      v_normalized,
      CASE WHEN v_is_ads THEN 'ADS' ELSE p_canal_origem END,
      CASE WHEN v_is_ads THEN 'ADS' ELSE p_canal_origem END,
      p_instancia_id,
      'start',   -- sempre entra como start (agente RAG vai enviar cardápio)
      NOW(),
      NOW()
    )
    RETURNING contatos.id INTO v_contato_id;
    v_was_created := true;

  ELSE
    -- Contato existente: atualiza estado para 'start' se estava NULL
    -- e atualiza canal para ADS se detectado
    UPDATE public.contatos
    SET ultima_interacao = COALESCE(ultima_interacao, 'start'),
        canal_origem     = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_origem END,
        canal_atual      = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_atual END,
        updated_at       = NOW()
    WHERE id = v_contato_id
      AND (ultima_interacao IS NULL OR v_is_ads);
  END IF;

  -- Retorna dados completos do contato para o Router
  SELECT jsonb_build_object(
    'id',                        c.id,
    'nome',                      c.nome,
    'telefone',                  c.telefone,
    'ultima_interacao',          c.ultima_interacao,
    'ja_comprou',                c.ja_comprou,
    'bot_pausado_ate',           c.bot_pausado_ate,
    'typebot_closing_session_id', c.typebot_closing_session_id,
    'canal_origem',              c.canal_origem,
    'canal_atual',               c.canal_atual,
    'instancia_id',              c.instancia_id,
    'was_created',               v_was_created
  ) INTO v_result
  FROM public.contatos c
  WHERE c.id = v_contato_id;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB, TEXT)
  TO authenticated, anon, service_role;

-- Revoga grant da assinatura antiga (5 params) caso exista
DROP FUNCTION IF EXISTS public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB);

-- ----------------------------------------------------------------------------
-- 7. Atualiza trigger_set_ja_comprou
--    - Reseta ativacao_tentativas e follow_up_tentativas quando ja_comprou = true
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_set_ja_comprou()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.status_pagamento = 'pago' AND NEW.contato_id IS NOT NULL THEN
    UPDATE public.contatos
    SET ja_comprou           = true,
        data_cliente         = COALESCE(data_cliente, NOW()),
        ultima_interacao     = COALESCE(ultima_interacao, 'cliente'),
        ativacao_tentativas  = 0,
        follow_up_tentativas = 0,
        updated_at           = NOW()
    WHERE id = NEW.contato_id
      AND ja_comprou = false;
  END IF;
  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. Atualiza perform_midnight_lead_migration
--    - Adiciona DELETE de contatos NUNCA_MAIS ao final do cron diário
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_default_instance_id uuid;
BEGIN
    -- Busca instância padrão para atribuição de leads
    SELECT id INTO v_default_instance_id
    FROM public.instancias
    WHERE is_default_base = true AND ativo = true
    LIMIT 1;

    -- ADS que compraram ontem → migra para BASE e marca Clientes no kanban
    UPDATE public.contatos
    SET canal_origem   = 'BASE',
        status_kanban  = 'Clientes',
        instancia_id   = COALESCE(instancia_id, v_default_instance_id),
        updated_at     = now()
    WHERE canal_origem = 'ADS'
      AND ultima_venda_em = CURRENT_DATE - 1;

    -- REP que compraram ontem → Clientes no kanban
    UPDATE public.contatos
    SET status_kanban = 'Clientes',
        instancia_id  = COALESCE(instancia_id, v_default_instance_id),
        updated_at    = now()
    WHERE canal_origem = 'REP'
      AND ultima_venda_em = CURRENT_DATE - 1
      AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    -- C-REP que compraram ontem → Clientes no kanban
    UPDATE public.contatos
    SET status_kanban = 'Clientes',
        instancia_id  = COALESCE(instancia_id, v_default_instance_id),
        updated_at    = now()
    WHERE canal_origem = 'C-REP'
      AND ultima_venda_em = CURRENT_DATE - 1
      AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    -- Limpeza diária: exclui permanentemente todos os contatos banidos (NUNCA_MAIS)
    DELETE FROM public.contatos
    WHERE ultima_interacao = 'NUNCA_MAIS';

    -- Registra execução do cron
    INSERT INTO public.configuracoes (chave, valor)
    VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
    ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

    RETURN json_build_object('success', true);
END;
$$;

NOTIFY pgrst, 'reload schema';

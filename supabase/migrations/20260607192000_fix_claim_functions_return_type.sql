-- ============================================================================
-- FIX COMPLETO: Aplica tudo da migração 20260607190000 de forma idempotente
--
-- A migração original falhou no passo 9 (claim_proximo_lead_ativacao)
-- porque CREATE OR REPLACE não pode alterar return type.
--
-- Este script reaplicará TODAS as alterações de forma segura (IF EXISTS/IF NOT EXISTS).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DROP ultima_campanha
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos DROP COLUMN IF EXISTS ultima_campanha;

-- ----------------------------------------------------------------------------
-- 2. DROP rem_tem_foto
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos DROP COLUMN IF EXISTS rem_tem_foto;

-- ----------------------------------------------------------------------------
-- 2b. DROP tag_vip (substituída por tag_kanban = 'VIP')
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos DROP COLUMN IF EXISTS tag_vip;

-- ----------------------------------------------------------------------------
-- 3. Corrige data_ultimo_ativacao NULL para contatos em ativação
-- ----------------------------------------------------------------------------
UPDATE public.contatos
SET data_ultimo_ativacao = NOW(),
    updated_at           = NOW()
WHERE ultima_interacao = 'ativacao_contatos'
  AND data_ultimo_ativacao IS NULL;

-- ----------------------------------------------------------------------------
-- 4. Garante data_em_fechamento
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS data_em_fechamento TIMESTAMPTZ;

-- ----------------------------------------------------------------------------
-- 5. Troca is_novo + novo_ate por tag_kanban + tag_kanban_ate
-- ----------------------------------------------------------------------------

-- 5a. Adiciona novas colunas
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS tag_kanban     TEXT        DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS tag_kanban_ate TIMESTAMPTZ DEFAULT NULL;

-- 5b. Migra dados existentes (só se is_novo ainda existir)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'contatos' AND column_name = 'is_novo'
  ) THEN
    UPDATE public.contatos
    SET tag_kanban     = 'NEW',
        tag_kanban_ate = novo_ate,
        updated_at     = NOW()
    WHERE is_novo = true
      AND (novo_ate IS NULL OR novo_ate > NOW());
  END IF;
END $$;

-- 5c. Marca OFF para NUNCA_MAIS
UPDATE public.contatos
SET tag_kanban     = 'OFF',
    tag_kanban_ate = NULL,
    updated_at     = NOW()
WHERE ultima_interacao = 'NUNCA_MAIS'
  AND tag_kanban IS DISTINCT FROM 'OFF';

-- 5d. DROP colunas antigas
ALTER TABLE public.contatos DROP COLUMN IF EXISTS is_novo;
ALTER TABLE public.contatos DROP COLUMN IF EXISTS novo_ate;

-- Índice para queries de kanban por tag
CREATE INDEX IF NOT EXISTS idx_contatos_tag_kanban
  ON public.contatos(tag_kanban)
  WHERE tag_kanban IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 6. Função compute_tag_kanban
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.compute_tag_kanban(TEXT, TEXT, BOOLEAN, INTEGER, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS public.compute_tag_kanban(TEXT, TEXT, BOOLEAN, BIGINT, TIMESTAMPTZ);

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
  IF p_ultima_interacao = 'NUNCA_MAIS' THEN
    RETURN 'OFF';
  END IF;

  IF p_total_pedidos >= 3 THEN
    RETURN 'VIP';
  END IF;

  IF p_canal_origem IN ('REP', 'C-REP') THEN
    RETURN 'REP';
  END IF;

  IF (p_ultima_interacao IS NULL OR p_ultima_interacao = 'start')
     AND p_created_at > NOW() - INTERVAL '48 hours' THEN
    RETURN 'NEW';
  END IF;

  RETURN NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. Trigger function: recalcula tag_kanban
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_sync_tag_kanban()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_pedidos BIGINT;
  v_nova_tag      TEXT;
  v_tag_ate       TIMESTAMPTZ;
BEGIN
  SELECT COUNT(*) INTO v_total_pedidos
  FROM public.pedidos
  WHERE contato_id = NEW.id
    AND status_pagamento = 'pago';

  v_nova_tag := public.compute_tag_kanban(
    NEW.ultima_interacao,
    NEW.canal_origem,
    NEW.ja_comprou,
    COALESCE(v_total_pedidos, 0),
    NEW.created_at
  );

  IF v_nova_tag = 'NEW' THEN
    v_tag_ate := NEW.created_at + INTERVAL '48 hours';
  ELSE
    v_tag_ate := NULL;
  END IF;

  IF NEW.tag_kanban IS DISTINCT FROM v_nova_tag
     OR NEW.tag_kanban_ate IS DISTINCT FROM v_tag_ate THEN
    NEW.tag_kanban     := v_nova_tag;
    NEW.tag_kanban_ate := v_tag_ate;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_tag_kanban ON public.contatos;

CREATE TRIGGER trg_sync_tag_kanban
  BEFORE INSERT OR UPDATE OF ultima_interacao, canal_origem, ja_comprou, tag_kanban
  ON public.contatos
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_tag_kanban();

-- ----------------------------------------------------------------------------
-- 8. Recalcula tag_kanban para todos os contatos existentes
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 9. DROP + Recria claim_proximo_lead_ativacao (FIX DO ERRO 42P13)
--    Old return: (id UUID, nome TEXT, telefone TEXT, rem_tem_foto BOOLEAN)
--    New return: (id UUID, nome TEXT, telefone TEXT)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_ativacao(UUID, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_ativacao(
  p_instancia_id UUID,
  p_campanha     TEXT DEFAULT NULL,
  p_dias_gap     INTEGER DEFAULT 30
)
RETURNS TABLE (id UUID, nome TEXT, telefone TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao     = 'ativacao_contatos',
      data_ultimo_ativacao = NOW(),
      ativacao_tentativas  = ativacao_tentativas + 1,
      instancia_id         = p_instancia_id,
      updated_at           = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ja_comprou = false
      AND (
        c2.ultima_interacao IS NULL
        OR (
          c2.ultima_interacao = 'ativacao_contatos'
          AND c2.data_ultimo_ativacao < NOW() - (p_dias_gap || ' days')::INTERVAL
        )
      )
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.ativacao_tentativas < 3
    ORDER BY c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_ativacao(UUID, TEXT, INTEGER)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 10. DROP + Recria claim_proximo_lead_rmkt
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_rmkt(UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id UUID,
  p_dias_gap     INTEGER DEFAULT 30
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
      AND c2.rmkt_consecutive_silenciosos < 3
      AND (c2.data_ultimo_rmkt IS NULL OR c2.data_ultimo_rmkt < NOW() - (p_dias_gap || ' days')::INTERVAL)
      AND c2.data_cliente < NOW() - (p_dias_gap || ' days')::INTERVAL
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
-- 11. DROP + Recria claim_proximo_lead_followup
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_followup(UUID);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup(
  p_instancia_id UUID
)
RETURNS TABLE (id UUID, nome TEXT, telefone TEXT, tentativa INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao      = 'follow_up',
      data_ultimo_follow_up = NOW(),
      follow_up_tentativas  = follow_up_tentativas + 1,
      instancia_id          = p_instancia_id,
      updated_at            = NOW()
  WHERE c.id = (
    SELECT c2.id
    FROM public.contatos c2
    WHERE c2.ja_comprou = false
      AND c2.ultima_interacao = 'wait_follow_up'
      AND c2.telefone IS NOT NULL
      AND c2.follow_up_tentativas < 3
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.data_wait_follow_up < NOW() - CASE c2.follow_up_tentativas
            WHEN 0 THEN INTERVAL '24 hours'
            WHEN 1 THEN INTERVAL '3 days'
            WHEN 2 THEN INTERVAL '7 days'
            ELSE INTERVAL '100 years'
          END
    ORDER BY c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone, c.follow_up_tentativas;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(UUID)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

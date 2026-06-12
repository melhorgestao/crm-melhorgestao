-- ============================================================================
-- RPCs claim_proximo_lead_ativacao / claim_proximo_lead_rmkt agora lêem
-- as regras de elegibilidade direto da tabela campanhas.
-- Mantém os parâmetros como fallback (compat com chamadas antigas).
--
-- Workflows não precisam mudar — basta editar valores em /campanhas e o claim
-- já respeita imediatamente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) claim_proximo_lead_ativacao — usa dias_sem_envio + max_tentativas_categoria
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_ativacao(uuid, text, integer);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_ativacao(
  p_instancia_id uuid,
  p_campanha     text DEFAULT NULL,
  p_dias_gap     integer DEFAULT 30   -- usado SE campanha não tiver dias_sem_envio
) RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_dias_gap  integer;
  v_max_tent  integer;
BEGIN
  -- Lê regras da campanha ativacao ativa (mais antiga = primária)
  SELECT
    COALESCE(c.dias_sem_envio, p_dias_gap, 30),
    COALESCE(c.max_tentativas_categoria, 3)
  INTO v_dias_gap, v_max_tent
  FROM public.campanhas c
  WHERE c.tipo = 'ativacao'
    AND c.ativa = true
    AND c.pausa_global = false
  ORDER BY c.created_at ASC
  LIMIT 1;

  v_dias_gap := COALESCE(v_dias_gap, p_dias_gap, 30);
  v_max_tent := COALESCE(v_max_tent, 3);

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
          AND c2.data_ultimo_ativacao < NOW() - (v_dias_gap || ' days')::INTERVAL
        )
      )
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.ativacao_tentativas < v_max_tent
    ORDER BY c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_ativacao(uuid, text, integer)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 2) claim_proximo_lead_rmkt — usa dias_inativo_min + dias_sem_envio
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.claim_proximo_lead_rmkt(uuid, integer);

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id uuid,
  p_dias_gap     integer DEFAULT 30   -- fallback se campanha não tiver
) RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_dias_inativo integer;
  v_dias_gap     integer;
BEGIN
  SELECT
    COALESCE(c.dias_inativo_min, p_dias_gap, 30),
    COALESCE(c.dias_sem_envio,   p_dias_gap, 30)
  INTO v_dias_inativo, v_dias_gap
  FROM public.campanhas c
  WHERE c.tipo = 'rmkt'
    AND c.ativa = true
    AND c.pausa_global = false
  ORDER BY c.created_at ASC
  LIMIT 1;

  v_dias_inativo := COALESCE(v_dias_inativo, p_dias_gap, 30);
  v_dias_gap     := COALESCE(v_dias_gap,     p_dias_gap, 30);

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
      AND (c2.data_ultimo_rmkt IS NULL OR c2.data_ultimo_rmkt < NOW() - (v_dias_gap || ' days')::INTERVAL)
      AND c2.data_cliente < NOW() - (v_dias_inativo || ' days')::INTERVAL
    ORDER BY c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(uuid, integer)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

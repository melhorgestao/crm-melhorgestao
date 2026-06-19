-- ============================================================================
-- Cupons configuráveis por estado do cliente + canal.
-- Agent-start menciona se houver cupom válido pra gancho de venda.
-- Agent-closing aplica automaticamente no resumo do pedido.
-- ============================================================================

-- 1) Captura estado anterior ao em_fechamento (pra cupom funcionar mesmo quando
--    contato já mudou de ultima_interacao pra 'em_fechamento').
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS estado_antes_fechamento TEXT;

COMMENT ON COLUMN public.contatos.estado_antes_fechamento IS
  'Snapshot do ultima_interacao no momento que entrou em em_fechamento. Usado pra cupons (ex: ativacao→cupom). Limpa quando sai do fechamento.';

-- 2) Tabela cupons
CREATE TABLE IF NOT EXISTS public.cupons (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome            text NOT NULL,
  desconto_pct    numeric NOT NULL CHECK (desconto_pct > 0 AND desconto_pct <= 100),
  -- '*' = qualquer | 'cliente' (cliente+cliente_pendente) | 'ativacao_contatos'
  -- 'rmkt' | 'followup' (follow_up+wait_follow_up) | 'novo' (sem ultima_interacao)
  estados_cliente text[] NOT NULL DEFAULT ARRAY['*']::text[],
  -- '*' | 'BASE' | 'ADS' | 'REP' (não inclui C-REP)
  canais_cliente  text[] NOT NULL DEFAULT ARRAY['*']::text[],
  expira_em       timestamptz,  -- NULL = sem expiração
  ativo           boolean NOT NULL DEFAULT true,
  observacao      text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cupons_ativos
  ON public.cupons (ativo, expira_em) WHERE ativo = true;

ALTER TABLE public.cupons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cupons_admin_all ON public.cupons;
CREATE POLICY cupons_admin_all ON public.cupons
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.cupons_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_cupons_updated_at ON public.cupons;
CREATE TRIGGER trg_cupons_updated_at
  BEFORE UPDATE ON public.cupons
  FOR EACH ROW EXECUTE FUNCTION public.cupons_set_updated_at();

-- 3) Helper: mapeia ultima_interacao do contato pro grupo do cupom
CREATE OR REPLACE FUNCTION public.estado_para_grupo_cupom(p_estado text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_estado IN ('cliente', 'cliente_pendente')            THEN 'cliente'
    WHEN p_estado IN ('ativacao_contatos')                       THEN 'ativacao_contatos'
    WHEN p_estado IN ('rmkt')                                    THEN 'rmkt'
    WHEN p_estado IN ('follow_up', 'wait_follow_up')             THEN 'followup'
    WHEN p_estado IS NULL OR p_estado IN ('start','novo','NULL') THEN 'novo'
    ELSE p_estado
  END
$$;

-- 4) RPC principal: retorna o MELHOR cupom (maior desconto) pro contato.
--    Considera estado_antes_fechamento se contato está em em_fechamento.
--    NUNCA aplica desconto pra canal C-REP.
CREATE OR REPLACE FUNCTION public.cupom_para_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_canal     text;
  v_estado    text;
  v_grupo     text;
  v_cupom     record;
BEGIN
  SELECT canal_atual,
         COALESCE(estado_antes_fechamento, ultima_interacao)
    INTO v_canal, v_estado
    FROM public.contatos WHERE id = p_contato_id;

  IF v_canal = 'C-REP' THEN
    RETURN NULL;  -- regra de negócio
  END IF;

  v_grupo := public.estado_para_grupo_cupom(v_estado);
  v_canal := COALESCE(v_canal, 'BASE');

  SELECT c.* INTO v_cupom
    FROM public.cupons c
   WHERE c.ativo = true
     AND (c.expira_em IS NULL OR c.expira_em > now())
     AND (
       '*' = ANY(c.estados_cliente)
       OR v_grupo = ANY(c.estados_cliente)
     )
     AND (
       '*' = ANY(c.canais_cliente)
       OR v_canal = ANY(c.canais_cliente)
     )
   ORDER BY c.desconto_pct DESC, c.created_at ASC
   LIMIT 1;

  IF v_cupom.id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'id',           v_cupom.id,
    'nome',         v_cupom.nome,
    'desconto_pct', v_cupom.desconto_pct,
    'expira_em',    v_cupom.expira_em,
    'estado_match', v_grupo,
    'canal_match',  v_canal
  );
END $$;

GRANT EXECUTE ON FUNCTION public.estado_para_grupo_cupom(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cupom_para_contato(uuid)      TO anon, authenticated, service_role;

-- 5) Trigger no iniciar_fechamento: salva estado anterior antes de virar em_fechamento.
--    Olha pelo trigger AFTER UPDATE em contatos.
CREATE OR REPLACE FUNCTION public.trigger_snapshot_estado_antes_fechamento()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  -- Entrou em em_fechamento agora?
  IF NEW.ultima_interacao = 'em_fechamento'
     AND OLD.ultima_interacao IS DISTINCT FROM 'em_fechamento'
     AND NEW.estado_antes_fechamento IS NULL THEN
    NEW.estado_antes_fechamento := OLD.ultima_interacao;
  END IF;

  -- Saiu do em_fechamento → limpa
  IF NEW.ultima_interacao IS DISTINCT FROM 'em_fechamento'
     AND OLD.ultima_interacao = 'em_fechamento'
     AND NEW.ultima_interacao NOT IN ('aguardando_pagamento') THEN
    NEW.estado_antes_fechamento := NULL;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_snapshot_estado_antes_fechamento ON public.contatos;
CREATE TRIGGER trg_snapshot_estado_antes_fechamento
  BEFORE UPDATE ON public.contatos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_snapshot_estado_antes_fechamento();

NOTIFY pgrst, 'reload schema';

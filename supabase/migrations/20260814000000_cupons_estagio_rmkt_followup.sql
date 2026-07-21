-- ============================================================================
-- Cupons por ESTÁGIO de RMKT / Follow-up.
--
-- Objetivo (regra do dono): dar desconto mais agressivo nos últimos estágios
-- pra converter antes de perder o lead. Ex.: cupom de 40% só no Follow-up 3.
-- O agent-closing só toca no assunto do desconto se o lead estiver no estágio
-- configurado.
--
-- MODELO:
--   cupons.rmkt_estagios      int[]  -- {} = qualquer estágio (compat)
--   cupons.followup_estagios  int[]  -- {} = qualquer estágio (compat)
--
-- ESTÁGIO do contato:
--   RMKT      → contatos.rmkt_consecutive_silenciosos (nº de disparos sem resposta)
--   Follow-up → contatos.follow_up_tentativas
--
-- Cupons existentes ficam com {} e seguem valendo pra todos os estágios.
-- ============================================================================

ALTER TABLE public.cupons
  ADD COLUMN IF NOT EXISTS rmkt_estagios     integer[] NOT NULL DEFAULT '{}'::integer[],
  ADD COLUMN IF NOT EXISTS followup_estagios integer[] NOT NULL DEFAULT '{}'::integer[];

COMMENT ON COLUMN public.cupons.rmkt_estagios IS
  'Estágios de RMKT em que o cupom vale (1,2,3). Vazio = qualquer estágio. Compara com contatos.rmkt_consecutive_silenciosos.';
COMMENT ON COLUMN public.cupons.followup_estagios IS
  'Estágios de follow-up em que o cupom vale (1,2,3). Vazio = qualquer estágio. Compara com contatos.follow_up_tentativas.';

-- ----------------------------------------------------------------------------
-- RPC: agora filtra também pelo ESTÁGIO quando o grupo é rmkt/followup.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cupom_para_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_canal        text;
  v_estado       text;
  v_grupo        text;
  v_est_rmkt     integer;
  v_est_followup integer;
  v_cupom        record;
BEGIN
  SELECT canal_atual,
         COALESCE(estado_antes_fechamento, ultima_interacao),
         COALESCE(rmkt_consecutive_silenciosos, 0),
         COALESCE(follow_up_tentativas, 0)
    INTO v_canal, v_estado, v_est_rmkt, v_est_followup
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
     -- ESTÁGIO RMKT: só restringe se o cupom mira rmkt E definiu estágios
     AND (
       cardinality(c.rmkt_estagios) = 0
       OR v_grupo <> 'rmkt'
       OR v_est_rmkt = ANY(c.rmkt_estagios)
     )
     -- ESTÁGIO FOLLOW-UP: idem
     AND (
       cardinality(c.followup_estagios) = 0
       OR v_grupo <> 'followup'
       OR v_est_followup = ANY(c.followup_estagios)
     )
   ORDER BY c.desconto_pct DESC, c.created_at ASC
   LIMIT 1;

  IF v_cupom.id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'id',            v_cupom.id,
    'nome',          v_cupom.nome,
    'desconto_pct',  v_cupom.desconto_pct,
    'expira_em',     v_cupom.expira_em,
    'estado_match',  v_grupo,
    'canal_match',   v_canal,
    'estagio_rmkt',     v_est_rmkt,
    'estagio_followup', v_est_followup
  );
END $$;

GRANT EXECUTE ON FUNCTION public.cupom_para_contato(uuid) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

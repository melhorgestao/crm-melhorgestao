-- ============================================================================
-- Reestrutura campanhas:
--   1) DROP campanhas.limite_diario_total (só limite por instância importa)
--   2) DROP templates_msg.observacao (não usado em lugar nenhum)
--   3) Novo tipo de campanha 'marketing' (sazonal, sem atrapalhar rmkt/fup)
--   4) Colunas pra regras de marketing (canal, cooldown, prioridade)
--   5) Coluna marketing_cooldown_ate em contatos (interlock com rmkt/fup)
--   6) RPC claim_proximo_lead_marketing
--   7) RMKT e FUP respeitam marketing_cooldown_ate
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) DROPs
-- ----------------------------------------------------------------------------
ALTER TABLE public.campanhas    DROP COLUMN IF EXISTS limite_diario_total;
ALTER TABLE public.templates_msg DROP COLUMN IF EXISTS observacao;

-- ----------------------------------------------------------------------------
-- 2) Aceita tipo 'marketing'
-- ----------------------------------------------------------------------------
ALTER TABLE public.campanhas
  DROP CONSTRAINT IF EXISTS campanhas_tipo_check;
ALTER TABLE public.campanhas
  ADD  CONSTRAINT campanhas_tipo_check
  CHECK (tipo IN ('ativacao', 'followup', 'rmkt', 'marketing'));

-- ----------------------------------------------------------------------------
-- 3) Colunas novas em campanhas (regras de marketing)
-- ----------------------------------------------------------------------------
ALTER TABLE public.campanhas
  ADD COLUMN IF NOT EXISTS marketing_dispara_cliente        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS marketing_dispara_wait_followup  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS marketing_cooldown_dias          integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS marketing_prioridade             text    NOT NULL DEFAULT 'sem_prioridade'
    CHECK (marketing_prioridade IN ('sem_prioridade', 'clientes'));

COMMENT ON COLUMN public.campanhas.marketing_cooldown_dias IS
  'Dias de bloqueio em RMKT/FUP após o contato receber este marketing.';

-- ----------------------------------------------------------------------------
-- 4) Colunas novas em contatos (marketing tracking + cooldown)
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS marketing_campanha       text,
  ADD COLUMN IF NOT EXISTS data_ultimo_marketing    timestamptz,
  ADD COLUMN IF NOT EXISTS marketing_cooldown_ate   timestamptz;

COMMENT ON COLUMN public.contatos.marketing_cooldown_ate IS
  'Até essa data, contato fica BLOQUEADO em rmkt/followup. Calculado no momento do envio: NOW() + campanhas.marketing_cooldown_dias.';

CREATE INDEX IF NOT EXISTS idx_contatos_marketing_cooldown
  ON public.contatos (marketing_cooldown_ate) WHERE marketing_cooldown_ate IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 5) pode_disparar_campanha aceita 'marketing' + sem limite_diario_total
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pode_disparar_campanha(p_tipo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campanha             record;
  v_now_time             time;
  v_minutes_since_last   numeric;
BEGIN
  v_now_time := (NOW() AT TIME ZONE 'America/Sao_Paulo')::time;

  SELECT c.* INTO v_campanha
    FROM public.campanhas c
   WHERE c.tipo = p_tipo
     AND c.ativa = true
     AND c.pausa_global = false
   ORDER BY c.created_at ASC
   LIMIT 1;

  IF v_campanha.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem campanha ativa');
  END IF;

  -- HORÁRIO PERMITIDO
  IF v_campanha.horario_inicio IS NOT NULL AND v_campanha.horario_fim IS NOT NULL THEN
    IF v_campanha.horario_inicio <= v_campanha.horario_fim THEN
      IF v_now_time < v_campanha.horario_inicio OR v_now_time > v_campanha.horario_fim THEN
        RETURN jsonb_build_object('ok', false, 'motivo', 'fora_horario', 'campanha_id', v_campanha.id);
      END IF;
    ELSE
      IF v_now_time < v_campanha.horario_inicio AND v_now_time > v_campanha.horario_fim THEN
        RETURN jsonb_build_object('ok', false, 'motivo', 'fora_horario_overnight', 'campanha_id', v_campanha.id);
      END IF;
    END IF;
  END IF;

  -- INTERVALO MÍNIMO
  IF v_campanha.ultima_execucao_em IS NOT NULL THEN
    v_minutes_since_last := EXTRACT(EPOCH FROM (NOW() - v_campanha.ultima_execucao_em)) / 60.0;
    IF v_minutes_since_last < v_campanha.intervalo_minutos THEN
      RETURN jsonb_build_object('ok', false,
        'motivo', 'intervalo (' || round(v_minutes_since_last, 1) || '/' || v_campanha.intervalo_minutos || 'min)',
        'campanha_id', v_campanha.id);
    END IF;
  END IF;

  -- COFFEE BREAK
  IF v_campanha.coffee_break_inicio IS NOT NULL AND v_campanha.coffee_break_fim IS NOT NULL
     AND v_now_time >= v_campanha.coffee_break_inicio AND v_now_time <= v_campanha.coffee_break_fim THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'coffee break', 'campanha_id', v_campanha.id);
  END IF;

  -- SKIP ALEATÓRIO
  IF v_campanha.skip_rate > 0 AND random() < v_campanha.skip_rate THEN
    RETURN jsonb_build_object('ok', false,
      'motivo', 'skip aleatório (' || (v_campanha.skip_rate * 100)::int || '%)',
      'campanha_id', v_campanha.id);
  END IF;

  UPDATE public.campanhas SET ultima_execucao_em = NOW() WHERE id = v_campanha.id;
  RETURN jsonb_build_object('ok', true, 'campanha_id', v_campanha.id);
END $$;

GRANT EXECUTE ON FUNCTION public.pode_disparar_campanha(text)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6) escolhe_template_v2 — aceita 'marketing' + remove limite_diario_total
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.escolhe_template_v2(
  p_categoria    text,
  p_subcategoria text,
  p_contato_id   uuid,
  p_instancia_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_pausa_global boolean;
  v_campanha     record;
  v_now_time     time;
  v_now_date     date;
  v_count        int;
  v_limite_inst  int;
  v_template     record;
  v_anexo        record;
  v_texto        text;
  v_contato      record;
  v_var          record;
BEGIN
  v_now_time := (NOW() AT TIME ZONE 'America/Sao_Paulo')::time;
  v_now_date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;

  SELECT (valor = 'true') INTO v_pausa_global FROM public.configuracoes WHERE chave = 'campanhas_pausa_global';
  IF COALESCE(v_pausa_global, false) THEN RETURN NULL; END IF;

  SELECT c.* INTO v_campanha
    FROM public.campanhas c
   WHERE c.tipo = p_categoria
     AND c.ativa = true
     AND c.pausa_global = false
     AND EXISTS (
       SELECT 1 FROM public.templates_msg t
        WHERE t.campanha_id = c.id AND t.ativo = true
          AND (t.subcategoria IS NOT DISTINCT FROM p_subcategoria)
     )
   ORDER BY c.created_at ASC LIMIT 1;
  IF v_campanha.id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (
    SELECT 1 FROM public.campanha_instancia
     WHERE campanha_id = v_campanha.id AND instancia_id = p_instancia_id AND ativa = false
  ) THEN RETURN NULL; END IF;

  IF v_now_time < v_campanha.horario_inicio OR v_now_time > v_campanha.horario_fim THEN
    RETURN NULL;
  END IF;

  IF v_campanha.cooldown_dias > 0 THEN
    IF EXISTS (
      SELECT 1 FROM public.campanha_envios
       WHERE contato_id = p_contato_id
         AND enviado_em > NOW() - (v_campanha.cooldown_dias || ' days')::interval
    ) THEN RETURN NULL; END IF;
  END IF;

  -- (limite global removido — só limite por instância importa)

  SELECT limite_diario_instancia INTO v_limite_inst FROM public.campanha_instancia
   WHERE campanha_id = v_campanha.id AND instancia_id = p_instancia_id;
  IF v_limite_inst IS NOT NULL THEN
    SELECT count(*) INTO v_count FROM public.campanha_envios
     WHERE campanha_id = v_campanha.id AND instancia_id = p_instancia_id AND enviado_em >= v_now_date;
    IF v_count >= v_limite_inst THEN RETURN NULL; END IF;
  END IF;

  -- TEMPLATE (rotação por hash contato)
  SELECT t.* INTO v_template
    FROM (
      SELECT tm.*, count(*) OVER () AS total,
             (row_number() OVER (ORDER BY ordem, id) - 1) AS idx
        FROM public.templates_msg tm
       WHERE tm.campanha_id = v_campanha.id
         AND (tm.subcategoria IS NOT DISTINCT FROM p_subcategoria)
         AND tm.ativo = true
    ) t
   WHERE idx = abs(hashtext(p_contato_id::text)) % t.total;
  IF v_template.id IS NULL THEN RETURN NULL; END IF;

  SELECT a.* INTO v_anexo
    FROM (
      SELECT ca.*, count(*) OVER () AS total,
             (row_number() OVER (ORDER BY ordem, id) - 1) AS idx
        FROM public.campanha_anexos ca
       WHERE ca.campanha_id = v_campanha.id AND ca.ativo = true
    ) a
   WHERE idx = abs(hashtext(p_contato_id::text || v_campanha.id::text)) % a.total;

  v_texto := v_template.texto;
  SELECT split_part(c.nome,' ',1) AS pri_nome, c.cidade, split_part(r.nome,' ',1) AS rep_nome
    INTO v_contato FROM public.contatos c
    LEFT JOIN public.contatos r ON r.id = c.representante_id
   WHERE c.id = p_contato_id;

  v_texto := REPLACE(v_texto, '{{nome}}',     COALESCE(v_contato.pri_nome,  'amigo(a)'));
  v_texto := REPLACE(v_texto, '{{cidade}}',   COALESCE(v_contato.cidade,    ''));
  v_texto := REPLACE(v_texto, '{{rep_nome}}', COALESCE(v_contato.rep_nome,  ''));

  FOR v_var IN SELECT chave, valor FROM public.variaveis_globais LOOP
    v_texto := REPLACE(v_texto, '{{' || v_var.chave || '}}', COALESCE(v_var.valor, ''));
  END LOOP;

  RETURN jsonb_build_object(
    'texto',       v_texto,
    'template_id', v_template.id,
    'campanha_id', v_campanha.id,
    'campanha_nome', v_campanha.nome,
    'anexo_url',   v_anexo.url,
    'anexo_tipo',  v_anexo.tipo,
    'anexo_id',    v_anexo.id
  );
END $$;

GRANT EXECUTE ON FUNCTION public.escolhe_template_v2(text, text, uuid, uuid)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 7) claim_proximo_lead_marketing
--    Filtra por marketing_dispara_cliente / wait_followup da campanha.
--    Respeita marketing_cooldown_ate global (evita disparar 2x sobreposto).
--    Marca contato com nome da campanha + cooldown_ate.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_marketing(
  p_instancia_id uuid,
  p_campanha_id  uuid
)
RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_camp record;
BEGIN
  SELECT * INTO v_camp FROM public.campanhas
   WHERE id = p_campanha_id AND tipo = 'marketing' AND ativa = true AND pausa_global = false;
  IF v_camp.id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  UPDATE public.contatos c
     SET marketing_campanha      = v_camp.nome,
         data_ultimo_marketing   = NOW(),
         marketing_cooldown_ate  = NOW() + (v_camp.marketing_cooldown_dias || ' days')::interval,
         instancia_id            = COALESCE(c.instancia_id, p_instancia_id),
         updated_at              = NOW()
   WHERE c.id = (
     SELECT c2.id FROM public.contatos c2
      WHERE c2.telefone IS NOT NULL
        AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
        -- canal: pula C-REP (regra geral do negócio)
        AND COALESCE(c2.canal_atual, 'BASE') != 'C-REP'
        -- elegibilidade: cliente E/OU wait_follow_up
        AND (
          (v_camp.marketing_dispara_cliente       AND c2.ja_comprou = true AND c2.ultima_interacao = 'cliente')
          OR
          (v_camp.marketing_dispara_wait_followup AND c2.ultima_interacao = 'wait_follow_up')
        )
        -- não disparar pra quem já recebeu essa campanha recentemente
        -- (cooldown próprio da campanha em campanha_envios)
        AND NOT EXISTS (
          SELECT 1 FROM public.campanha_envios ce
           WHERE ce.contato_id = c2.id AND ce.campanha_id = v_camp.id
             AND ce.enviado_em > NOW() - GREATEST(v_camp.cooldown_dias, 1) * INTERVAL '1 day'
        )
      ORDER BY
        -- prioridade: clientes primeiro se configurado
        CASE WHEN v_camp.marketing_prioridade = 'clientes'
             AND c2.ja_comprou = true THEN 0 ELSE 1 END,
        c2.created_at ASC
      LIMIT 1
      FOR UPDATE SKIP LOCKED
   )
   RETURNING c.id, c.nome, c.telefone;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_marketing(uuid, uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 8) RMKT respeita marketing_cooldown_ate
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id uuid,
  p_dias_gap integer DEFAULT 30
)
RETURNS TABLE (id uuid, nome text, telefone text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_dias_inativo integer;
  v_dias_gap     integer;
BEGIN
  SELECT c.dias_inativo_min, c.intervalo_minutos
    INTO v_dias_inativo, v_dias_gap
  FROM public.campanhas c
  WHERE c.tipo = 'rmkt' AND c.ativa = true AND c.pausa_global = false
  ORDER BY c.created_at ASC LIMIT 1;

  v_dias_inativo := COALESCE(v_dias_inativo, p_dias_gap, 30);
  v_dias_gap     := COALESCE(v_dias_gap,     p_dias_gap, 30);

  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao = 'rmkt',
      data_ultimo_rmkt = NOW(),
      instancia_id     = p_instancia_id,
      updated_at       = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ja_comprou = true
      AND c2.ultima_interacao = 'cliente'
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.rmkt_consecutive_silenciosos < 3
      AND (c2.data_ultimo_rmkt IS NULL OR c2.data_ultimo_rmkt < NOW() - (v_dias_gap || ' days')::INTERVAL)
      AND c2.primeira_venda_em < NOW() - (v_dias_inativo || ' days')::INTERVAL
      -- INTERLOCK com marketing: se cooldown ativo, pula
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
    ORDER BY c2.created_at ASC LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(uuid, integer)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 9) FollowUp claim respeita marketing_cooldown_ate
--    Se a função existir; senão criamos versão básica.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup(p_instancia_id uuid)
RETURNS TABLE (id uuid, nome text, telefone text, subcategoria text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao = 'follow_up',
      data_ultimo_follow_up = NOW(),
      follow_up_tentativas = follow_up_tentativas + 1,
      instancia_id = p_instancia_id,
      updated_at = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ultima_interacao = 'wait_follow_up'
      AND c2.ja_comprou = false
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.follow_up_tentativas < 3
      -- INTERLOCK com marketing
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
      AND (c2.data_wait_follow_up < NOW() - INTERVAL '24 hours' OR c2.data_wait_follow_up IS NULL)
    ORDER BY c2.data_wait_follow_up ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone,
            CASE c.follow_up_tentativas WHEN 1 THEN '24h' WHEN 2 THEN '3d' ELSE '7d' END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 10) Cria campanha Marketing default (uma só, pode customizar nome via UI)
-- ----------------------------------------------------------------------------
INSERT INTO public.campanhas (nome, tipo, ativa, pausa_global, horario_inicio, horario_fim,
  cooldown_dias, intervalo_minutos, skip_rate,
  marketing_dispara_cliente, marketing_dispara_wait_followup,
  marketing_cooldown_dias, marketing_prioridade)
SELECT 'Marketing Sazonal', 'marketing', false, false, '09:00', '20:00',
       30, 30, 0.0,
       true, false, 3, 'sem_prioridade'
 WHERE NOT EXISTS (SELECT 1 FROM public.campanhas WHERE tipo = 'marketing');

NOTIFY pgrst, 'reload schema';

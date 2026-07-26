-- ============================================================================
-- FOLLOW-UP PERSONALIZADO (custom) — o agent agenda um retorno no prazo que o
-- CLIENTE prometeu ("mês que vem", "daqui 3 dias", "quarta eu chamo").
--
-- Fluxo:
--   1) Cliente dá um prazo → o agent chama agendar_followup_custom(texto).
--      parse_prazo_followup() vira o prazo numa data. O lead entra em
--      ultima_interacao='wait_follow_up_custom' com followup_custom_em=<data>.
--      No Kanban aparece a tag "F-UP Custom" (mesma coluna Follow-up).
--   2) Na data, o MESMO workflow de follow-up dispara (o claim abaixo devolve
--      subcategoria='custom' e o escolhe_template_v2 pega o template da
--      campanha "Follow-up Personalizado"). Zero mudança no n8n.
--   3) Se o cliente pedir MAIS prazo → o agent reagenda (nova data, volta pra
--      wait_follow_up_custom).
--   4) Se NÃO converter e NÃO pedir mais prazo, após o disparo custom o lead
--      cai na cadência normal 3d → 7d, PULANDO só o 1º de 4h
--      (confirmar_envio_lead seta follow_up_tentativas = 1).
--
-- Também: cron da state-machine passa de 1h → 15min (transição mais fina).
-- ============================================================================

-- 0) Coluna do prazo prometido -----------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS followup_custom_em timestamptz;

COMMENT ON COLUMN public.contatos.followup_custom_em IS
  'Quando disparar o follow-up PERSONALIZADO (prazo prometido pelo cliente). Vale só no estado wait_follow_up_custom.';

CREATE INDEX IF NOT EXISTS idx_contatos_followup_custom
  ON public.contatos (followup_custom_em)
  WHERE ultima_interacao = 'wait_follow_up_custom';

-- 1) Campanha "Follow-up Personalizado" + template default --------------------
DO $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.campanhas
   WHERE tipo = 'followup' AND nome = 'Follow-up Personalizado' LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO public.campanhas (nome, tipo, ativa)
    VALUES ('Follow-up Personalizado', 'followup', false)   -- ligar quando quiser
    RETURNING id INTO v_id;
  END IF;

  -- template default (subcategoria 'custom') se ainda não houver nenhum
  IF NOT EXISTS (
    SELECT 1 FROM public.templates_msg
     WHERE campanha_id = v_id AND subcategoria = 'custom'
  ) THEN
    INSERT INTO public.templates_msg (campanha_id, categoria, subcategoria, ordem, texto, ativo)
    VALUES (
      v_id, 'followup', 'custom', 1,
      'Oi {{nome}}! 😊 Passando pra retomar como a gente combinou. Quando você quiser seguir com seu pedido é só me chamar que eu já preparo tudo. Tô por aqui!',
      true
    );
  END IF;
END $$;

-- 2) parse_prazo_followup: prazo em texto → timestamp de disparo -------------
--    Determinístico (o parsing NÃO fica no LLM). Cobre os casos do dono:
--    "mês que vem" -> dia 1 do próximo mês; "daqui 3 dias" -> +3d;
--    "quarta" -> próxima quarta do calendário. Disparo às 10:00 (dentro da
--    janela comercial). Devolve NULL se não entender.
CREATE OR REPLACE FUNCTION public.parse_prazo_followup(
  p_texto text,
  p_base  timestamptz DEFAULT now()
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  t         text;
  n         int;
  base_date date;
  target    date;
  dow       int;
  cur_dow   int;
  add_days  int;
  m         text[];
BEGIN
  IF p_texto IS NULL OR btrim(p_texto) = '' THEN RETURN NULL; END IF;

  -- normaliza: minúsculo + remove acentos comuns
  t := lower(p_texto);
  t := translate(t, 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc');
  base_date := (p_base AT TIME ZONE 'America/Sao_Paulo')::date;

  -- depois de amanhã / amanhã
  IF t ~ 'depois de amanha' THEN
    RETURN ((base_date + 2) + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
  END IF;
  IF t ~ 'amanha' THEN
    RETURN ((base_date + 1) + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
  END IF;

  -- mês que vem / próximo mês → dia 1 do próximo mês
  IF t ~ '(mes que vem|proximo mes|mes proximo|mes seguinte|outro mes|mes q vem)' THEN
    target := (date_trunc('month', base_date::timestamp) + interval '1 month')::date;
    RETURN (target + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
  END IF;

  -- semana que vem / próxima semana → +7
  IF t ~ '(semana que vem|proxima semana|semana proxima|outra semana|semana q vem)' THEN
    RETURN ((base_date + 7) + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
  END IF;

  -- N semanas
  m := regexp_match(t, '(\d+)\s*semanas?');
  IF m IS NOT NULL THEN
    n := m[1]::int;
    IF n BETWEEN 1 AND 12 THEN
      RETURN ((base_date + (n*7)) + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
    END IF;
  END IF;

  -- N dias (daqui a N dias, em N dias, N dias)
  m := regexp_match(t, '(\d+)\s*dias?');
  IF m IS NOT NULL THEN
    n := m[1]::int;
    IF n BETWEEN 1 AND 120 THEN
      RETURN ((base_date + n) + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
    END IF;
  END IF;

  -- dia da semana (próxima ocorrência no calendário; se for hoje, a que vem)
  dow := CASE
    WHEN t ~ 'segunda'          THEN 1
    WHEN t ~ '(terca|terça)'    THEN 2
    WHEN t ~ 'quarta'           THEN 3
    WHEN t ~ 'quinta'           THEN 4
    WHEN t ~ 'sexta'            THEN 5
    WHEN t ~ 'sabado'           THEN 6
    WHEN t ~ 'domingo'          THEN 0
    ELSE -1 END;
  IF dow >= 0 THEN
    cur_dow  := EXTRACT(dow FROM base_date)::int;   -- 0=dom .. 6=sab
    add_days := ((dow - cur_dow) + 7) % 7;
    IF add_days = 0 THEN add_days := 7; END IF;      -- "quarta" hoje = próxima quarta
    RETURN ((base_date + add_days) + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
  END IF;

  -- "dia N" explícito (dia 15) → mês atual se futuro, senão próximo mês
  m := regexp_match(t, 'dia\s+(\d{1,2})');
  IF m IS NOT NULL THEN
    n := LEAST(m[1]::int, 28);
    IF n BETWEEN 1 AND 28 THEN
      target := make_date(EXTRACT(year FROM base_date)::int, EXTRACT(month FROM base_date)::int, n);
      IF target <= base_date THEN
        target := (date_trunc('month', base_date::timestamp) + interval '1 month')::date + (n - 1);
      END IF;
      RETURN (target + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
    END IF;
  END IF;

  RETURN NULL;   -- não deu pra entender o prazo
END $$;

GRANT EXECUTE ON FUNCTION public.parse_prazo_followup(text, timestamptz)
  TO authenticated, anon, service_role;

-- 3) agendar_followup_custom: chamado pela tool do agent ---------------------
CREATE OR REPLACE FUNCTION public.agendar_followup_custom(
  p_contato_id uuid,
  p_texto      text        DEFAULT NULL,
  p_data       timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data     timestamptz;
  v_entendeu boolean := true;
BEGIN
  v_data := COALESCE(p_data, public.parse_prazo_followup(p_texto, now()));

  -- não entendeu o prazo → fallback conservador de +3 dias (não trava o fluxo)
  IF v_data IS NULL THEN
    v_data := now() + interval '3 days';
    v_entendeu := false;
  END IF;

  -- guarda-corpos: nunca no passado, nunca além de 90 dias
  IF v_data < now() + interval '1 hour' THEN v_data := now() + interval '1 day'; END IF;
  IF v_data > now() + interval '90 days' THEN v_data := now() + interval '90 days'; END IF;

  UPDATE public.contatos
     SET ultima_interacao       = 'wait_follow_up_custom',
         followup_custom_em      = v_data,
         follow_up_reservado_ate = NULL,   -- solta qualquer reserva pendente
         data_em_fechamento      = NULL,   -- sai do fechamento (prometeu voltar)
         bot_pausado_ate         = NULL,   -- volta a ser atendível
         updated_at              = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, metadata)
    VALUES (p_contato_id, 'followup_custom_agendado',
            jsonb_build_object('texto', p_texto, 'agendado_para', v_data, 'entendeu', v_entendeu));
  EXCEPTION WHEN OTHERS THEN /* log é best-effort */ NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'agendado_para', v_data, 'entendeu_prazo', v_entendeu);
END $$;

GRANT EXECUTE ON FUNCTION public.agendar_followup_custom(uuid, text, timestamptz)
  TO authenticated, anon, service_role;

-- 4) claim follow-up _raw: agora também claim'a o custom vencido -------------
--    (a 20260825 embrulha este _raw com a trava de modo mudo; continua valendo)
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup_raw(p_instancia_id uuid)
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
    WHERE c2.ja_comprou = false
      AND c2.telefone IS NOT NULL
      AND COALESCE(c2.ativacao_tentativas, 0) = 0
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
      AND (c2.follow_up_reservado_ate IS NULL OR c2.follow_up_reservado_ate < NOW())
      AND (
        -- CUSTOM: prazo prometido pelo cliente venceu
        (c2.ultima_interacao = 'wait_follow_up_custom'
         AND c2.followup_custom_em IS NOT NULL
         AND c2.followup_custom_em <= NOW())
        OR
        -- NORMAL: cadência 4h (silêncio real) / 3d / 7d
        (c2.ultima_interacao = 'wait_follow_up'
         AND c2.follow_up_tentativas < 3
         AND CASE
               WHEN COALESCE(c2.follow_up_tentativas, 0) = 0 THEN
                 COALESCE(c2.data_ultima_entrada, NOW() - INTERVAL '999 days') < NOW() - INTERVAL '4 hours'
               ELSE
                 COALESCE(c2.data_ultimo_follow_up, c2.data_wait_follow_up, NOW() - INTERVAL '999 days') <
                   NOW() - CASE COALESCE(c2.follow_up_tentativas, 0) + 1
                             WHEN 2 THEN INTERVAL '3 days'
                             ELSE     INTERVAL '7 days'
                           END
             END)
      )
    ORDER BY
      -- custom vencido tem prioridade (é promessa explícita do cliente)
      CASE WHEN c2.ultima_interacao = 'wait_follow_up_custom' THEN 0 ELSE 1 END,
      COALESCE(c2.followup_custom_em, c2.data_ultimo_follow_up,
               c2.data_ultima_entrada, c2.data_wait_follow_up) ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone,
            CASE
              WHEN c.ultima_interacao = 'wait_follow_up_custom' THEN 'custom'
              ELSE CASE (c.follow_up_tentativas + 1) WHEN 1 THEN '4h' WHEN 2 THEN '3d' ELSE '7d' END
            END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup_raw(uuid)
  TO authenticated, anon, service_role;

-- 5) confirmar_envio_lead: trata o disparo CUSTOM antes do followup normal ----
CREATE OR REPLACE FUNCTION public.confirmar_envio_lead(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hit boolean;
BEGIN
  -- CUSTOM: acabou de disparar o follow-up personalizado. Cai na cadência
  -- normal PULANDO o 1º de 4h (follow_up_tentativas = 1 → próximo é 3d, depois
  -- 7d). Limpa o prazo prometido.
  UPDATE public.contatos
     SET ultima_interacao        = 'follow_up',
         follow_up_tentativas     = GREATEST(COALESCE(follow_up_tentativas, 0), 1),
         data_ultimo_follow_up    = NOW(),
         followup_custom_em       = NULL,
         follow_up_reservado_ate  = NULL,
         updated_at               = NOW()
   WHERE id = p_contato_id
     AND ultima_interacao = 'wait_follow_up_custom'
     AND follow_up_reservado_ate IS NOT NULL;
  GET DIAGNOSTICS v_hit = ROW_COUNT;
  IF v_hit THEN RETURN jsonb_build_object('ok', true, 'tipo', 'followup_custom'); END IF;

  -- followup normal
  UPDATE public.contatos
     SET ultima_interacao        = 'follow_up',
         follow_up_tentativas     = follow_up_tentativas + 1,
         data_ultimo_follow_up    = NOW(),
         follow_up_reservado_ate  = NULL,
         updated_at               = NOW()
   WHERE id = p_contato_id
     AND follow_up_reservado_ate IS NOT NULL;
  GET DIAGNOSTICS v_hit = ROW_COUNT;
  IF v_hit THEN RETURN jsonb_build_object('ok', true, 'tipo', 'followup'); END IF;

  -- rmkt
  UPDATE public.contatos
     SET ultima_interacao             = 'rmkt',
         data_ultimo_rmkt             = NOW(),
         rmkt_consecutive_silenciosos = COALESCE(rmkt_consecutive_silenciosos, 0) + 1,
         rmkt_reservado_ate           = NULL,
         updated_at                   = NOW()
   WHERE id = p_contato_id
     AND rmkt_reservado_ate IS NOT NULL;
  GET DIAGNOSTICS v_hit = ROW_COUNT;
  IF v_hit THEN RETURN jsonb_build_object('ok', true, 'tipo', 'rmkt'); END IF;

  RETURN jsonb_build_object('ok', true, 'tipo', 'none');
END $$;

GRANT EXECUTE ON FUNCTION public.confirmar_envio_lead(uuid)
  TO authenticated, anon, service_role;

-- 6) reverter_claim_lead: também solta a reserva de um custom (sem perder o prazo)
--    (se a função existir, garante que custom volte a ser claim'ável)
--    — o corpo padrão só zera follow_up_reservado_ate, o que já serve.

-- 7) state-machine: safety net p/ custom "zumbi" + cron 15min ----------------
--    Se um custom venceu há > 7 dias e nunca disparou (campanha custom off, sem
--    template), cai na cadência normal pra não ficar preso invisível.
CREATE OR REPLACE FUNCTION public.limpar_followup_custom_zumbi()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.contatos c
     SET ultima_interacao    = 'wait_follow_up',
         follow_up_tentativas = GREATEST(COALESCE(follow_up_tentativas, 0), 1),
         data_wait_follow_up  = NOW(),
         followup_custom_em   = NULL,
         updated_at           = NOW()
   WHERE c.ultima_interacao = 'wait_follow_up_custom'
     AND c.followup_custom_em IS NOT NULL
     AND c.followup_custom_em < NOW() - INTERVAL '7 days'
     AND EXISTS (SELECT 1 FROM public.instancias i
                  WHERE i.id = c.instancia_id AND i.status = 'ativo' AND i.ativo = true);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

GRANT EXECUTE ON FUNCTION public.limpar_followup_custom_zumbi()
  TO authenticated, anon, service_role;

-- tick único do cron (transições + limpeza custom) — evita 2 statements no schedule
CREATE OR REPLACE FUNCTION public.cron_state_machine_tick()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.processar_transicoes_estado_contato();
  PERFORM public.limpar_followup_custom_zumbi();
END $$;

GRANT EXECUTE ON FUNCTION public.cron_state_machine_tick()
  TO authenticated, anon, service_role;

-- cron: state-machine a cada 15min (antes era 1h)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'state-machine-transicoes') THEN
    PERFORM cron.unschedule('state-machine-transicoes');
  END IF;
  PERFORM cron.schedule(
    'state-machine-transicoes',
    '*/15 * * * *',
    $cmd$ SELECT public.cron_state_machine_tick() $cmd$
  );
END $$;

NOTIFY pgrst, 'reload schema';

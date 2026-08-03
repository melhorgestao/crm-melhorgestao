-- ============================================================================
-- FECHAMENTO CUSTOM (Aguardando fechamento AGENDADO)
--
-- Novo modelo: o "aguardando fechamento" deixa de ser suporte pausado e passa
-- a ser um AGENDAMENTO dentro do próprio em_fechamento (bot ATIVO):
--   - agent-closing (ou a ampulheta no Kanban) agenda uma data de retorno.
--   - o contato fica em em_fechamento + fechamento_agendado_em (não pausa).
--   - no dia, o MESMO rail de follow-up (claim_proximo_lead_followup_raw)
--     dispara a mensagem de reengajamento (subcategoria 'fechamento', template
--     da campanha "Fechamento Custom"). Quando o lead responde, o router já
--     roteia pro closing (estado em_fechamento).
--
-- em_fechamento nunca é elegível a RMKT (exige 'cliente') nem ao follow-up
-- NORMAL (exige 'wait_follow_up'), então fica naturalmente fora dessas campanhas.
-- ============================================================================

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS fechamento_agendado_em timestamptz;

COMMENT ON COLUMN public.contatos.fechamento_agendado_em IS
  'Aguardando fechamento agendado: data em que o bot deve reengajar o lead em em_fechamento. Setado pelo agent-closing (agendar_fechamento) ou pela ampulheta no Kanban. Limpo ao disparar o reengajamento.';

-- ----------------------------------------------------------------------------
-- 1) RPC agendar_aguardando_fechamento — usada pela tool do agent-closing e
--    pela ampulheta do Kanban. Sem data específica → +24h (lead quente).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.agendar_aguardando_fechamento(
  p_contato_id uuid,
  p_texto      text        DEFAULT NULL,
  p_data       timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_data     timestamptz;
  v_entendeu boolean := true;
BEGIN
  -- data explícita (calendário) vence; senão parseia o texto; senão +24h.
  IF p_data IS NOT NULL THEN
    v_data := p_data;
  ELSIF NULLIF(TRIM(COALESCE(p_texto, '')), '') IS NOT NULL THEN
    v_data := public.parse_prazo_followup(p_texto, now());
    IF v_data IS NULL THEN
      v_data := now() + interval '24 hours';   -- lead quente: fallback curto
      v_entendeu := false;
    END IF;
  ELSE
    v_data := now() + interval '24 hours';       -- "sem data definida"
    v_entendeu := false;
  END IF;

  -- guarda-corpos: nunca no passado, nunca além de 90 dias
  IF v_data < now() + interval '1 hour' THEN v_data := now() + interval '1 day'; END IF;
  IF v_data > now() + interval '90 days' THEN v_data := now() + interval '90 days'; END IF;

  UPDATE public.contatos
     SET ultima_interacao       = 'em_fechamento',   -- bot ATIVO, coluna Fechamento
         fechamento_agendado_em  = v_data,
         data_em_fechamento      = COALESCE(data_em_fechamento, NOW()),
         fechamento_aguardando   = false,            -- aposenta o flag antigo
         estado_antes_suporte    = NULL,
         data_suporte            = NULL,
         suporte_motivo          = COALESCE(NULLIF(TRIM(COALESCE(p_texto,'')),''), suporte_motivo),
         bot_pausado_ate         = NULL,             -- NUNCA pausa (precisa reengajar)
         follow_up_reservado_ate = NULL,
         updated_at              = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, metadata)
    VALUES (p_contato_id, 'fechamento_agendado',
            jsonb_build_object('texto', p_texto, 'agendado_para', v_data, 'entendeu', v_entendeu));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'agendado_para', v_data, 'entendeu_prazo', v_entendeu);
END $$;

GRANT EXECUTE ON FUNCTION public.agendar_aguardando_fechamento(uuid, text, timestamptz)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 2) claim_proximo_lead_followup_raw — agora também captura o fechamento
--    agendado vencido (subcategoria 'fechamento'). Recria 20260828 + branch.
-- ----------------------------------------------------------------------------
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
        -- FECHAMENTO: reengajamento agendado venceu (promessa em negociação)
        (c2.ultima_interacao = 'em_fechamento'
         AND c2.fechamento_agendado_em IS NOT NULL
         AND c2.fechamento_agendado_em <= NOW())
        OR
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
      -- promessas explícitas (fechamento agendado / custom) têm prioridade
      CASE WHEN c2.ultima_interacao IN ('em_fechamento', 'wait_follow_up_custom') THEN 0 ELSE 1 END,
      COALESCE(c2.fechamento_agendado_em, c2.followup_custom_em, c2.data_ultimo_follow_up,
               c2.data_ultima_entrada, c2.data_wait_follow_up) ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone,
            CASE
              WHEN c.ultima_interacao = 'em_fechamento'        THEN 'fechamento'
              WHEN c.ultima_interacao = 'wait_follow_up_custom' THEN 'custom'
              ELSE CASE (c.follow_up_tentativas + 1) WHEN 1 THEN '4h' WHEN 2 THEN '3d' ELSE '7d' END
            END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup_raw(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 3) confirmar_envio_lead — trata o reengajamento de FECHAMENTO antes de tudo.
--    Recria 20260828 + branch. Mantém em_fechamento (bot segue no closing),
--    limpa o agendamento e reinicia a janela de 48h.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirmar_envio_lead(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hit boolean;
BEGIN
  -- FECHAMENTO: reengajou o lead agendado. Continua em em_fechamento (o bot
  -- fecha na resposta), zera o agendamento e reinicia a janela de fechamento.
  UPDATE public.contatos
     SET fechamento_agendado_em   = NULL,
         data_em_fechamento       = NOW(),
         follow_up_reservado_ate   = NULL,
         updated_at                = NOW()
   WHERE id = p_contato_id
     AND ultima_interacao = 'em_fechamento'
     AND follow_up_reservado_ate IS NOT NULL;
  GET DIAGNOSTICS v_hit = ROW_COUNT;
  IF v_hit THEN RETURN jsonb_build_object('ok', true, 'tipo', 'fechamento'); END IF;

  -- CUSTOM: acabou de disparar o follow-up personalizado.
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

-- ----------------------------------------------------------------------------
-- 4) Campanha "Fechamento Custom" + template de reengajamento
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.campanhas WHERE tipo = 'fechamento' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.campanhas (nome, tipo, ativa)
    VALUES ('Fechamento Custom', 'fechamento', false)   -- ligar quando quiser
    RETURNING id INTO v_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.templates_msg
     WHERE campanha_id = v_id AND categoria = 'fechamento' AND subcategoria = 'custom'
  ) THEN
    INSERT INTO public.templates_msg (campanha_id, categoria, subcategoria, ordem, texto, ativo)
    VALUES (
      v_id, 'fechamento', 'custom', 1,
      'Oi {{nome}}! 😊 Voltando como a gente combinou pra fechar seu pedido. Posso seguir com tudo pra você agora?',
      true
    );
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5) Migração do modelo antigo: quem está em "aguardando fechamento" pausado
--    (suporte + fechamento_aguardando) vira o novo agendado (em_fechamento +
--    fechamento_agendado_em = +24h), sem pausa.
-- ----------------------------------------------------------------------------
UPDATE public.contatos
   SET ultima_interacao       = 'em_fechamento',
       fechamento_agendado_em  = NOW() + interval '24 hours',
       data_em_fechamento      = COALESCE(data_em_fechamento, NOW()),
       fechamento_aguardando   = false,
       estado_antes_suporte    = NULL,
       data_suporte            = NULL,
       suporte_motivo          = NULL,
       bot_pausado_ate         = NULL,
       updated_at              = NOW()
 WHERE COALESCE(fechamento_aguardando, false) = true
   AND ultima_interacao = 'suporte';

NOTIFY pgrst, 'reload schema';

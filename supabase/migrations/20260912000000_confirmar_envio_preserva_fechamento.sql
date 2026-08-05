-- ============================================================================
-- FIX: após disparar o reengajamento de FECHAMENTO (subcategoria 'fechamento'),
-- o card deve CONTINUAR na coluna Fechamento (ultima_interacao='em_fechamento'),
-- apenas SEM a tag "AGENDADO" (fechamento_agendado_em = NULL).
--
-- Sintoma reportado: agente disparou o follow-up custom de fechamento e o card
-- sumiu da coluna Fechamento. Causa: o branch de follow-up NORMAL de
-- confirmar_envio_lead não tinha guarda de estado — qualquer contato com
-- follow_up_reservado_ate setado (inclui em_fechamento reservado pelo claim)
-- era convertido em 'follow_up', movendo o card pra coluna Follow-up.
--
-- Blindagem: o branch NORMAL agora só age em estados de follow-up de fato
-- ('wait_follow_up' | 'follow_up'). em_fechamento e wait_follow_up_custom têm
-- seus próprios branches ANTES dele. Idempotente (CREATE OR REPLACE).
--
-- Além disso: o follow-up CUSTOM (wait_follow_up_custom) é uma promessa de
-- retomar pra FECHAR. Ao disparar, o lead agora vai pra em_fechamento (coluna
-- Fechamento / negociação), não mais pra follow_up — o bot fecha na resposta.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.confirmar_envio_lead(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hit boolean;
BEGIN
  -- FECHAMENTO: reengajou o lead agendado. CONTINUA em em_fechamento (o bot
  -- fecha na resposta), zera o agendamento (tira a tag AGENDADO) e reinicia a
  -- janela de fechamento.
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

  -- CUSTOM: acabou de disparar o follow-up personalizado (promessa de retomar
  -- pra fechar). Vai pra em_fechamento (coluna Fechamento, negociação) — o bot
  -- fecha na resposta. SEM tag agendada. Não volta pra cadência de follow-up.
  UPDATE public.contatos
     SET ultima_interacao        = 'em_fechamento',
         data_em_fechamento       = NOW(),
         fechamento_agendado_em    = NULL,
         followup_custom_em       = NULL,
         follow_up_reservado_ate  = NULL,
         updated_at               = NOW()
   WHERE id = p_contato_id
     AND ultima_interacao = 'wait_follow_up_custom'
     AND follow_up_reservado_ate IS NOT NULL;
  GET DIAGNOSTICS v_hit = ROW_COUNT;
  IF v_hit THEN RETURN jsonb_build_object('ok', true, 'tipo', 'followup_custom'); END IF;

  -- FOLLOW-UP normal — BLINDADO: só estados de follow-up (nunca em_fechamento/rmkt).
  UPDATE public.contatos
     SET ultima_interacao        = 'follow_up',
         follow_up_tentativas     = follow_up_tentativas + 1,
         data_ultimo_follow_up    = NOW(),
         follow_up_reservado_ate  = NULL,
         updated_at               = NOW()
   WHERE id = p_contato_id
     AND ultima_interacao IN ('wait_follow_up', 'follow_up')
     AND follow_up_reservado_ate IS NOT NULL;
  GET DIAGNOSTICS v_hit = ROW_COUNT;
  IF v_hit THEN RETURN jsonb_build_object('ok', true, 'tipo', 'followup'); END IF;

  -- RMKT
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

NOTIFY pgrst, 'reload schema';

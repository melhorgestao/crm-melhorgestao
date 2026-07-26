-- ============================================================================
-- desagendar_followup_custom: cancela o F-UP Custom (botão "Cancelar
-- agendamento" no popup do calendário do Kanban) e devolve o lead pra fila
-- normal de follow-up.
--
-- Só age em leads que estão em wait_follow_up_custom (nunca inventa estado em
-- outra situação). Volta pra 'wait_follow_up' (estado VÁLIDO e VISÍVEL no
-- Kanban) — mantém follow_up_tentativas como está (não força pular o 4h; como
-- o custom foi cancelado antes de disparar, o lead segue a cadência normal a
-- partir de onde estava).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.desagendar_followup_custom(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_hit boolean;
BEGIN
  UPDATE public.contatos
     SET ultima_interacao   = 'wait_follow_up',
         followup_custom_em  = NULL,
         data_wait_follow_up = NOW(),
         updated_at          = NOW()
   WHERE id = p_contato_id
     AND ultima_interacao = 'wait_follow_up_custom';
  GET DIAGNOSTICS v_hit = ROW_COUNT;

  RETURN jsonb_build_object('ok', v_hit, 'desagendado', v_hit);
END $$;

GRANT EXECUTE ON FUNCTION public.desagendar_followup_custom(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

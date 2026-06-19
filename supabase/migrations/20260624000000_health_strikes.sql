-- ============================================================================
-- Health check de instância com strikes consecutivos + reativação automática.
-- Antes: pausava na 1ª falha transitória (state='connecting'). Hoje não voltava
-- sozinho mesmo quando Evolution já estava 'open'.
-- ============================================================================

ALTER TABLE public.instancias
  ADD COLUMN IF NOT EXISTS health_strikes      INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_health_check_em TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_health_state    TEXT;

COMMENT ON COLUMN public.instancias.health_strikes IS
  'Contador de falhas consecutivas no health check. Pausa só após 3 strikes.';

-- Reativa automaticamente se Evolution diz que tá 'open'.
-- Mantém status pausado_admin (pausa manual) intacto.
CREATE OR REPLACE FUNCTION public.health_check_marcar_ok(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_status TEXT; v_strikes INT;
BEGIN
  SELECT status, health_strikes INTO v_status, v_strikes
    FROM public.instancias WHERE id = p_id;

  -- Pausa manual NÃO mexe.
  IF v_status = 'pausado_admin' THEN
    RETURN jsonb_build_object('ok', true, 'action', 'skip_admin_pause');
  END IF;

  UPDATE public.instancias
     SET health_strikes        = 0,
         last_health_state     = 'open',
         last_health_check_em  = NOW(),
         -- reativa se estava em desconectado/banido (state agora OK)
         status                = CASE WHEN status IN ('desconectado','banido') THEN 'ativo' ELSE status END,
         pausado_ate           = CASE WHEN status IN ('desconectado','banido') THEN NULL  ELSE pausado_ate END,
         motivo_pausa          = CASE WHEN status IN ('desconectado','banido') THEN NULL  ELSE motivo_pausa END
   WHERE id = p_id;

  RETURN jsonb_build_object('ok', true,
                            'action', CASE WHEN v_status IN ('desconectado','banido') THEN 'reactivated' ELSE 'still_active' END,
                            'previous_status', v_status,
                            'strikes_zeroed', v_strikes);
END $$;

-- Incrementa strikes. Pausa só ao 3º strike consecutivo.
CREATE OR REPLACE FUNCTION public.health_check_strike(
  p_id uuid, p_state TEXT, p_horas INT DEFAULT 2
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_status TEXT; v_strikes INT; v_threshold CONSTANT INT := 3;
BEGIN
  SELECT status, health_strikes INTO v_status, v_strikes
    FROM public.instancias WHERE id = p_id;

  IF v_status = 'pausado_admin' THEN
    RETURN jsonb_build_object('ok', true, 'action', 'skip_admin_pause');
  END IF;

  v_strikes := COALESCE(v_strikes, 0) + 1;

  UPDATE public.instancias
     SET health_strikes       = v_strikes,
         last_health_state    = p_state,
         last_health_check_em = NOW()
   WHERE id = p_id;

  IF v_strikes >= v_threshold AND v_status = 'ativo' THEN
    UPDATE public.instancias
       SET status       = 'desconectado',
           pausado_ate  = NOW() + (p_horas || ' hours')::interval,
           motivo_pausa = 'health_check_strikes(' || v_strikes || ') state=' || p_state
     WHERE id = p_id;
    RETURN jsonb_build_object('ok', true, 'action', 'paused',
                              'strikes', v_strikes, 'state', p_state);
  END IF;

  RETURN jsonb_build_object('ok', true, 'action', 'strike_counted',
                            'strikes', v_strikes, 'threshold', v_threshold);
END $$;

GRANT EXECUTE ON FUNCTION public.health_check_marcar_ok(uuid)        TO service_role;
GRANT EXECUTE ON FUNCTION public.health_check_strike(uuid, text, int) TO service_role;

NOTIFY pgrst, 'reload schema';

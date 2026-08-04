-- ============================================================================
-- Disparo MANUAL (clicar na tag F-UP/RMKT no Kanban) agora registra o envio em
-- campanha_envios. Antes só avançava o contador — então esses disparos não
-- apareciam em "abertas" (Instâncias) nem no "Enviados hoje" das campanhas.
--
-- Usa campanha_id = NULL de propósito: conta como disparo (aparece em "abertas"
-- por instancia_id), mas NÃO consome a cota diária das campanhas automáticas
-- (escolhe_template_v2 conta por campanha_id específico). metadata.manual=true.
-- ============================================================================

-- ---- FOLLOW-UP manual -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_disparo_manual_followup(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_nova       int;
  v_c          record;
  v_apto_em    timestamptz;
  v_tent       int;
BEGIN
  SELECT * INTO v_c FROM public.contatos WHERE id = p_contato_id;
  IF v_c.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  IF v_c.ja_comprou <> false
     OR v_c.ultima_interacao NOT IN ('wait_follow_up', 'follow_up')
     OR COALESCE(v_c.follow_up_tentativas, 0) >= 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não elegível pra follow-up manual (estado/limite)');
  END IF;

  v_tent := COALESCE(v_c.follow_up_tentativas, 0);
  v_apto_em := CASE
    WHEN v_tent = 0 THEN COALESCE(v_c.data_ultima_entrada, v_c.data_wait_follow_up, v_c.data_start, NOW() - INTERVAL '999 days') + INTERVAL '4 hours'
    WHEN v_tent = 1 THEN COALESCE(v_c.data_ultimo_follow_up, v_c.data_wait_follow_up, NOW() - INTERVAL '999 days') + INTERVAL '3 days'
    ELSE               COALESCE(v_c.data_ultimo_follow_up, v_c.data_wait_follow_up, NOW() - INTERVAL '999 days') + INTERVAL '7 days'
  END;

  IF v_apto_em > NOW() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fora do prazo da cadência', 'next_apto_em', v_apto_em);
  END IF;

  UPDATE public.contatos
     SET ultima_interacao       = 'follow_up',
         follow_up_tentativas    = COALESCE(follow_up_tentativas, 0) + 1,
         data_ultimo_follow_up   = NOW(),
         follow_up_reservado_ate = NULL,
         updated_at              = NOW()
   WHERE id = p_contato_id
   RETURNING follow_up_tentativas INTO v_nova;

  -- loga o disparo manual (conta em "abertas"; não consome cota de campanha)
  BEGIN
    INSERT INTO public.campanha_envios (campanha_id, instancia_id, contato_id, metadata)
    VALUES (NULL, v_c.instancia_id, p_contato_id,
            jsonb_build_object('manual', true, 'via', 'kanban', 'tipo', 'followup', 'tentativa', v_nova));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'tipo', 'followup', 'tentativa', v_nova);
END $$;

GRANT EXECUTE ON FUNCTION public.registrar_disparo_manual_followup(uuid)
  TO authenticated, anon, service_role;

-- ---- RMKT manual ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_disparo_manual_rmkt(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_nova int;
  v_inst uuid;
BEGIN
  UPDATE public.contatos
     SET ultima_interacao             = 'rmkt',
         rmkt_consecutive_silenciosos = COALESCE(rmkt_consecutive_silenciosos, 0) + 1,
         data_ultimo_rmkt             = NOW(),
         rmkt_reservado_ate           = NULL,
         updated_at                   = NOW()
   WHERE id = p_contato_id
     AND ja_comprou = true
     AND ultima_interacao IN ('cliente', 'rmkt')
     AND COALESCE(rmkt_consecutive_silenciosos, 0) < 3
   RETURNING rmkt_consecutive_silenciosos, instancia_id INTO v_nova, v_inst;

  IF v_nova IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não elegível pra RMKT manual (estado/limite)');
  END IF;

  BEGIN
    INSERT INTO public.campanha_envios (campanha_id, instancia_id, contato_id, metadata)
    VALUES (NULL, v_inst, p_contato_id,
            jsonb_build_object('manual', true, 'via', 'kanban', 'tipo', 'rmkt', 'tentativa', v_nova));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'tipo', 'rmkt', 'tentativa', v_nova);
END $$;

GRANT EXECUTE ON FUNCTION public.registrar_disparo_manual_rmkt(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

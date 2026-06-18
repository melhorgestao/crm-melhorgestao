-- ============================================================================
-- pode_disparar_campanha: passa a respeitar horario_inicio/horario_fim e
-- limite_diario_total (campos da tabela campanhas que estavam sendo ignorados).
--
-- Vale pra ativacao, followup e rmkt (todos usam essa mesma RPC).
-- Workflows continuam Schedule a 1min — quem gateia o disparo é só essa função.
-- Timezone: America/Sao_Paulo (mesma usada na função antiga).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.pode_disparar_campanha(p_tipo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campanha             record;
  v_now_time             time;
  v_today                date;
  v_minutes_since_last   numeric;
  v_count_hoje           integer;
BEGIN
  v_now_time := (NOW() AT TIME ZONE 'America/Sao_Paulo')::time;
  v_today    := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;

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

  -- HORÁRIO PERMITIDO (fora da janela → não dispara)
  IF v_campanha.horario_inicio IS NOT NULL
     AND v_campanha.horario_fim   IS NOT NULL THEN
    -- Janela normal (08:00-20:00)
    IF v_campanha.horario_inicio <= v_campanha.horario_fim THEN
      IF v_now_time < v_campanha.horario_inicio OR v_now_time > v_campanha.horario_fim THEN
        RETURN jsonb_build_object(
          'ok', false,
          'motivo', 'fora_horario (' || v_now_time::text || ' /' ||
                    v_campanha.horario_inicio::text || '-' || v_campanha.horario_fim::text || ')',
          'campanha_id', v_campanha.id
        );
      END IF;
    -- Janela cruza meia-noite (22:00-06:00)
    ELSE
      IF v_now_time < v_campanha.horario_inicio AND v_now_time > v_campanha.horario_fim THEN
        RETURN jsonb_build_object(
          'ok', false, 'motivo', 'fora_horario_overnight',
          'campanha_id', v_campanha.id
        );
      END IF;
    END IF;
  END IF;

  -- LIMITE DIÁRIO TOTAL (conta envios da campanha hoje)
  IF v_campanha.limite_diario_total IS NOT NULL AND v_campanha.limite_diario_total > 0 THEN
    SELECT COUNT(*) INTO v_count_hoje
      FROM public.campanha_envios ce
     WHERE ce.campanha_id = v_campanha.id
       AND ce.enviado_em >= v_today::timestamptz
       AND ce.enviado_em <  (v_today + 1)::timestamptz;

    IF v_count_hoje >= v_campanha.limite_diario_total THEN
      RETURN jsonb_build_object(
        'ok', false,
        'motivo', 'limite_diario (' || v_count_hoje || '/' || v_campanha.limite_diario_total || ')',
        'campanha_id', v_campanha.id
      );
    END IF;
  END IF;

  -- INTERVALO MÍNIMO entre execuções
  IF v_campanha.ultima_execucao_em IS NOT NULL THEN
    v_minutes_since_last := EXTRACT(EPOCH FROM (NOW() - v_campanha.ultima_execucao_em)) / 60.0;
    IF v_minutes_since_last < v_campanha.intervalo_minutos THEN
      RETURN jsonb_build_object(
        'ok', false,
        'motivo', 'intervalo (' || round(v_minutes_since_last, 1) || '/' || v_campanha.intervalo_minutos || 'min)',
        'campanha_id', v_campanha.id
      );
    END IF;
  END IF;

  -- COFFEE BREAK
  IF v_campanha.coffee_break_inicio IS NOT NULL
     AND v_campanha.coffee_break_fim   IS NOT NULL
     AND v_now_time >= v_campanha.coffee_break_inicio
     AND v_now_time <= v_campanha.coffee_break_fim THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'coffee break', 'campanha_id', v_campanha.id);
  END IF;

  -- SKIP ALEATÓRIO (anti-ban)
  IF v_campanha.skip_rate > 0 AND random() < v_campanha.skip_rate THEN
    RETURN jsonb_build_object(
      'ok', false,
      'motivo', 'skip aleatório (' || (v_campanha.skip_rate * 100)::int || '%)',
      'campanha_id', v_campanha.id
    );
  END IF;

  -- Marca execução (atômico)
  UPDATE public.campanhas SET ultima_execucao_em = NOW() WHERE id = v_campanha.id;

  RETURN jsonb_build_object('ok', true, 'campanha_id', v_campanha.id);
END $$;

GRANT EXECUTE ON FUNCTION public.pode_disparar_campanha(text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

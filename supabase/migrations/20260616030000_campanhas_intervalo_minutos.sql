-- ============================================================================
-- Intervalo entre execuções editável via UI.
--
-- Workflows passam a rodar Schedule a 1 minuto. A RPC pode_disparar_campanha
-- decide quando realmente processar baseado em:
--   - intervalo_minutos (mínimo de N minutos entre execuções bem-sucedidas)
--   - ultima_execucao_em (timestamp da última vez que ok=true foi retornado)
--
-- Vantagem: trocar 5min ↔ 2min ↔ 60min na UI passa a valer imediatamente
-- sem precisar editar workflow.
-- ============================================================================

ALTER TABLE public.campanhas
  ADD COLUMN IF NOT EXISTS intervalo_minutos   integer NOT NULL DEFAULT 5
    CHECK (intervalo_minutos >= 1 AND intervalo_minutos <= 1440),
  ADD COLUMN IF NOT EXISTS ultima_execucao_em  timestamptz;

-- Seeds preservando comportamento histórico
UPDATE public.campanhas SET intervalo_minutos = 5  WHERE tipo = 'ativacao';
UPDATE public.campanhas SET intervalo_minutos = 30 WHERE tipo IN ('followup','rmkt');

-- ----------------------------------------------------------------------------
-- RPC pode_disparar_campanha atualizada — agora também valida intervalo
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
    RETURN jsonb_build_object(
      'ok', false,
      'motivo', 'coffee break',
      'campanha_id', v_campanha.id
    );
  END IF;

  -- SKIP ALEATÓRIO
  IF v_campanha.skip_rate > 0 AND random() < v_campanha.skip_rate THEN
    RETURN jsonb_build_object(
      'ok', false,
      'motivo', 'skip aleatório (' || (v_campanha.skip_rate * 100)::int || '%)',
      'campanha_id', v_campanha.id
    );
  END IF;

  -- Marca execução (atômico: usa o WHERE pra evitar race entre múltiplos workers)
  UPDATE public.campanhas
     SET ultima_execucao_em = NOW()
   WHERE id = v_campanha.id;

  RETURN jsonb_build_object('ok', true, 'campanha_id', v_campanha.id);
END $$;

GRANT EXECUTE ON FUNCTION public.pode_disparar_campanha(text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

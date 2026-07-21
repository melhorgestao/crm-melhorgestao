-- ============================================================================
-- Anti-ban: JITTER no intervalo entre disparos de campanha.
--
-- PROBLEMA: pode_disparar_campanha liberava assim que passava EXATAMENTE
-- intervalo_minutos desde o último. Como o workflow roda a cada 1 min, os
-- envios saíam num ritmo FIXO (ex.: a cada 30 min cravado) — padrão de bot,
-- fácil de flaggar. O JITTER 30-90s do workflow só mexe nos segundos do slot,
-- não na cadência.
--
-- FIX: cada disparo AGENDA o próximo com intervalo ALEATÓRIO em torno do
-- configurado: intervalo_minutos * (1 ± jitter_pct). Ex.: 30 min com ±40% →
-- próximo disparo entre 18 e 42 min. Guardado em campanhas.proximo_disparo_em;
-- o gate passa a ser "NOW() >= proximo_disparo_em".
--
-- intervalo_jitter_pct configurável por campanha (default 0.40 = ±40%).
-- ============================================================================

ALTER TABLE public.campanhas
  ADD COLUMN IF NOT EXISTS proximo_disparo_em    timestamptz,
  ADD COLUMN IF NOT EXISTS intervalo_jitter_pct  numeric NOT NULL DEFAULT 0.40
    CHECK (intervalo_jitter_pct >= 0 AND intervalo_jitter_pct <= 0.9);

COMMENT ON COLUMN public.campanhas.proximo_disparo_em IS
  'Momento (com jitter) em que o próximo disparo é liberado. Recalculado a cada disparo.';
COMMENT ON COLUMN public.campanhas.intervalo_jitter_pct IS
  'Variação aleatória do intervalo (0.40 = ±40%). Quebra o padrão fixo de envio (anti-ban).';

-- Backfill: campanhas com histórico respeitam o intervalo atual até o 1º
-- disparo jittered assumir.
UPDATE public.campanhas
   SET proximo_disparo_em = ultima_execucao_em + (intervalo_minutos || ' minutes')::interval
 WHERE ultima_execucao_em IS NOT NULL AND proximo_disparo_em IS NULL;

CREATE OR REPLACE FUNCTION public.pode_disparar_campanha(p_tipo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campanha       record;
  v_now_time       time;
  v_jitter_pct     numeric;
  v_fator          numeric;
  v_intervalo_seg  numeric;
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

  -- INTERVALO COM JITTER: gate é o proximo_disparo_em já sorteado.
  -- Fallback (pré-migration): se ainda não há proximo_disparo_em mas há
  -- ultima_execucao_em, usa o intervalo fixo até o próximo ciclo assumir.
  IF v_campanha.proximo_disparo_em IS NOT NULL THEN
    IF NOW() < v_campanha.proximo_disparo_em THEN
      RETURN jsonb_build_object('ok', false,
        'motivo', 'intervalo (aguardando ' ||
          round(EXTRACT(EPOCH FROM (v_campanha.proximo_disparo_em - NOW()))/60.0, 1) || ' min)',
        'campanha_id', v_campanha.id);
    END IF;
  ELSIF v_campanha.ultima_execucao_em IS NOT NULL THEN
    IF EXTRACT(EPOCH FROM (NOW() - v_campanha.ultima_execucao_em))/60.0 < v_campanha.intervalo_minutos THEN
      RETURN jsonb_build_object('ok', false, 'motivo', 'intervalo', 'campanha_id', v_campanha.id);
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

  -- LIBEROU: agenda o PRÓXIMO disparo com intervalo jittered.
  v_jitter_pct    := LEAST(GREATEST(COALESCE(v_campanha.intervalo_jitter_pct, 0.40), 0), 0.9);
  v_fator         := 1 + (random() * 2 - 1) * v_jitter_pct;      -- [1-pct, 1+pct]
  v_intervalo_seg := GREATEST(30, round(v_campanha.intervalo_minutos * v_fator * 60));

  UPDATE public.campanhas
     SET ultima_execucao_em = NOW(),
         proximo_disparo_em = NOW() + (v_intervalo_seg || ' seconds')::interval
   WHERE id = v_campanha.id;

  RETURN jsonb_build_object('ok', true, 'campanha_id', v_campanha.id,
    'proximo_em_min', round(v_intervalo_seg/60.0, 1));
END $$;

GRANT EXECUTE ON FUNCTION public.pode_disparar_campanha(text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

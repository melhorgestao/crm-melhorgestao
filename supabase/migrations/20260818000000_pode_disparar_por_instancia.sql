-- ============================================================================
-- Ritmo de campanha POR CHIP (per-instância) — destrava a vazão.
--
-- PROBLEMA: pode_disparar_campanha controlava o intervalo na LINHA DA CAMPANHA
-- (global). O workflow separa por instância, mas o 1º chip que passava no gate
-- agendava o próximo e BLOQUEAVA os demais naquele intervalo. Resultado: N
-- chips DIVIDIAM um único orçamento (~16/dia com intervalo de 30 min) em vez
-- de somarem. Por isso "16/dia é pouco".
--
-- FIX: o intervalo (com jitter) passa a ser controlado POR (campanha, chip).
-- 2 chips a 30 min = 32/dia; 3 chips = 48/dia — cada chip no MESMO passo
-- seguro, sem competir. Volume por chip continua limitado por instância
-- (limite_diario em escolhe_template_v2) — a trava de ban real.
--
-- horário permitido, coffee break e skip aleatório continuam GLOBAIS da
-- campanha (fazem sentido pra todos os chips).
--
-- Compat: p_instancia_id é opcional. Sem ele, cai no ritmo global antigo.
-- ============================================================================

-- Ritmo por (campanha, instância)
CREATE TABLE IF NOT EXISTS public.campanha_ritmo (
  campanha_id        uuid NOT NULL REFERENCES public.campanhas(id) ON DELETE CASCADE,
  instancia_id       uuid NOT NULL REFERENCES public.instancias(id) ON DELETE CASCADE,
  ultima_execucao_em timestamptz,
  proximo_disparo_em timestamptz,
  PRIMARY KEY (campanha_id, instancia_id)
);
ALTER TABLE public.campanha_ritmo ENABLE ROW LEVEL SECURITY;  -- só a RPC (definer) escreve

-- Remove a versão de 1 argumento pra não gerar ambiguidade de overload.
DROP FUNCTION IF EXISTS public.pode_disparar_campanha(text);

CREATE OR REPLACE FUNCTION public.pode_disparar_campanha(
  p_tipo text,
  p_instancia_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campanha       record;
  v_now_time       time;
  v_jitter_pct     numeric;
  v_fator          numeric;
  v_intervalo_seg  numeric;
  v_prox           timestamptz;
BEGIN
  v_now_time := (NOW() AT TIME ZONE 'America/Sao_Paulo')::time;

  SELECT c.* INTO v_campanha
    FROM public.campanhas c
   WHERE c.tipo = p_tipo AND c.ativa = true AND c.pausa_global = false
   ORDER BY c.created_at ASC LIMIT 1;

  IF v_campanha.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem campanha ativa');
  END IF;

  -- HORÁRIO PERMITIDO (global)
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

  -- INTERVALO COM JITTER — POR CHIP quando p_instancia_id vem; senão global.
  IF p_instancia_id IS NOT NULL THEN
    SELECT proximo_disparo_em INTO v_prox
      FROM public.campanha_ritmo
     WHERE campanha_id = v_campanha.id AND instancia_id = p_instancia_id;
  ELSE
    v_prox := v_campanha.proximo_disparo_em;
  END IF;

  IF v_prox IS NOT NULL AND NOW() < v_prox THEN
    RETURN jsonb_build_object('ok', false,
      'motivo', 'intervalo (aguardando ' || round(EXTRACT(EPOCH FROM (v_prox - NOW()))/60.0, 1) || ' min)',
      'campanha_id', v_campanha.id);
  END IF;

  -- COFFEE BREAK (global)
  IF v_campanha.coffee_break_inicio IS NOT NULL AND v_campanha.coffee_break_fim IS NOT NULL
     AND v_now_time >= v_campanha.coffee_break_inicio AND v_now_time <= v_campanha.coffee_break_fim THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'coffee break', 'campanha_id', v_campanha.id);
  END IF;

  -- SKIP ALEATÓRIO (por call)
  IF v_campanha.skip_rate > 0 AND random() < v_campanha.skip_rate THEN
    RETURN jsonb_build_object('ok', false,
      'motivo', 'skip aleatório (' || (v_campanha.skip_rate * 100)::int || '%)', 'campanha_id', v_campanha.id);
  END IF;

  -- LIBEROU: agenda o próximo disparo com jitter.
  v_jitter_pct    := LEAST(GREATEST(COALESCE(v_campanha.intervalo_jitter_pct, 0.40), 0), 0.9);
  v_fator         := 1 + (random() * 2 - 1) * v_jitter_pct;
  v_intervalo_seg := GREATEST(30, round(v_campanha.intervalo_minutos * v_fator * 60));

  IF p_instancia_id IS NOT NULL THEN
    INSERT INTO public.campanha_ritmo (campanha_id, instancia_id, ultima_execucao_em, proximo_disparo_em)
    VALUES (v_campanha.id, p_instancia_id, NOW(), NOW() + (v_intervalo_seg || ' seconds')::interval)
    ON CONFLICT (campanha_id, instancia_id) DO UPDATE
      SET ultima_execucao_em = EXCLUDED.ultima_execucao_em,
          proximo_disparo_em = EXCLUDED.proximo_disparo_em;
  END IF;

  -- ultima_execucao_em global fica atualizado pra exibição ("última execução")
  UPDATE public.campanhas
     SET ultima_execucao_em = NOW(),
         proximo_disparo_em = CASE WHEN p_instancia_id IS NULL
                                   THEN NOW() + (v_intervalo_seg || ' seconds')::interval
                                   ELSE proximo_disparo_em END
   WHERE id = v_campanha.id;

  RETURN jsonb_build_object('ok', true, 'campanha_id', v_campanha.id,
    'por_chip', p_instancia_id IS NOT NULL,
    'proximo_em_min', round(v_intervalo_seg/60.0, 1));
END $$;

GRANT EXECUTE ON FUNCTION public.pode_disparar_campanha(text, uuid)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

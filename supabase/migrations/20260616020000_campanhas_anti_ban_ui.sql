-- ============================================================================
-- Anti-ban editável via UI:
--   - coffee_break_inicio / coffee_break_fim: janela em que NÃO dispara (BRT)
--   - skip_rate: probabilidade 0..1 de pular cada execução
--
-- RPC pode_disparar_campanha(tipo) → retorna { ok, motivo }
-- Workflows chamam ANTES do claim pra não consumir tentativas à toa.
-- ============================================================================

ALTER TABLE public.campanhas
  ADD COLUMN IF NOT EXISTS coffee_break_inicio time,
  ADD COLUMN IF NOT EXISTS coffee_break_fim    time,
  ADD COLUMN IF NOT EXISTS skip_rate           numeric(4,2) NOT NULL DEFAULT 0
    CHECK (skip_rate >= 0 AND skip_rate <= 1);

-- Seeds preservando o comportamento histórico hardcoded
UPDATE public.campanhas
   SET coffee_break_inicio = '12:00',
       coffee_break_fim    = '13:30',
       skip_rate           = 0.10
 WHERE tipo = 'ativacao';

UPDATE public.campanhas
   SET coffee_break_inicio = '12:00',
       coffee_break_fim    = '13:30',
       skip_rate           = 0.04
 WHERE tipo IN ('followup', 'rmkt');

-- ----------------------------------------------------------------------------
-- RPC pode_disparar_campanha
--
-- Retorno: jsonb { ok: bool, motivo?: text, campanha_id?: uuid }
-- ok=false significa: pula este envio (coffee break OU skip aleatório)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pode_disparar_campanha(p_tipo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campanha record;
  v_now_time time;
BEGIN
  v_now_time := (NOW() AT TIME ZONE 'America/Sao_Paulo')::time;

  -- Pega campanha ativa do tipo (mesma que escolhe_template_v2 usa)
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

  -- COFFEE BREAK
  IF v_campanha.coffee_break_inicio IS NOT NULL
     AND v_campanha.coffee_break_fim   IS NOT NULL
     AND v_now_time >= v_campanha.coffee_break_inicio
     AND v_now_time <= v_campanha.coffee_break_fim THEN
    RETURN jsonb_build_object(
      'ok',     false,
      'motivo', 'coffee break',
      'campanha_id', v_campanha.id
    );
  END IF;

  -- SKIP ALEATÓRIO
  IF v_campanha.skip_rate > 0 AND random() < v_campanha.skip_rate THEN
    RETURN jsonb_build_object(
      'ok',     false,
      'motivo', 'skip aleatório (' || (v_campanha.skip_rate * 100)::int || '%)',
      'campanha_id', v_campanha.id
    );
  END IF;

  RETURN jsonb_build_object('ok', true, 'campanha_id', v_campanha.id);
END $$;

GRANT EXECUTE ON FUNCTION public.pode_disparar_campanha(text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

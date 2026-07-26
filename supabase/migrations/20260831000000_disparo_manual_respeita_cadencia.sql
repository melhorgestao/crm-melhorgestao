-- ============================================================================
-- Disparo manual de follow-up passa a respeitar a CADÊNCIA (igual ao claim).
--
-- Antes o botão "Confirmar X/3" no Kanban avançava o contador a qualquer hora,
-- permitindo disparo fora do prazo (risco de spam/ban). Agora a RPC só deixa
-- se o lead estiver REALMENTE apto:
--   tent 0 → 4h de silêncio real (data_ultima_entrada)
--   tent 1 → 3 dias do último envio (data_ultimo_follow_up)
--   tent 2 → 7 dias do último envio
-- A UI já mostra o contador e trava o botão; isto é a rede de segurança no
-- banco. Devolve next_apto_em pra UI poder exibir quanto falta.
-- ============================================================================

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

  -- estado/limite (igual antes)
  IF v_c.ja_comprou <> false
     OR v_c.ultima_interacao NOT IN ('wait_follow_up', 'follow_up')
     OR COALESCE(v_c.follow_up_tentativas, 0) >= 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não elegível pra follow-up manual (estado/limite)');
  END IF;

  -- momento em que o PRÓXIMO toque fica apto pela cadência
  v_tent := COALESCE(v_c.follow_up_tentativas, 0);
  v_apto_em := CASE
    WHEN v_tent = 0 THEN COALESCE(v_c.data_ultima_entrada, v_c.data_wait_follow_up, v_c.data_start, NOW() - INTERVAL '999 days') + INTERVAL '4 hours'
    WHEN v_tent = 1 THEN COALESCE(v_c.data_ultimo_follow_up, v_c.data_wait_follow_up, NOW() - INTERVAL '999 days') + INTERVAL '3 days'
    ELSE               COALESCE(v_c.data_ultimo_follow_up, v_c.data_wait_follow_up, NOW() - INTERVAL '999 days') + INTERVAL '7 days'
  END;

  IF v_apto_em > NOW() THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'fora do prazo da cadência',
      'next_apto_em', v_apto_em
    );
  END IF;

  UPDATE public.contatos
     SET ultima_interacao       = 'follow_up',
         follow_up_tentativas    = COALESCE(follow_up_tentativas, 0) + 1,
         data_ultimo_follow_up   = NOW(),
         follow_up_reservado_ate = NULL,
         updated_at              = NOW()
   WHERE id = p_contato_id
   RETURNING follow_up_tentativas INTO v_nova;

  RETURN jsonb_build_object('ok', true, 'tipo', 'followup', 'tentativa', v_nova);
END $$;

GRANT EXECUTE ON FUNCTION public.registrar_disparo_manual_followup(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

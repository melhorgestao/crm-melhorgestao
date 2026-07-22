-- ============================================================================
-- Trabalho manual + bot: comandos de save (só novos) + registrar disparo manual.
--
-- 1) salvar_contato_se_novo: /saveads e /savebase criam o contato SÓ SE NOVO
--    (ultima_interacao='start', pra o cron rodar normal). Contato existente
--    NÃO é tocado (no-op) — não sobrescreve nada.
--
-- 2) registrar_disparo_manual_followup / _rmkt: o dono clica na tag do card no
--    Kanban e confirma "realizei o disparo X/3 manualmente". Avança o contador
--    e carimba a data COMO SE o bot tivesse enviado (sem exigir reserva de
--    claim). Assim, com o bot off, os dados ficam atualizados e quando ele
--    voltar retoma de onde parou (não repete os toques já feitos à mão).
-- ============================================================================

-- 1) SAVE só se novo -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salvar_contato_se_novo(
  p_telefone     text,
  p_nome         text,
  p_instancia_id uuid,
  p_canal        text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_norm text;
  v_id   uuid;
BEGIN
  v_norm := public.normalize_telefone_br(p_telefone);
  IF v_norm IS NULL OR length(v_norm) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'telefone inválido');
  END IF;

  SELECT id INTO v_id
    FROM public.contatos
   WHERE telefone IS NOT NULL AND public.telefone_br_match(telefone, p_telefone)
   ORDER BY created_at ASC LIMIT 1;

  IF v_id IS NOT NULL THEN
    -- Já existe → NÃO toca em nada.
    RETURN jsonb_build_object('ok', true, 'ja_existe', true, 'contato_id', v_id);
  END IF;

  BEGIN
    INSERT INTO public.contatos (
      nome, telefone, canal_origem, canal_atual,
      instancia_id, ultima_interacao, created_at, updated_at
    ) VALUES (
      COALESCE(NULLIF(TRIM(p_nome), ''), v_norm),
      v_norm,
      p_canal, p_canal,
      p_instancia_id, 'start', NOW(), NOW()
    ) RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    SELECT id INTO v_id FROM public.contatos
     WHERE public.telefone_canonico_br(telefone) = public.telefone_canonico_br(v_norm)
     ORDER BY created_at ASC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'ja_existe', true, 'contato_id', v_id);
  END;

  RETURN jsonb_build_object('ok', true, 'ja_existe', false, 'contato_id', v_id, 'canal', p_canal);
END $$;

GRANT EXECUTE ON FUNCTION public.salvar_contato_se_novo(text, text, uuid, text)
  TO authenticated, anon, service_role;

-- 2a) Registrar follow-up manual ----------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_disparo_manual_followup(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_nova int;
BEGIN
  UPDATE public.contatos
     SET ultima_interacao       = 'follow_up',
         follow_up_tentativas    = COALESCE(follow_up_tentativas, 0) + 1,
         data_ultimo_follow_up   = NOW(),
         follow_up_reservado_ate = NULL,
         updated_at              = NOW()
   WHERE id = p_contato_id
     AND ultima_interacao IN ('wait_follow_up', 'follow_up')
     AND ja_comprou = false
     AND COALESCE(follow_up_tentativas, 0) < 3
   RETURNING follow_up_tentativas INTO v_nova;

  IF v_nova IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não elegível pra follow-up manual (estado/limite)');
  END IF;
  RETURN jsonb_build_object('ok', true, 'tipo', 'followup', 'tentativa', v_nova);
END $$;

GRANT EXECUTE ON FUNCTION public.registrar_disparo_manual_followup(uuid)
  TO authenticated, anon, service_role;

-- 2b) Registrar RMKT manual ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_disparo_manual_rmkt(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_nova int;
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
   RETURNING rmkt_consecutive_silenciosos INTO v_nova;

  IF v_nova IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não elegível pra RMKT manual (estado/limite)');
  END IF;
  RETURN jsonb_build_object('ok', true, 'tipo', 'rmkt', 'tentativa', v_nova);
END $$;

GRANT EXECUTE ON FUNCTION public.registrar_disparo_manual_rmkt(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

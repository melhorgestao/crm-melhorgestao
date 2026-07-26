-- ============================================================================
-- marcar_nunca_mais: o agent tira o lead de circulação em casos EXTREMOS de
-- recusa ("não tenho interesse", "não quero mais", "para de me mandar msg",
-- "me tira da lista"). Vira estado terminal NUNCA_MAIS — sai do follow-up/RMKT,
-- evitando bloqueios e denúncias por insistência.
--
-- NUNCA_MAIS é estado JÁ existente (setado pelos crons quando esgota tentativas)
-- e é limpo pelo cron diário de exclusão. Aqui é a versão sob demanda, chamada
-- pela tool do agent. Zera reservas/pausa e limpa o prazo custom.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.marcar_nunca_mais(
  p_contato_id uuid,
  p_motivo     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado_atual text;
BEGIN
  SELECT ultima_interacao INTO v_estado_atual
    FROM public.contatos WHERE id = p_contato_id;

  UPDATE public.contatos
     SET ultima_interacao        = 'NUNCA_MAIS',
         data_nunca_mais         = NOW(),
         followup_custom_em      = NULL,
         follow_up_reservado_ate = NULL,
         rmkt_reservado_ate      = NULL,
         bot_pausado_ate         = NULL,
         updated_at              = NOW()
   WHERE id = p_contato_id;

  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, estado_de, estado_para, metadata)
    VALUES (p_contato_id, 'nunca_mais', v_estado_atual, 'NUNCA_MAIS',
            jsonb_build_object('motivo', COALESCE(p_motivo, 'recusa_explicita')));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'estado_anterior', v_estado_atual);
END $$;

GRANT EXECUTE ON FUNCTION public.marcar_nunca_mais(uuid, text)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

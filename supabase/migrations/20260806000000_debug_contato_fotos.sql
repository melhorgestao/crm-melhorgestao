-- ============================================================================
-- RPC de DEBUG: raio-x de um contato pra depurar envio de fotos/mensagens.
--
-- Retorna: estado do contato (fotos_enviadas, ultima_interacao, pausa),
-- últimas mensagens do buffer (in/out) e últimos eventos_contato.
-- SECURITY DEFINER + grant anon: leitura pontual de diagnóstico via API
-- (mesmo padrão de acesso já usado por executa_comando_dono/get_or_create).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.debug_contato_fotos(p_telefone TEXT)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
  v_contato jsonb;
  v_buffer jsonb;
  v_eventos jsonb;
BEGIN
  SELECT id INTO v_id
    FROM contatos c
   WHERE c.telefone IS NOT NULL
     AND public.telefone_br_match(c.telefone, p_telefone)
   ORDER BY c.created_at ASC LIMIT 1;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  SELECT jsonb_build_object(
    'id', id, 'nome', nome, 'telefone', telefone,
    'ultima_interacao', ultima_interacao,
    'fotos_enviadas', to_jsonb(fotos_enviadas),
    'bot_pausado_ate', bot_pausado_ate,
    'instancia_id', instancia_id,
    'data_start', data_start,
    'updated_at', updated_at
  ) INTO v_contato FROM contatos WHERE id = v_id;

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_buffer FROM (
    SELECT jsonb_build_object(
      'recebida_em', recebida_em, 'direcao', direcao, 'tipo', tipo,
      'processada_em', processada_em, 'msg', left(mensagem, 160)
    ) AS x
    FROM mensagens_buffer
    WHERE contato_id = v_id
    ORDER BY recebida_em DESC LIMIT 10
  ) s;

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_eventos FROM (
    SELECT jsonb_build_object(
      'created_at', created_at, 'tipo', tipo, 'canal', canal,
      'metadata', metadata
    ) AS x
    FROM eventos_contato
    WHERE contato_id = v_id
    ORDER BY created_at DESC LIMIT 8
  ) s;

  RETURN jsonb_build_object('ok', true, 'contato', v_contato,
                            'buffer', v_buffer, 'eventos', v_eventos);
END $$;

GRANT EXECUTE ON FUNCTION public.debug_contato_fotos(TEXT)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

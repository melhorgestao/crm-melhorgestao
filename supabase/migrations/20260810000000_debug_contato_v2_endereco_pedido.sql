-- ============================================================================
-- debug_contato_fotos v2: inclui endereço/CPF + pedido em aberto.
-- Necessário pra depurar o loop "pede número+CPF de novo" com dados reais.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.debug_contato_fotos(p_telefone TEXT)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
  v_contato jsonb;
  v_buffer jsonb;
  v_eventos jsonb;
  v_pedido jsonb;
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
    'cep', cep, 'rua', rua, 'numero', numero, 'complemento', complemento,
    'bairro', bairro, 'cidade', cidade, 'uf', uf, 'cpf', cpf,
    'updated_at', updated_at
  ) INTO v_contato FROM contatos WHERE id = v_id;

  SELECT jsonb_build_object(
    'id', id, 'status', status, 'total', total,
    'pix_gerado', (pix_copia_cola IS NOT NULL),
    'pix_expira_em', pix_expira_em, 'created_at', created_at
  ) INTO v_pedido
    FROM pedido_em_aberto
   WHERE contato_id = v_id
   ORDER BY created_at DESC LIMIT 1;

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
                            'pedido_aberto', v_pedido,
                            'buffer', v_buffer, 'eventos', v_eventos);
END $$;

GRANT EXECUTE ON FUNCTION public.debug_contato_fotos(TEXT)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

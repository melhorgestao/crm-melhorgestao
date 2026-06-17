-- ============================================================================
-- RESET COMPLETO de um contato pra teste do bot do zero.
-- Telefone: 555198507433
--
-- Limpa: buffer, eventos, pedidos_em_aberto, todos os campos de
-- endereço e state machine. Mantém telefone, instancia_id e push_name.
-- ============================================================================

DO $$
DECLARE
  v_contato_id uuid;
BEGIN
  SELECT id INTO v_contato_id FROM public.contatos WHERE telefone = '555198507433' LIMIT 1;

  IF v_contato_id IS NULL THEN
    RAISE NOTICE 'Contato com telefone 555198507433 não encontrado — nada a fazer.';
    RETURN;
  END IF;

  -- buffer (mensagens in+out)
  DELETE FROM public.mensagens_buffer WHERE contato_id = v_contato_id;

  -- eventos (router_turn, etc)
  DELETE FROM public.eventos_contato WHERE contato_id = v_contato_id;

  -- pedidos em aberto (rascunhos não pagos)
  DELETE FROM public.pedidos_em_aberto WHERE contato_id = v_contato_id;

  -- zera campos do contato
  UPDATE public.contatos SET
    -- endereço
    cep            = NULL,
    rua            = NULL,
    rua_numero     = NULL,
    numero         = NULL,
    complemento    = NULL,
    bairro         = NULL,
    cidade         = NULL,
    cidade_uf      = NULL,
    uf             = NULL,

    -- state machine
    ultima_interacao             = NULL,
    ja_comprou                   = false,
    canal_atual                  = NULL,
    is_novo                      = true,
    novo_ate                     = NULL,
    representante_id             = NULL,
    estado_antes_suporte         = NULL,
    suporte_motivo               = NULL,
    ultima_campanha              = NULL,

    -- tentativas
    ativacao_tentativas          = 0,
    follow_up_tentativas         = 0,
    rastreio_tentativas          = 0,
    rmkt_consecutive_silenciosos = 0,

    -- datas
    data_start                = NULL,
    data_apresentacao         = NULL,
    data_wait_follow_up       = NULL,
    data_em_fechamento        = NULL,
    data_cliente              = NULL,
    data_cliente_pendente     = NULL,
    data_suporte              = NULL,
    data_nunca_mais           = NULL,
    data_ultimo_rmkt          = NULL,
    data_ultimo_follow_up     = NULL,
    data_ultimo_rastreio      = NULL,
    data_ultimo_ativacao      = NULL,
    primeira_venda_em         = NULL,
    ultima_venda_em           = NULL,
    rmkt_respondeu_em         = NULL,

    updated_at = NOW()
  WHERE id = v_contato_id;

  RAISE NOTICE 'Contato % (telefone 555198507433) zerado. Buffer/eventos/pedidos_em_aberto limpos.', v_contato_id;
END $$;

-- Confirmação visual
SELECT id, telefone, nome, cep, rua, numero, bairro, cidade, uf,
       ultima_interacao, ja_comprou, canal_atual, is_novo,
       data_start, data_em_fechamento, data_cliente
  FROM public.contatos
 WHERE telefone = '555198507433';

SELECT 'buffer'         AS tabela, COUNT(*) AS qtd FROM public.mensagens_buffer mb
  JOIN public.contatos c ON c.id = mb.contato_id WHERE c.telefone = '555198507433'
UNION ALL
SELECT 'eventos'        AS tabela, COUNT(*) AS qtd FROM public.eventos_contato ec
  JOIN public.contatos c ON c.id = ec.contato_id WHERE c.telefone = '555198507433'
UNION ALL
SELECT 'pedidos_aberto' AS tabela, COUNT(*) AS qtd FROM public.pedidos_em_aberto pa
  JOIN public.contatos c ON c.id = pa.contato_id WHERE c.telefone = '555198507433';

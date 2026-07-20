-- ============================================================================
-- REGRA: contato NUNCA sai do Kanban enquanto não paga.
--
-- criar_pedido_em_aberto (foundation 20260617) marcava
-- contatos.ultima_interacao='aguardando_pagamento' ao criar o rascunho do
-- pedido. Esse estado NÃO tem coluna no Kanban → o lead prestes a pagar
-- ficava INVISÍVEL pro humano. Regra do dono: estados de ultima_interacao
-- são só os que os crons/Kanban conhecem — quem está aguardando Pix fica
-- em 'em_fechamento' (coluna Fechamento), visível.
--
-- MUDANÇAS:
--  1) criar_pedido_em_aberto: mantém contato em 'em_fechamento' (não muda
--     estado). Continua carimbando data_aguardando_pagamento (o cron de
--     expiração do PEDIDO usa o status do pedido_em_aberto, não o contato).
--  2) BACKFILL: contatos hoje em 'aguardando_pagamento' voltam pra
--     'em_fechamento' (reaparecem no Kanban imediatamente).
--
-- O roteamento não muda: o router n8n manda em_fechamento pro agent-closing,
-- e o pedido aberto (status aguardando_pagamento NA TABELA DO PEDIDO) já
-- entra no prompt — o fluxo de pagar segue igual.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.criar_pedido_em_aberto(
  p_contato_id        uuid,
  p_instancia_id      uuid,
  p_itens             jsonb,
  p_brindes           jsonb,
  p_modalidade_frete  text,
  p_frete_preco       numeric,
  p_frete_prazo_min   integer,
  p_frete_prazo_max   integer,
  p_frete_gratis      boolean,
  p_endereco_snapshot jsonb,
  p_subtotal          numeric,
  p_total             numeric,
  p_resumo_formatado  text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
BEGIN
  -- cancela rascunho anterior se houver (cliente pode ter desistido antes)
  UPDATE public.pedido_em_aberto
     SET status = 'cancelado', updated_at = now()
   WHERE contato_id = p_contato_id
     AND status = 'aguardando_pagamento';

  INSERT INTO public.pedido_em_aberto (
    contato_id, instancia_id, itens, brindes, modalidade_frete,
    frete_preco, frete_prazo_min, frete_prazo_max, frete_gratis,
    endereco_snapshot, subtotal, total, resumo_formatado
  ) VALUES (
    p_contato_id, p_instancia_id, p_itens, p_brindes, p_modalidade_frete,
    p_frete_preco, p_frete_prazo_min, p_frete_prazo_max, p_frete_gratis,
    p_endereco_snapshot, p_subtotal, p_total, p_resumo_formatado
  ) RETURNING id INTO v_id;

  -- Contato FICA em 'em_fechamento' (visível no Kanban até pagar).
  -- data_aguardando_pagamento ainda é carimbada pra métricas/expiração.
  UPDATE public.contatos
     SET ultima_interacao          = 'em_fechamento',
         data_aguardando_pagamento = now(),
         updated_at                = now()
   WHERE id = p_contato_id;

  RETURN jsonb_build_object('ok', true, 'pedido_em_aberto_id', v_id);
END $$;

REVOKE ALL ON FUNCTION public.criar_pedido_em_aberto(uuid,uuid,jsonb,jsonb,text,numeric,integer,integer,boolean,jsonb,numeric,numeric,text) FROM public;
GRANT EXECUTE ON FUNCTION public.criar_pedido_em_aberto(uuid,uuid,jsonb,jsonb,text,numeric,integer,integer,boolean,jsonb,numeric,numeric,text) TO service_role;

-- BACKFILL: leads invisíveis voltam pro Kanban (coluna Fechamento)
UPDATE public.contatos
   SET ultima_interacao = 'em_fechamento', updated_at = now()
 WHERE ultima_interacao = 'aguardando_pagamento';

NOTIFY pgrst, 'reload schema';

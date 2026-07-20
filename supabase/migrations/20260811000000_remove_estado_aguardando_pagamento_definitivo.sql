-- ============================================================================
-- REMOÇÃO DEFINITIVA do estado 'aguardando_pagamento' em contatos.
--
-- REGRA DO DONO: contatos.ultima_interacao só pode ter estados que os CRONS e
-- o KANBAN conhecem. Lead aguardando Pix FICA em 'em_fechamento' (coluna
-- Fechamento), visível pro humano. Nada de estado "às cegas".
--
-- POR QUE AINDA EXISTIA (apesar da migration 20260809):
-- criar_pedido_em_aberto tem DUAS assinaturas (overload). A 20260809 corrigiu
-- a de 13 params, mas a edge calcular-pedido chama a de 15 params
-- (…, p_is_parcelado, p_caixa_id) criada em 20260618020000 — e ESSA continuava
-- fazendo ultima_interacao='aguardando_pagamento'. Era a que rodava.
--
-- ESTA MIGRATION:
--  1) Corrige o overload de 15 params (o que roda de verdade).
--  2) Dropa o overload de 13 params (morto, evita confusão futura).
--  3) Ajusta os crons que filtravam por ultima_interacao='aguardando_pagamento'
--     (20260618030000 / 20260618040000): o gatilho passa a ser o STATUS DO
--     PEDIDO (pedido_em_aberto.status), não o estado do contato.
--  4) Backfill: quem estiver no estado morto volta pra 'em_fechamento'.
--
-- IMPORTANTE: pedido_em_aberto.status='aguardando_pagamento' CONTINUA — é o
-- status do PEDIDO (outra tabela, não aparece no Kanban) e é o que o webhook
-- DeFlow e a expiração usam. Só o ESTADO DO CONTATO foi eliminado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) criar_pedido_em_aberto (15 params) — mantém contato em 'em_fechamento'
-- ----------------------------------------------------------------------------
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
  p_resumo_formatado  text,
  p_is_parcelado      boolean DEFAULT false,
  p_caixa_id          text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
  v_caixa text;
  v_primeira_parcela numeric;
BEGIN
  -- Cancela rascunho anterior se houver
  UPDATE public.pedido_em_aberto
     SET status = 'cancelado', updated_at = now()
   WHERE contato_id = p_contato_id
     AND status = 'aguardando_pagamento';

  -- Resolve caixa default
  IF p_caixa_id IS NULL THEN
    SELECT valor INTO v_caixa FROM public.configuracoes WHERE chave = 'caixa_default_bot';
    v_caixa := COALESCE(v_caixa, 'C1');
  ELSE
    v_caixa := p_caixa_id;
  END IF;

  v_primeira_parcela := CASE
    WHEN p_is_parcelado THEN ROUND(p_total / 2, 2)
    ELSE NULL
  END;

  INSERT INTO public.pedido_em_aberto (
    contato_id, instancia_id, itens, brindes, modalidade_frete,
    frete_preco, frete_prazo_min, frete_prazo_max, frete_gratis,
    endereco_snapshot, subtotal, total, resumo_formatado,
    is_parcelado, valor_primeira_parcela, caixa_id
  ) VALUES (
    p_contato_id, p_instancia_id, p_itens, p_brindes, p_modalidade_frete,
    p_frete_preco, p_frete_prazo_min, p_frete_prazo_max, p_frete_gratis,
    p_endereco_snapshot, p_subtotal, p_total, p_resumo_formatado,
    p_is_parcelado, v_primeira_parcela, v_caixa
  ) RETURNING id INTO v_id;

  -- Contato FICA em 'em_fechamento' (visível no Kanban até pagar).
  -- data_aguardando_pagamento segue carimbada só pra métrica/expiração.
  UPDATE public.contatos
     SET ultima_interacao          = 'em_fechamento',
         data_aguardando_pagamento = now(),
         updated_at                = now()
   WHERE id = p_contato_id;

  RETURN jsonb_build_object(
    'ok', true,
    'pedido_em_aberto_id', v_id,
    'is_parcelado', p_is_parcelado,
    'valor_a_pagar_pix', COALESCE(v_primeira_parcela, p_total),
    'valor_total', p_total,
    'caixa_id', v_caixa
  );
END $$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_em_aberto(uuid,uuid,jsonb,jsonb,text,numeric,integer,integer,boolean,jsonb,numeric,numeric,text,boolean,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 2) Dropa o overload MORTO de 13 params (ninguém chama; evita recair no bug)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.criar_pedido_em_aberto(
  uuid,uuid,jsonb,jsonb,text,numeric,integer,integer,boolean,jsonb,numeric,numeric,text
);

-- ----------------------------------------------------------------------------
-- 3) Crons de expiração: gatilho vira o STATUS DO PEDIDO, não o estado do contato
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expirar_pedidos_abandonados()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_expirados int := 0;
BEGIN
  -- Expira o PEDIDO (tabela própria). O contato permanece em 'em_fechamento'
  -- e o cron de 48h do fechamento decide o destino dele normalmente.
  WITH exp AS (
    UPDATE public.pedido_em_aberto
       SET status = 'expirado', updated_at = now()
     WHERE status = 'aguardando_pagamento'
       AND expires_at < now()
    RETURNING contato_id
  )
  SELECT count(*) INTO v_expirados FROM exp;

  -- Defensivo: se sobrou alguém no estado morto, devolve pro Kanban
  UPDATE public.contatos
     SET ultima_interacao = 'em_fechamento', updated_at = now()
   WHERE ultima_interacao = 'aguardando_pagamento';

  RETURN jsonb_build_object('ok', true, 'pedidos_expirados', v_expirados);
END $$;

GRANT EXECUTE ON FUNCTION public.expirar_pedidos_abandonados() TO service_role;

-- ----------------------------------------------------------------------------
-- 4) BACKFILL: ninguém fica invisível
-- ----------------------------------------------------------------------------
UPDATE public.contatos
   SET ultima_interacao = 'em_fechamento', updated_at = now()
 WHERE ultima_interacao = 'aguardando_pagamento';

NOTIFY pgrst, 'reload schema';

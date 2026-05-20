-- Pedidos FREE (Reposicao / Reenvio / Brinde)
-- - is_free=true marca o pedido como gratuito (sem impacto financeiro)
-- - Estoque AINDA é abatido (mesmo fluxo de criar_pedido_v2)
-- - NAO insere em lancamentos_socios (sem impacto em saldo/ticket/metricas)
-- - Pedido aparece em Logistica normalmente para gerar etiqueta

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS is_free boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_pedidos_is_free ON public.pedidos(is_free) WHERE is_free = true;

CREATE OR REPLACE FUNCTION public.criar_pedido_free(
  p_contato_id uuid,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido_id uuid; v_contato_id uuid; v_produto_id uuid; v_qtd integer;
  v_lote_rec record; v_order_number integer; v_data_sp date;
  v_uf_postagem_calc text; v_modalidade_calc text;
  v_criado_por_apelido text; v_quantidade_total integer; v_produto_text text;
  v_canal text;
BEGIN
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_contato_id IS NULL THEN RAISE EXCEPTION 'p_contato_id obrigatorio'; END IF;

  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id; END IF;

  SELECT nome INTO v_criado_por_apelido FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1;
  v_criado_por_apelido := COALESCE(NULLIF(v_criado_por_apelido, ''), 'sistema');

  -- Canal: pega do contato (canal_origem) com fallback para 'BASE'.
  -- NUNCA hardcode 'ADS' aqui — pedido FREE nao deve forcar canal.
  SELECT UPPER(canal_origem) INTO v_canal FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  v_canal := COALESCE(NULLIF(v_canal, ''), 'BASE');

  v_uf_postagem_calc := COALESCE(p_uf_postagem, 'SC');
  v_modalidade_calc := COALESCE(p_modalidade, 'mini');

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    v_quantidade_total := 0;
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      v_quantidade_total := v_quantidade_total + COALESCE(v_qtd, 1);
    END LOOP;
    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := (p_produtos->0->>'produto');
    ELSE
      v_produto_text := p_produtos::text;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
  END IF;

  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, obs, criado_por, order_number, data,
    estoque_processado, created_at, produto, quantidade,
    is_free
  )
  VALUES (
    p_contato_id, 0, v_canal, 'pago', v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, v_criado_por_apelido, v_order_number, v_data_sp,
    false, now(), COALESCE(v_produto_text, ''), v_quantidade_total,
    true
  )
  RETURNING id INTO v_pedido_id;

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      SELECT * INTO v_lote_rec FROM public.lotes l
      WHERE l.produto_id = v_produto_id AND l.uf = v_uf_postagem_calc
      ORDER BY l.data_producao ASC LIMIT 1;
      IF NOT FOUND THEN
        SELECT * INTO v_lote_rec FROM public.lotes l
        WHERE l.produto_id = v_produto_id
        ORDER BY l.data_producao ASC LIMIT 1;
      END IF;
      IF FOUND THEN
        UPDATE public.lotes SET quantidade_atual = quantidade_atual - v_qtd WHERE id = v_lote_rec.id;
        INSERT INTO public.estoque_movimentacoes (pedido_id, produto_id, quantidade, tipo, lote_id, uf_origem, observacao)
        VALUES (v_pedido_id, v_produto_id, v_qtd, 'saida', v_lote_rec.id, v_lote_rec.uf, 'Pedido FREE #' || v_order_number::text);
      ELSE
        INSERT INTO public.estoque_movimentacoes (pedido_id, produto_id, quantidade, tipo, uf_origem, observacao)
        VALUES (v_pedido_id, v_produto_id, v_qtd, 'saida', v_uf_postagem_calc, 'Pedido FREE #' || v_order_number::text || ' (sem lote)');
      END IF;
      INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco)
      VALUES (v_pedido_id, v_produto_id, COALESCE(v_qtd, 1), 0);
    END LOOP;
  END IF;

  -- Sem lancamentos_socios: FREE nao impacta financeiro nem metricas

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number, 'is_free', true);
EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Erro ao criar pedido free: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_free TO anon, authenticated, service_role;

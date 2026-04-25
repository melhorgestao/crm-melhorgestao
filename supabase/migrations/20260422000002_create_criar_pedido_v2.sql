-- ==============================================================================
-- CRIAR_PEDIDO_V2 - Baseado no schema .agent/schemas/pedido.md
-- Execute NO SUPABASE SQL EDITOR
-- ==============================================================================

BEGIN;

-- Garante que colunas existem
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS obs text;
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS observacao text;

-- Cria sequencia para order_number (thread-safe)
CREATE SEQUENCE IF NOT EXISTS public.pedidos_order_number_seq;

-- Inicia a partir do max atual
PERFORM setval('public.pedidos_order_number_seq', COALESCE(MAX(order_number), 0)) FROM public.pedidos;

-- Drop funcao antiga se existir
DROP FUNCTION IF EXISTS public.criar_pedido_v2(
  uuid, text, numeric, text, text, text, text, text, jsonb
);

CREATE OR REPLACE FUNCTION public.criar_pedido_v2(
  p_contato_id uuid,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido_id uuid;
  v_contato_id uuid;
  v_produto_id uuid;
  v_qtd integer;
  v_lote_rec record;
  v_order_number integer;
  v_data_sp date;
  v_uf_postagem_calc text;
  v_uf_cliente text;
  v_modalidade_calc text;
  v_socio text;
  v_canal_lancamento text;
  v_quantidade_total integer;
  v_produto_text text;
BEGIN
  -- order_number via sequence (thread-safe)
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Valida contato obrigatorio
  IF p_contato_id IS NULL THEN
    RAISE EXCEPTION 'p_contato_id e obrigatorio';
  END IF;

  -- Verifica se contato existe
  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN
    RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id;
  END IF;

  -- Determina socio pelo apelido (ver ou a - minúsculo ou maiúsculo)
  IF LOWER(p_criado_por) = 'ver' THEN
    v_socio := 'ver';
  ELSIF LOWER(p_criado_por) = 'a' THEN
    v_socio := 'a';
  ELSE
    -- Padrao: usar o apelido recebido diretamente
    v_socio := LOWER(p_criado_por);
  END IF;

  -- Canal do lancamento
  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS';
  END IF;

  -- Qtd total produtos
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM((item->>'quantidade')::integer), 1)::int INTO v_quantidade_total
    FROM jsonb_array_elements(p_produtos) AS item;
  ELSE
    v_quantidade_total := 1;
  END IF;

  -- UF do cliente
  BEGIN
    SELECT cidade_uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  -- UF postagem
  IF p_uf_postagem IS NOT NULL AND LENGTH(p_uf_postagem) = 2 THEN
    v_uf_postagem_calc := p_uf_postagem;
  ELSE
    v_uf_postagem_calc := COALESCE(v_uf_cliente, 'SC');
  END IF;

  v_modalidade_calc := COALESCE(p_modalidade, 'mini');

  -- Define produto: se 1 = texto, se +1 = JSON
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    v_quantidade_total := 0;
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      v_quantidade_total := v_quantidade_total + COALESCE(v_qtd, 1);
    END LOOP;
    
    -- Se 1 produto = texto, se +1 = JSON
    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := (p_produtos->0->>'produto');
    ELSE
      v_produto_text := p_produtos::text;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
  END IF;

  -- CRIA PEDIDO
  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, obs, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, v_socio, v_order_number, v_data_sp,
    false, now(),
    COALESCE(v_produto_text, ''), v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  -- Processa produtos e ABATE ESTOQUE
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      -- Busca lote
      SELECT * INTO v_lote_rec FROM public.lotes l
      WHERE l.produto_id = v_produto_id AND l.uf = v_uf_postagem_calc
      ORDER BY l.data_producao ASC LIMIT 1;

      IF NOT FOUND THEN
        SELECT * INTO v_lote_rec FROM public.lotes l
        WHERE l.produto_id = v_produto_id
        ORDER BY l.data_producao ASC LIMIT 1;
      END IF;

      -- ABATE SEMPRE (pode ficar negativo)
      IF FOUND THEN
        UPDATE public.lotes SET quantidade_atual = quantidade_atual - v_qtd WHERE id = v_lote_rec.id;
        
        -- Registra movimentacao
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, lote_id, uf_origem, observacao)
        VALUES (v_produto_id, v_qtd, 'saida', v_lote_rec.id, v_lote_rec.uf, 'Pedido: ' || v_pedido_id);
      END IF;

      -- Insere item no pedido
      INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco)
      VALUES (v_pedido_id, v_produto_id, COALESCE(v_qtd, 1), 0);
    END LOOP;
  END IF;

  -- CRIA LANCAMENTO DO SOCIO (so se pago)
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento,
      v_socio, v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_v2 TO anon, authenticated, service_role;

COMMIT;
-- =============================================================================
-- RODAR TUDO DE UMA VEZ no Supabase → SQL Editor → New query → colar → Run
-- Atualiza: triggers legados, criar_pedido, processar_pedido_estoque_trigger,
--           get_estoque_completo, trigger_uf_postagem_update (+ trigger na tabela)
-- =============================================================================

-- ========== BLOCO 1 (igual migrations/20260418000001_...) ==========
-- --- PARTE 1 ---
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque() CASCADE;

-- --- PARTE 2 ---
DROP FUNCTION IF EXISTS public.criar_pedido(
  uuid, text, numeric, text, text, text, text, text, jsonb, uuid
);

CREATE OR REPLACE FUNCTION public.criar_pedido(
  p_contato_id uuid DEFAULT NULL,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido_id uuid;
  v_order_number integer;
  v_data_sp date;
  v_produto_text text;
  v_quantidade integer;
  v_socio text;
  v_canal_lancamento text;
  v_is_entrega_maos boolean;
  v_uf_postagem_eff text;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_is_entrega_maos := (p_modalidade = 'entrega_maos');
  v_uf_postagem_eff := NULLIF(trim(COALESCE(p_uf_postagem, '')), '');

  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (
      SELECT string_agg(COALESCE(x->>'produto', x->>'nome_oficial'), ', ')
      FROM jsonb_array_elements(p_produtos) AS x
    );
    v_quantidade := (
      SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x
    );
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  v_socio := CASE
    WHEN p_criado_por ILIKE 'v%' OR p_criado_por ILIKE 'v@%' THEN 'V'
    ELSE 'A'
  END;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;

  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem,
    criado_por, produto, quantidade, order_number, data, status_pedido,
    representante_id, tipo_origem, entrega_em_maos, observacao,
    estoque_debitado, estoque_processado
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, p_status_pagamento, p_modalidade, v_uf_postagem_eff,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio',
    p_representante_id,
    CASE
      WHEN p_representante_id IS NOT NULL THEN 'rep'
      WHEN p_canal = 'ADS' THEN 'ads'
      ELSE 'base'
    END,
    v_is_entrega_maos, p_obs,
    v_is_entrega_maos,
    v_is_entrega_maos
  ) RETURNING id INTO v_pedido_id;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
    SELECT
      v_pedido_id,
      COALESCE(
        NULLIF(x->>'produto_id', '')::uuid,
        (SELECT pr.id FROM public.produtos pr
         WHERE pr.ativo = true AND lower(trim(pr.nome_oficial)) = lower(trim(COALESCE(x->>'produto', x->>'nome_oficial', '')))
         LIMIT 1)
      ),
      COALESCE(x->>'produto', x->>'nome_oficial'),
      GREATEST(COALESCE((x->>'quantidade')::integer, 0), 0),
      COALESCE(
        NULLIF(x->>'valor_unit', '')::numeric,
        NULLIF(x->>'preco', '')::numeric
      )
    FROM jsonb_array_elements(p_produtos) AS x
    WHERE COALESCE((x->>'quantidade')::integer, 0) > 0
      AND (
        NULLIF(x->>'produto_id', '') IS NOT NULL
        OR COALESCE(x->>'produto', x->>'nome_oficial', '') <> ''
      );
  END IF;

  IF p_representante_id IS NULL AND EXISTS (SELECT 1 FROM public.pedido_itens WHERE pedido_id = v_pedido_id) THEN
    PERFORM public.processar_pedido_estoque_trigger(v_pedido_id, v_uf_postagem_eff);
  END IF;

  IF p_contato_id IS NOT NULL AND p_status_pagamento = 'pago' THEN
    UPDATE public.contatos
    SET
      status_kanban = CASE WHEN p_canal = 'BASE' THEN 'Clientes' ELSE 'Pagou' END,
      canal_atual = CASE WHEN p_canal = 'BASE' THEN 'BASE' ELSE COALESCE(canal_atual, p_canal) END,
      is_novo = (p_canal = 'BASE'),
      novo_ate = CASE WHEN p_canal = 'BASE' THEN ((CURRENT_DATE + 1)::timestamptz) ELSE NULL END,
      updated_at = now()
    WHERE id = p_contato_id;
  END IF;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade, p_modalidade, v_uf_postagem_eff, 'pago', p_criado_por,
      v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'pedido_id', v_pedido_id,
    'order_number', v_order_number
  );
END;
$$;

-- --- PARTE 3 ---
DROP FUNCTION IF EXISTS public.processar_pedido_estoque_trigger(uuid, text);

CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(
  p_pedido_id uuid,
  p_uf_postagem text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_pref text;
  v_uf_eff text;
  v_total_items integer := 0;
  v_processed_items integer := 0;
  v_order_num integer;
  v_ja_saiu integer;
  v_linhas_mesmo_prod integer;
  v_legacy_saiu integer;
BEGIN
  SELECT p.order_number INTO v_order_num FROM public.pedidos p WHERE p.id = p_pedido_id;

  SELECT COALESCE(
    NULLIF(trim(COALESCE(p_uf_postagem, '')), ''),
    NULLIF(trim(COALESCE(po.uf_postagem, '')), '')
  ) INTO v_uf_pref
  FROM public.pedidos po
  WHERE po.id = p_pedido_id;

  FOR v_item IN
    SELECT pi.id, pi.produto_id, pi.nome_oficial, pi.quantidade
    FROM public.pedido_itens pi
    WHERE pi.pedido_id = p_pedido_id
      AND pi.produto_id IS NOT NULL
  LOOP
    v_total_items := v_total_items + 1;

    SELECT COALESCE(SUM(em.quantidade), 0)::integer INTO v_ja_saiu
    FROM public.estoque_movimentacoes em
    WHERE em.tipo = 'saida' AND em.pedido_item_id = v_item.id;

    IF v_ja_saiu = 0 THEN
      SELECT COUNT(*)::integer INTO v_linhas_mesmo_prod
      FROM public.pedido_itens pi
      WHERE pi.pedido_id = p_pedido_id AND pi.produto_id = v_item.produto_id;

      IF v_linhas_mesmo_prod <= 1 THEN
        SELECT COALESCE(SUM(em.quantidade), 0)::integer INTO v_legacy_saiu
        FROM public.estoque_movimentacoes em
        WHERE em.tipo = 'saida'
          AND em.pedido_id = p_pedido_id
          AND em.produto_id = v_item.produto_id
          AND em.pedido_item_id IS NULL;
        v_ja_saiu := v_legacy_saiu;
      END IF;
    END IF;

    v_remaining := GREATEST(v_item.quantidade - v_ja_saiu, 0);
    IF v_remaining <= 0 THEN
      CONTINUE;
    END IF;

    v_uf_eff := NULLIF(trim(COALESCE(v_uf_pref, '')), '');
    IF v_uf_eff IS NULL THEN
      SELECT u.uf INTO v_uf_eff
      FROM (
        SELECT l.uf, SUM(l.quantidade_atual)::bigint AS tot
        FROM public.lotes l
        WHERE l.produto_id = v_item.produto_id
          AND l.quantidade_atual > 0
        GROUP BY l.uf
        ORDER BY tot DESC, l.uf ASC
        LIMIT 1
      ) u;
    END IF;
    v_uf_eff := COALESCE(v_uf_eff, 'SP');

    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf
      FROM public.lotes
      WHERE produto_id = v_item.produto_id
        AND quantidade_atual > 0
      ORDER BY (uf = v_uf_eff) DESC, created_at ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;

      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);

      UPDATE public.lotes
      SET quantidade_atual = quantidade_atual - v_deduct
      WHERE id = v_lote_rec.id;

      INSERT INTO public.estoque_movimentacoes (
        produto_id, quantidade, tipo, posse, lote_id, uf_origem,
        pedido_item_id, pedido_id, observacao
      ) VALUES (
        v_item.produto_id, v_deduct, 'saida', 'Venda',
        v_lote_rec.id, v_lote_rec.uf,
        v_item.id, p_pedido_id,
        'Pedido #' || COALESCE(v_order_num::text, '?')
      );

      v_remaining := v_remaining - v_deduct;
    END LOOP;

    IF v_remaining > 0 THEN
      INSERT INTO public.estoque_movimentacoes (
        produto_id, quantidade, tipo, posse, lote_id, uf_origem,
        pedido_item_id, pedido_id, observacao
      ) VALUES (
        v_item.produto_id, v_remaining, 'saida', 'Venda',
        NULL, v_uf_eff,
        v_item.id, p_pedido_id,
        'Pedido #' || COALESCE(v_order_num::text, '?') || ' (sem lote)'
      );
    END IF;

    PERFORM public.update_produto_estoque(v_item.produto_id);
    v_processed_items := v_processed_items + 1;
  END LOOP;

  UPDATE public.pedidos
  SET estoque_processado = true
  WHERE id = p_pedido_id;

  PERFORM public.atualizar_estoque_snapshot();

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'total_items', v_total_items,
    'processed', v_processed_items
  );
END;
$$;

-- --- PARTE 4 ---
DROP FUNCTION IF EXISTS public.get_estoque_completo();

CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada int,
  saida int,
  saldo int
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH entradas AS (
    SELECT
      l.produto_id AS pid,
      COALESCE(l.uf, 'SP') AS uff,
      SUM(l.quantidade_atual)::int AS qtd_ent
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas AS (
    SELECT
      em.produto_id AS pid,
      COALESCE(NULLIF(trim(em.uf_origem), ''), 'SP') AS uff,
      SUM(em.quantidade)::int AS qtd_sai
    FROM public.estoque_movimentacoes em
    WHERE em.tipo = 'saida'
    GROUP BY em.produto_id, COALESCE(NULLIF(trim(em.uf_origem), ''), 'SP')
  ),
  chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas
  )
  SELECT
    ch.pid AS prod_id,
    pr.nome_oficial AS prod_nome,
    ch.uff AS estado,
    COALESCE(e.qtd_ent, 0) AS entrada,
    COALESCE(s.qtd_sai, 0) AS saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) AS saldo
  FROM chaves ch
  INNER JOIN public.produtos pr ON pr.id = ch.pid AND pr.ativo = true
  LEFT JOIN entradas e ON e.pid = ch.pid AND e.uff = ch.uff
  LEFT JOIN saidas s ON s.pid = ch.pid AND s.uff = ch.uff
  ORDER BY pr.nome_oficial, ch.uff;
END;
$$;

-- ========== BLOCO 2 (migrations/20260419000001 + trigger na tabela) ==========
CREATE OR REPLACE FUNCTION public.trigger_uf_postagem_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uf_new text;
  v_uf_old text;
BEGIN
  v_uf_new := NULLIF(trim(COALESCE(NEW.uf_postagem, '')), '');
  v_uf_old := NULLIF(trim(COALESCE(OLD.uf_postagem, '')), '');

  IF NEW.representante_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF v_uf_new IS NOT NULL
     AND (v_uf_old IS NULL OR v_uf_old = '')
     AND NEW.estoque_processado = false
  THEN
    PERFORM public.processar_pedido_estoque_trigger(NEW.id, v_uf_new);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_uf_postagem_update ON public.pedidos;
CREATE TRIGGER trg_uf_postagem_update
  AFTER UPDATE OF uf_postagem ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_uf_postagem_update();

-- ========== BLOCO 3 (migrations/20260420000001 — idempotente) ==========
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque() CASCADE;

-- ========== Confirmação + teste rápido (opcional) ==========
SELECT 'Estoque SQL aplicado: criar_pedido, processar, get_estoque_completo, UF postagem trigger.' AS status;

-- Descomente para testar RPC de cards:
-- SELECT * FROM public.get_estoque_completo() ORDER BY prod_nome, estado LIMIT 30;

-- ============================================================================
-- PEDIDO MISTO: itens de VENDA + itens FREE (reposição) no mesmo pedido.
--
-- O pedido NÃO é free (is_free=false a nível de pedido → aparece normal na
-- Logística), mas alguns ITENS podem ser free (reposição). Item free:
--   • baixa estoque normalmente (envio real);
--   • NÃO é cobrado (o valor da venda que o usuário digita já os exclui);
--   • NÃO recebe atribuição de faturamento por grupo (peso 0 no rateio);
--   • continua no total de unidades (divide custo op/produto un, como hoje).
--
-- Este passo: coluna pedido_itens.is_free + criar_pedido_v2 gravando o flag por
-- item + receita_por_grupo ignorando itens free no faturamento.
-- ============================================================================

ALTER TABLE public.pedido_itens
  ADD COLUMN IF NOT EXISTS is_free boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.pedido_itens.is_free IS
  'Item de reposição (free): baixa estoque mas não é cobrado nem gera faturamento. O pedido em si não é free.';

-- ── criar_pedido_v2: idêntico à 20260629, + is_free por item ────────────────
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
  v_is_free boolean;
  v_lote_rec record;
  v_order_number integer;
  v_data_sp date;
  v_uf_postagem_calc text;
  v_uf_cliente text;
  v_modalidade_calc text;
  v_socio text;
  v_criado_por_apelido text;
  v_canal_lancamento text;
  v_quantidade_total integer;
  v_produto_text text;
  v_snapshot_v numeric;
  v_snapshot_a numeric;
  v_input text;
BEGIN
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_contato_id IS NULL THEN
    RAISE EXCEPTION 'p_contato_id e obrigatorio';
  END IF;

  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN
    RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id;
  END IF;

  -- Normaliza socio: aceita V, A, P, C1..C5 (uppercase). Outros → V.
  v_input := UPPER(TRIM(COALESCE(p_criado_por, '')));
  IF v_input ~ '^C[1-5]$' THEN
    v_socio := v_input;
  ELSIF v_input = 'A' THEN
    v_socio := 'A';
  ELSIF v_input = 'P' THEN
    v_socio := 'P';
  ELSIF v_input = 'V' OR UPPER(LEFT(v_input, 1)) = 'V' THEN
    v_socio := 'V';
  ELSE
    v_socio := 'V';
  END IF;

  SELECT nome INTO v_criado_por_apelido
  FROM public.perfis_usuario
  WHERE user_id = auth.uid()
  LIMIT 1;
  v_criado_por_apelido := COALESCE(NULLIF(v_criado_por_apelido, ''), v_socio);

  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS';
  END IF;

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM((item->>'quantidade')::integer), 1)::int INTO v_quantidade_total
    FROM jsonb_array_elements(p_produtos) AS item;
  ELSE
    v_quantidade_total := 1;
  END IF;

  BEGIN
    SELECT cidade_uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  IF p_uf_postagem IS NOT NULL AND LENGTH(p_uf_postagem) = 2 THEN
    v_uf_postagem_calc := p_uf_postagem;
  ELSE
    v_uf_postagem_calc := COALESCE(v_uf_cliente, 'SC');
  END IF;

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
    status_pedido, obs, observacao, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, COALESCE(p_obs, '')::text,
    v_criado_por_apelido, v_order_number, v_data_sp,
    false, now(),
    COALESCE(v_produto_text, ''), v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_produto_id, v_qtd, v_is_free IN
      SELECT (item->>'produto_id')::uuid,
             COALESCE((item->>'quantidade')::integer, 1),
             COALESCE((item->>'is_free')::boolean, false)
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
        VALUES (v_pedido_id, v_produto_id, v_qtd, 'saida', v_lote_rec.id, v_lote_rec.uf, 'Pedido #' || v_order_number::text);
      ELSE
        INSERT INTO public.estoque_movimentacoes (pedido_id, produto_id, quantidade, tipo, uf_origem, observacao)
        VALUES (v_pedido_id, v_produto_id, v_qtd, 'saida', v_uf_postagem_calc, 'Pedido #' || v_order_number::text || ' (sem lote)');
      END IF;

      INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco, is_free)
      VALUES (v_pedido_id, v_produto_id, COALESCE(v_qtd, 1), 0, COALESCE(v_is_free, false));
    END LOOP;
  END IF;

  IF p_status_pagamento = 'pago' THEN
    SELECT
      COALESCE(SUM(CASE WHEN socio = 'V' THEN valor ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN socio = 'A' THEN valor ELSE 0 END), 0)
    INTO v_snapshot_v, v_snapshot_a
    FROM public.lancamentos_socios;

    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao,
      snapshot_saldo_v, snapshot_saldo_a
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento,
      v_criado_por_apelido, v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text,
      v_snapshot_v, v_snapshot_a
    );
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_v2 TO anon, authenticated, service_role;

-- ── receita_por_grupo: itens FREE não geram faturamento (peso 0 / excluídos) ─
CREATE OR REPLACE FUNCTION public.receita_por_grupo(p_inicio text, p_fim text)
RETURNS TABLE (grupo_id uuid, grupo_nome text, receita numeric, unidades numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH ped_ok AS (
    SELECT p.id,
           (COALESCE(p.valor_original, p.valor, 0) - COALESCE(p.desconto_total, 0)) AS venda_real
      FROM public.pedidos p
     WHERE p.is_free IS DISTINCT FROM true
       AND p.status_pagamento IN ('pago', 'pendente')
       AND p.data::date >= p_inicio::date
       AND p.data::date <  p_fim::date
       AND (COALESCE(p.valor_original, p.valor, 0) - COALESCE(p.desconto_total, 0)) > 0
  ),
  -- itens que CONTAM pra faturamento: exclui itens free (reposição).
  itens AS (
    SELECT pi.pedido_id, pi.produto_id, pi.quantidade
      FROM public.pedido_itens pi
     WHERE pi.pedido_id IN (SELECT id FROM ped_ok)
       AND COALESCE(pi.is_free, false) = false
    UNION ALL
    SELECT po.id, p.produto_id, COALESCE(p.quantidade, 1)
      FROM ped_ok po
      JOIN public.pedidos p ON p.id = po.id
     WHERE p.produto_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi2 WHERE pi2.pedido_id = po.id)
  ),
  grp AS (
    SELECT it.pedido_id,
           pr.grupo_id,
           SUM(COALESCE(pr.preco, 0) * it.quantidade) AS peso,
           SUM(it.quantidade)                          AS qtd
      FROM itens it
      JOIN public.produtos pr ON pr.id = it.produto_id
     GROUP BY it.pedido_id, pr.grupo_id
  ),
  tot AS (
    SELECT pedido_id, SUM(peso) AS peso_total, SUM(qtd) AS qtd_total
      FROM grp GROUP BY pedido_id
  )
  SELECT grp.grupo_id,
         COALESCE(g.nome, 'Sem grupo') AS grupo_nome,
         SUM(
           po.venda_real *
           CASE WHEN tot.peso_total > 0 THEN grp.peso / tot.peso_total
                WHEN tot.qtd_total  > 0 THEN grp.qtd::numeric / tot.qtd_total
                ELSE 0 END
         )::numeric AS receita,
         SUM(grp.qtd)::numeric AS unidades
    FROM grp
    JOIN tot   ON tot.pedido_id = grp.pedido_id
    JOIN ped_ok po ON po.id     = grp.pedido_id
    LEFT JOIN public.produtos_grupos g ON g.id = grp.grupo_id
   GROUP BY grp.grupo_id, g.nome
   ORDER BY receita DESC;
$$;

GRANT EXECUTE ON FUNCTION public.receita_por_grupo(text, text)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

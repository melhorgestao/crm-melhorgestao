-- ============================================================================
-- Estoque — 2 correções
--
-- 1) Cron 'atualizar-estoque-snapshot' a cada 10min
--    Cards de estoque agora sempre frescos (era manual, ficava horas defasado)
--
-- 2) RPC recriar_movs_pedidos_orfaos()
--    Itera pedidos sem movimentação e cria movs faltantes a partir do
--    JSON em pedidos.produto (formato novo) ou da combinação produto-texto +
--    quantidade total (formato antigo).
--    Idempotente: só toca em pedidos sem movs.
--    Executada uma vez no final pra preencher os 17 órfãos atuais (44 unidades).
--
-- UF de origem: usa uf_postagem do pedido; fallback 'RS' se ausente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) RPC recriar_movs_pedidos_orfaos
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recriar_movs_pedidos_orfaos()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ped record;
  v_item jsonb;
  v_produto_id uuid;
  v_qtd integer;
  v_uf text;
  v_movs_criadas integer := 0;
  v_pedidos_processados integer := 0;
  v_pedidos_sem_match integer := 0;
BEGIN
  -- itera pedidos onde quantidade total > soma de movimentações
  FOR v_ped IN
    SELECT p.id, p.order_number, p.produto, p.quantidade, p.uf_postagem
      FROM public.pedidos p
     WHERE p.status_pedido != 'cancelado'
       AND p.quantidade > COALESCE((
         SELECT SUM(m.quantidade) FROM public.estoque_movimentacoes m
          WHERE m.pedido_id = p.id AND m.tipo = 'saida'
       ), 0)
  LOOP
    v_uf := COALESCE(NULLIF(trim(v_ped.uf_postagem), ''), 'RS');
    v_pedidos_processados := v_pedidos_processados + 1;

    -- formato NOVO: p.produto é JSON array
    BEGIN
      IF jsonb_typeof(v_ped.produto::jsonb) = 'array' THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_ped.produto::jsonb)
        LOOP
          v_produto_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qtd        := COALESCE((v_item->>'quantidade')::integer, 1);

          -- fallback: tenta match por tag/nome se produto_id ausente
          IF v_produto_id IS NULL THEN
            SELECT id INTO v_produto_id
              FROM public.produtos
             WHERE LOWER(tag) = LOWER(v_item->>'produto')
                OR LOWER(nome_oficial) = LOWER(v_item->>'produto')
             LIMIT 1;
          END IF;

          IF v_produto_id IS NOT NULL AND v_qtd > 0 THEN
            INSERT INTO public.estoque_movimentacoes
              (pedido_id, produto_id, quantidade, tipo, uf_origem, observacao, data)
            VALUES
              (v_ped.id, v_produto_id, v_qtd, 'saida', v_uf,
               'Pedido #' || v_ped.order_number || ' (backfill)',
               CURRENT_DATE);
            v_movs_criadas := v_movs_criadas + 1;
          ELSE
            v_pedidos_sem_match := v_pedidos_sem_match + 1;
          END IF;
        END LOOP;
        CONTINUE;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- p.produto não é JSON válido → trata como formato antigo
      NULL;
    END;

    -- formato ANTIGO: p.produto é texto, p.quantidade é total
    SELECT id INTO v_produto_id
      FROM public.produtos
     WHERE LOWER(tag) = LOWER(trim(v_ped.produto))
        OR LOWER(nome_oficial) = LOWER(trim(v_ped.produto))
     LIMIT 1;

    IF v_produto_id IS NOT NULL THEN
      INSERT INTO public.estoque_movimentacoes
        (pedido_id, produto_id, quantidade, tipo, uf_origem, observacao, data)
      VALUES
        (v_ped.id, v_produto_id, v_ped.quantidade, 'saida', v_uf,
         'Pedido #' || v_ped.order_number || ' (backfill)',
         CURRENT_DATE);
      v_movs_criadas := v_movs_criadas + 1;
    ELSE
      v_pedidos_sem_match := v_pedidos_sem_match + 1;
    END IF;
  END LOOP;

  -- atualiza snapshot pra refletir backfill
  PERFORM public.atualizar_estoque_snapshot();

  RETURN jsonb_build_object(
    'ok', true,
    'pedidos_processados', v_pedidos_processados,
    'movimentacoes_criadas', v_movs_criadas,
    'pedidos_sem_match', v_pedidos_sem_match
  );
END $$;

GRANT EXECUTE ON FUNCTION public.recriar_movs_pedidos_orfaos() TO service_role, authenticated;

-- ----------------------------------------------------------------------------
-- 2) Cron pg_cron: atualizar snapshot a cada 10min
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid)
      FROM cron.job
     WHERE jobname = 'atualizar-estoque-snapshot';

    PERFORM cron.schedule(
      'atualizar-estoque-snapshot',
      '*/10 * * * *',
      $cron$ SELECT public.atualizar_estoque_snapshot(); $cron$
    );
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3) Backfill imediato dos 17 órfãos atuais (44 unidades)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT public.recriar_movs_pedidos_orfaos() INTO v_result;
  RAISE NOTICE 'Backfill resultado: %', v_result;
END $$;

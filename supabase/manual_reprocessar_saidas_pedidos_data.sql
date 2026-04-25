-- =============================================================================
-- Regravar saídas em estoque_movimentacoes via processar_pedido_estoque_trigger
-- (ex.: após apagar lançamentos duplicados manualmente)
--
-- ⚠️ ATENÇÃO — LEIA ANTES DE RODAR
-- Esta função TAMBÉM abate de novo em public.lotes (quantidade_atual).
-- Só use se UMA destas for verdade:
--   A) Você apagou só linhas duplicadas e AINDA EXISTE pelo menos uma saída
--      correta por pedido_item_id → o trigger só completa o que falta (idempotente).
--   B) Você apagou TODAS as saídas desse pedido E já devolveu as quantidades nos
--      lotes (estoque físico igual ao “antes do pedido”).
-- NÃO rode se apagou todas as movimentações mas os lotes continuam abatidos:
--      isso descontaria o pedido duas vezes no estoque físico.
-- =============================================================================

-- 1) Conferir pedidos do dia (ajuste a data se precisar)
SELECT
  p.id,
  p.order_number,
  p.data,
  p.uf_postagem,
  p.estoque_processado,
  c.nome AS cliente
FROM public.pedidos p
LEFT JOIN public.contatos c ON c.id = p.contato_id
WHERE p.data = DATE '2026-04-11'
ORDER BY p.order_number;

-- 2) Conferir itens e movimentações atuais (troque o order_number se for só um pedido)
SELECT pi.*, pr.nome_oficial
FROM public.pedido_itens pi
JOIN public.pedidos p ON p.id = pi.pedido_id
LEFT JOIN public.produtos pr ON pr.id = pi.produto_id
WHERE p.order_number = 12;

SELECT em.*
FROM public.estoque_movimentacoes em
JOIN public.pedidos p ON p.id = em.pedido_id
WHERE p.order_number = 12
  AND em.tipo = 'saida'
ORDER BY em.created_at;

-- =============================================================================
-- 3) REPROCESSAR — descomente UM dos blocos abaixo
-- =============================================================================

-- --- Opção A: só UM pedido (troque 12 pelo order_number correto, ex. 11 ou 12) ---
/*
UPDATE public.pedidos
SET estoque_processado = false
WHERE order_number = 12;

SELECT public.processar_pedido_estoque_trigger(
  p.id,
  NULLIF(trim(COALESCE(p.uf_postagem, '')), '')
)
FROM public.pedidos p
WHERE p.order_number = 12;
*/

-- --- Opção B: todos os pedidos do dia 11/04/2026 (sem representante) ---
/*
UPDATE public.pedidos
SET estoque_processado = false
WHERE data = DATE '2026-04-11'
  AND representante_id IS NULL;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT id, uf_postagem
    FROM public.pedidos
    WHERE data = DATE '2026-04-11'
      AND representante_id IS NULL
    ORDER BY order_number
  LOOP
    PERFORM public.processar_pedido_estoque_trigger(
      r.id,
      NULLIF(trim(COALESCE(r.uf_postagem, '')), '')
    );
  END LOOP;
END $$;
*/

-- 4) Conferir de novo
-- SELECT * FROM public.get_estoque_completo() ORDER BY prod_nome, estado;
-- SELECT em.* FROM public.estoque_movimentacoes em JOIN public.pedidos p ON p.id = em.pedido_id WHERE p.order_number = 12 AND em.tipo = 'saida';

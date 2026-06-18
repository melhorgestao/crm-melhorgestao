-- ============================================================================
-- 3 fixes em uma migration:
--
-- 1) GARANTE colunas que o cron state-machine precisa (estavam ausentes em prod?)
--    rmkt_respondeu_em + duvidas_consecutivas + outras citadas pela função.
--
-- 2) Trigger AFTER INSERT em pedidos: ao registrar venda (qualquer canal,
--    qualquer status_pgto != 'cancelado'), marca o contato como cliente.
--    Resolve o caso do Claudio: vendeu manualmente, ficou em em_fechamento.
--
-- 3) Pedidos ganha uf_postagem TEXT DEFAULT 'RS' (fallback única UF ativa
--    por enquanto — depois aceitamos mais).
-- ============================================================================

-- ---- 1) garante colunas faltantes ----------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS rmkt_respondeu_em            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rmkt_consecutive_silenciosos INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS duvidas_consecutivas         INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS data_cliente                 TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_em_fechamento           TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_aguardando_pagamento    TIMESTAMPTZ;

-- ---- 2) trigger: pedido criado → contato vira cliente --------------------
CREATE OR REPLACE FUNCTION public.trigger_contato_virou_cliente()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Só faz sentido pra pedidos com contato_id, não cancelado
  IF NEW.contato_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status_pedido = 'cancelado' THEN RETURN NEW; END IF;

  UPDATE public.contatos
     SET ja_comprou         = true,
         ultima_interacao   = 'cliente',
         data_cliente       = COALESCE(data_cliente, NOW()),
         data_em_fechamento = NULL,
         data_aguardando_pagamento = NULL,
         primeira_venda_em  = COALESCE(primeira_venda_em, NOW()::date),
         ultima_venda_em    = NOW()::date,
         updated_at         = NOW()
   WHERE id = NEW.contato_id;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_contato_virou_cliente ON public.pedidos;
CREATE TRIGGER trg_contato_virou_cliente
  AFTER INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_contato_virou_cliente();

-- ---- 2.1) backfill: contatos com pedido ativo mas ainda em em_fechamento --
UPDATE public.contatos c
   SET ja_comprou        = true,
       ultima_interacao  = 'cliente',
       data_cliente      = COALESCE(data_cliente, NOW()),
       data_em_fechamento = NULL,
       primeira_venda_em = COALESCE(primeira_venda_em, (SELECT MIN(data) FROM public.pedidos p WHERE p.contato_id = c.id)),
       ultima_venda_em   = COALESCE(ultima_venda_em,   (SELECT MAX(data) FROM public.pedidos p WHERE p.contato_id = c.id)),
       updated_at        = NOW()
 WHERE EXISTS (
   SELECT 1 FROM public.pedidos p
    WHERE p.contato_id = c.id AND p.status_pedido != 'cancelado'
 )
   AND (c.ultima_interacao IN ('em_fechamento', 'aguardando_pagamento') OR c.ja_comprou IS DISTINCT FROM true);

-- ---- 3) UF de postagem no pedido com default RS --------------------------
ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS uf_postagem TEXT NOT NULL DEFAULT 'RS';

COMMENT ON COLUMN public.pedidos.uf_postagem IS
  'UF de origem da postagem. Default RS (única UF ativa). Quando expandirmos, vira parâmetro do agent_closing.';

NOTIFY pgrst, 'reload schema';

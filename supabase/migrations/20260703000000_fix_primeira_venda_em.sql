-- ============================================================================
-- Fix: primeira_venda_em ficava NULL em muitos contatos com pedidos.
--
-- CAUSA:
--   Trigger trigger_contato_virou_cliente usava NOW()::date — se trigger
--   não roda (insert antigo, falha silenciosa em backfills passados),
--   primeira_venda_em fica NULL pra sempre.
--   Também: deveria refletir a DATA REAL do pedido (NEW.data), não NOW().
--   Pedidos retroativos (data passada) salvavam data errada.
--
-- AÇÕES:
--   1) Recria trigger usando COALESCE(NEW.data, CURRENT_DATE) — fonte de
--      verdade é a data do pedido, não NOW().
--   2) BACKFILL definitivo: contatos com pedidos NÃO cancelados sem
--      primeira_venda_em / ultima_venda_em populados.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trigger_contato_virou_cliente()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_data date := COALESCE(NEW.data, (NOW() AT TIME ZONE 'America/Sao_Paulo')::date);
BEGIN
  IF NEW.contato_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status_pedido = 'cancelado' THEN RETURN NEW; END IF;

  UPDATE public.contatos
     SET ja_comprou                = true,
         ultima_interacao          = 'cliente',
         data_cliente              = COALESCE(data_cliente, NOW()),
         data_em_fechamento        = NULL,
         data_aguardando_pagamento = NULL,
         primeira_venda_em         = LEAST(COALESCE(primeira_venda_em, v_data), v_data),
         ultima_venda_em           = GREATEST(COALESCE(ultima_venda_em, v_data), v_data),
         updated_at                = NOW()
   WHERE id = NEW.contato_id;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_contato_virou_cliente ON public.pedidos;
CREATE TRIGGER trg_contato_virou_cliente
  AFTER INSERT ON public.pedidos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_contato_virou_cliente();

-- ----------------------------------------------------------------------------
-- BACKFILL: contatos com pedido ativo mas primeira/ultima venda vazios
-- ----------------------------------------------------------------------------
UPDATE public.contatos c
   SET primeira_venda_em = sub.min_data,
       ultima_venda_em   = sub.max_data,
       ja_comprou        = true,
       data_cliente      = COALESCE(c.data_cliente, sub.min_data::timestamptz),
       updated_at        = NOW()
  FROM (
    SELECT contato_id, MIN(data) AS min_data, MAX(data) AS max_data
      FROM public.pedidos
     WHERE contato_id IS NOT NULL AND status_pedido != 'cancelado'
     GROUP BY contato_id
  ) sub
 WHERE c.id = sub.contato_id
   AND (c.primeira_venda_em IS NULL
        OR c.ultima_venda_em IS NULL
        OR c.primeira_venda_em > sub.min_data
        OR c.ultima_venda_em   < sub.max_data);

NOTIFY pgrst, 'reload schema';

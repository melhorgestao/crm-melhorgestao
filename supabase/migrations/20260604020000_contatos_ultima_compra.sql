-- ============================================================================
-- Feature: Filtro de 30 dias pra RMKT BASE — exclui quem comprou recente
--
-- Cria coluna contatos.ultima_compra_em (DATE) mantida automaticamente
-- por trigger em pedidos. RMKT BASE filtra: ultima_compra_em IS NULL OR
-- ultima_compra_em < hoje - 30 dias.
--
-- Objetivo: evitar incomodar cliente que acabou de comprar.
-- ============================================================================

-- 1) Coluna
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS ultima_compra_em DATE;

COMMENT ON COLUMN public.contatos.ultima_compra_em IS
  'Data da última compra paga deste contato (sincronizada por trigger). Usado pra excluir do RMKT BASE quem comprou < 30 dias.';

-- 2) Backfill: pega MAX(data_pago) de pedidos pagos
UPDATE public.contatos c
SET ultima_compra_em = sub.max_data_pago
FROM (
  SELECT contato_id, MAX(data_pago) AS max_data_pago
  FROM public.pedidos
  WHERE status_pagamento = 'pago' AND data_pago IS NOT NULL
  GROUP BY contato_id
) sub
WHERE c.id = sub.contato_id;

-- 3) Trigger function — só avança a data, nunca regride
CREATE OR REPLACE FUNCTION public.trigger_update_ultima_compra()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status_pagamento = 'pago' AND NEW.data_pago IS NOT NULL AND NEW.contato_id IS NOT NULL THEN
    UPDATE public.contatos
    SET ultima_compra_em = NEW.data_pago,
        updated_at = NOW()
    WHERE id = NEW.contato_id
      AND (ultima_compra_em IS NULL OR ultima_compra_em < NEW.data_pago);
  END IF;
  RETURN NEW;
END;
$$;

-- 4) Trigger em pedidos
DROP TRIGGER IF EXISTS pedidos_update_ultima_compra ON public.pedidos;
CREATE TRIGGER pedidos_update_ultima_compra
  AFTER INSERT OR UPDATE OF status_pagamento, data_pago
  ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_update_ultima_compra();

-- 5) Index parcial: acelera filtro do n8n (apenas contatos elegíveis pra RMKT)
CREATE INDEX IF NOT EXISTS idx_contatos_ultima_compra
  ON public.contatos(ultima_compra_em);

NOTIFY pgrst, 'reload schema';

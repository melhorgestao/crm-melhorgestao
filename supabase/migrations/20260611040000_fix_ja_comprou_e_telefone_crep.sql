-- ============================================================================
-- 1) BUG ja_comprou: trigger só marcava cliente quando status_pagamento='pago'.
--    C-REP nunca chega lá (pagamento offline via REP) → sempre ficava false.
--    Nova regra: qualquer pedido criado (não cancelado) marca ja_comprou=true.
--
-- 2) REGRA C-REP: telefone do contato C-REP = telefone do representante responsável.
--    Backfill + trigger pra manter sincronizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) ja_comprou: backfill + novo trigger
-- ----------------------------------------------------------------------------

-- Backfill: qualquer contato com pedido (status != cancelado) vira cliente
UPDATE public.contatos c
   SET ja_comprou = true,
       data_cliente = COALESCE(c.data_cliente, NOW()),
       ultima_interacao = COALESCE(c.ultima_interacao, 'cliente'),
       updated_at = NOW()
 WHERE c.ja_comprou = false
   AND EXISTS (
     SELECT 1 FROM public.pedidos p
      WHERE p.contato_id = c.id
        AND COALESCE(p.status_pedido, '') != 'cancelado'
   );

-- Trigger refinado: dispara em INSERT (independente de pagamento)
-- e também em UPDATE de status_pagamento (compat com lógica antiga).
CREATE OR REPLACE FUNCTION public.trigger_set_ja_comprou()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL
     AND COALESCE(NEW.status_pedido, '') != 'cancelado' THEN
    UPDATE public.contatos
       SET ja_comprou = true,
           data_cliente = COALESCE(data_cliente, NOW()),
           ultima_interacao = COALESCE(ultima_interacao, 'cliente'),
           updated_at = NOW()
     WHERE id = NEW.contato_id
       AND ja_comprou = false;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS pedidos_set_ja_comprou ON public.pedidos;
CREATE TRIGGER pedidos_set_ja_comprou
  AFTER INSERT OR UPDATE OF status_pagamento, status_pedido
  ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_set_ja_comprou();

-- ----------------------------------------------------------------------------
-- 2) telefone C-REP = telefone do representante responsável
-- ----------------------------------------------------------------------------

-- Backfill: todo C-REP com representante recebe telefone do representante
UPDATE public.contatos c
   SET telefone = r.telefone,
       updated_at = NOW()
  FROM public.contatos r
 WHERE c.canal_origem = 'C-REP'
   AND c.representante_id = r.id
   AND r.telefone IS NOT NULL
   AND COALESCE(c.telefone, '') IS DISTINCT FROM r.telefone;

-- Trigger: mantém sincronizado em INSERT/UPDATE
CREATE OR REPLACE FUNCTION public.trigger_crep_telefone_do_rep()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rep_tel text;
BEGIN
  IF NEW.canal_origem = 'C-REP' AND NEW.representante_id IS NOT NULL THEN
    SELECT telefone INTO v_rep_tel
      FROM public.contatos
     WHERE id = NEW.representante_id;
    IF v_rep_tel IS NOT NULL THEN
      NEW.telefone := v_rep_tel;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS contatos_crep_telefone_rep ON public.contatos;
CREATE TRIGGER contatos_crep_telefone_rep
  BEFORE INSERT OR UPDATE OF canal_origem, representante_id
  ON public.contatos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_crep_telefone_do_rep();

-- ----------------------------------------------------------------------------
-- Conferência
-- ----------------------------------------------------------------------------
-- SELECT count(*) FILTER (WHERE c.canal_origem='C-REP' AND c.telefone IS NULL) AS crep_sem_tel,
--        count(*) FILTER (WHERE c.ja_comprou = false AND EXISTS(SELECT 1 FROM pedidos p WHERE p.contato_id=c.id)) AS clientes_sem_flag
--   FROM contatos c;

NOTIFY pgrst, 'reload schema';

-- Lock status after midnight - prevents changes to delivered orders and paid vendas

-- Add locked_at column to pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS locked_at timestamptz;

-- Add locked_at column to lancamentos_socios
ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS locked_at timestamptz;

-- Create function to lock pedidos delivered yesterday
CREATE OR REPLACE FUNCTION public.lock_yesterday_delivered_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.pedidos
  SET locked_at = now()
  WHERE status_pedido = 'entregue'
    AND locked_at IS NULL
    AND data < CURRENT_DATE;
END;
$$;

-- Create function to lock vendas paid yesterday
CREATE OR REPLACE FUNCTION public.lock_yesterday_paid_vendas()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.lancamentos_socios
  SET locked_at = now()
  WHERE tipo = 'VENDA'
    AND (status_pagamento = 'pago' OR status_pagamento IS NULL OR status_pagamento = '')
    AND locked_at IS NULL
    AND data < CURRENT_DATE;
END;
$$;

-- Create combined lock function
CREATE OR REPLACE FUNCTION public.perform_daily_lock()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedidos_locked integer;
  v_vendas_locked integer;
BEGIN
  -- Lock yesterday's delivered orders
  UPDATE public.pedidos
  SET locked_at = now()
  WHERE status_pedido = 'entregue'
    AND locked_at IS NULL
    AND data < CURRENT_DATE
  RETURNING count(*) INTO v_pedidos_locked;

  -- Lock yesterday's paid vendas
  UPDATE public.lancamentos_socios
  SET locked_at = now()
  WHERE tipo = 'VENDA'
    AND status_pagamento = 'pago'
    AND locked_at IS NULL
    AND data < CURRENT_DATE
  RETURNING count(*) INTO v_vendas_locked;

  RETURN json_build_object(
    'success', true,
    'pedidos_locked', v_pedidos_locked,
    'vendas_locked', v_vendas_locked
  );
END;
$$;
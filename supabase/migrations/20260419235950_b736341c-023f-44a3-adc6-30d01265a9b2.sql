ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS gateway_etiqueta text DEFAULT 'superfrete';
UPDATE public.pedidos SET gateway_etiqueta = 'superfrete' WHERE gateway_etiqueta IS NULL;
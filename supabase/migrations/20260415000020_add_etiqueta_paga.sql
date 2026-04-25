-- Add etiqueta_paga column to pedidos
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_paga BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN pedidos.etiqueta_paga IS 'Indica se a etiqueta foi paga no Super Frete';
-- Verificar e criar colunas para valor dofrete
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_valor NUMERIC(10,2);
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS shipping_price NUMERIC(10,2);
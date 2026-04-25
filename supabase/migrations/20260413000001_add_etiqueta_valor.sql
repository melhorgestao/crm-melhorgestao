-- Adicionar coluna etiqueta_valor para armazenar custo do frete
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_valor NUMERIC(10,2);
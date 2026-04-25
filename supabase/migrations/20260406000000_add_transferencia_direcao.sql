-- Add transferencia_direcao column to lancamentos_socios
ALTER TABLE lancamentos_socios ADD COLUMN IF NOT EXISTS transferencia_direcao TEXT;

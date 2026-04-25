-- ============================================================
-- White Label - Sócios dinâmicos via AdminPage
-- ============================================================
-- 1. Adicionar is_socio em perfis_usuario
-- 2. Backfill: quem tem socio_key V ou A → is_socio = true
-- 3. FinanceiroPage, PedidosPage buscam sócios do banco (não hardcoded)

BEGIN;

-- Nova coluna
ALTER TABLE perfis_usuario ADD COLUMN IF NOT EXISTS is_socio boolean DEFAULT false;

-- Backfill: admins existentes com socio_key viram sócios
UPDATE perfis_usuario SET is_socio = true WHERE socio_key IN ('V', 'A');

COMMIT;

-- =============================================
-- Migration: Logística - Sistema de Duas Etapas
-- Execute no Supabase SQL Editor
-- =============================================

-- 1. Adicionar coluna etiqueta_paga na tabela pedidos
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_paga BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN pedidos.etiqueta_paga IS 'Indica se a etiqueta foi paga no Super Frete';

-- 2. Verificar se tabela remetentes_uf existe e tem os campos necessários
-- (Execute separadamente se precisar criar a tabela)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'remetentes_uf') THEN
        CREATE TABLE remetentes_uf (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            uf VARCHAR(2) UNIQUE NOT NULL,
            cep_origem VARCHAR(8),
            cidade VARCHAR(100),
            bairro VARCHAR(100),
            endereco VARCHAR(255),
            numero VARCHAR(20),
            complemento VARCHAR(100),
            nome_remetente VARCHAR(255),
            contato_remetente VARCHAR(20),
            cpf VARCHAR(11),
            descricao_produto VARCHAR(255),
            valor_unitario DECIMAL(10,2),
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    END IF;
END $$;

-- 3. Verificar se produtos tem coluna peso
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM information_schema.columns 
        WHERE table_name = 'produtos' AND column_name = 'peso'
    ) THEN
        ALTER TABLE produtos ADD COLUMN peso INTEGER DEFAULT 300;
        COMMENT ON COLUMN produtos.peso IS 'Peso do produto em gramas';
    END IF;
END $$;

-- 4. Criar índices para performance (se não existirem)
CREATE INDEX IF NOT EXISTS idx_pedidos_status_rastreio ON pedidos(status_pedido) WHERE status_pedido = 'aguardando_rastreio';
CREATE INDEX IF NOT EXISTS idx_pedidos_modalidade ON pedidos(modalidade) WHERE modalidade != 'entrega_maos';
CREATE INDEX IF NOT EXISTS idx_pedidos_uf_postagem ON pedidos(uf_postagem);
CREATE INDEX IF NOT EXISTS idx_pedidos_etiqueta_paga ON pedidos(etiqueta_paga) WHERE etiqueta_paga = false;

-- 5. Confirmar alterações
SELECT 
    'pedidos.etiqueta_paga' as column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'pedidos' AND column_name = 'etiqueta_paga';

SELECT 'Migration executada com sucesso!' as result;
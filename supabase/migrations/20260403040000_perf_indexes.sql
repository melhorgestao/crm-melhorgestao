-- CRITICAL: Enable pg_trgm for fast text search (ilike %...%)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Indexes for 'contatos' table
-- GIN index for fast substring search on name
CREATE INDEX IF NOT EXISTS idx_contatos_nome_trgm ON contatos USING gin (nome gin_trgm_ops);
-- Standard indexes for exact/prefix matches
CREATE INDEX IF NOT EXISTS idx_contatos_telefone ON contatos (telefone);
CREATE INDEX IF NOT EXISTS idx_contatos_cpf ON contatos (cpf);
CREATE INDEX IF NOT EXISTS idx_contatos_created_at ON contatos (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contatos_canal_origem ON contatos (canal_origem);

-- Indexes for 'financeiro' table
CREATE INDEX IF NOT EXISTS idx_financeiro_data ON financeiro ("data" DESC);
CREATE INDEX IF NOT EXISTS idx_financeiro_canal ON financeiro (canal);
CREATE INDEX IF NOT EXISTS idx_financeiro_tipo ON financeiro (tipo);
CREATE INDEX IF NOT EXISTS idx_financeiro_composite ON financeiro (tipo, canal, "data");

-- Indexes for 'pedidos' table
CREATE INDEX IF NOT EXISTS idx_pedidos_contato_id ON pedidos (contato_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_status_pagamento ON pedidos (status_pagamento);
CREATE INDEX IF NOT EXISTS idx_pedidos_data ON pedidos ("data" DESC);

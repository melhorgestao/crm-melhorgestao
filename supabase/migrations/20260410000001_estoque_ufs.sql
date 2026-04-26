-- Migration: tabela estoque_ufs para UFs dinâmicas
-- EXECUTAR MANUALMENTE NO SQL EDITOR DO SUPABASE

-- 1. Criar tabela
CREATE TABLE IF NOT EXISTS estoque_ufs (
  uf TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Habilitar RLS
ALTER TABLE estoque_ufs ENABLE ROW LEVEL SECURITY;

-- 3. Policy de leitura pública (autenticados)
CREATE POLICY "Authenticated can read estoque_ufs" ON estoque_ufs
  FOR SELECT TO authenticated USING (true);

-- 4. Policy de inserção (autenticados)
CREATE POLICY "Authenticated can insert estoque_ufs" ON estoque_ufs
  FOR INSERT TO authenticated WITH CHECK (true);

-- 5. Policy de deleção (autenticados)
CREATE POLICY "Authenticated can delete estoque_ufs" ON estoque_ufs
  FOR DELETE TO authenticated USING (true);

-- 6. Seed: migrar UFs existentes conhecidas
INSERT INTO estoque_ufs (uf) VALUES ('SC'), ('RS'), ('SP'), ('GO')
ON CONFLICT (uf) DO NOTHING;

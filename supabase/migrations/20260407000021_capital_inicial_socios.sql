-- Migration: Inserir capital inicial dos sócios V e A
-- Substitui o hardcoded +49/+942 do frontend por registros reais no banco

-- Sócio V: Capital inicial R$ 49,00
INSERT INTO lancamentos_socios (id, socio, tipo, valor, descricao, status_pagamento, criado_por, realizado, data)
VALUES (
  gen_random_uuid(),
  'V',
  'CAPITAL_INICIAL',
  49.00,
  'Capital inicial - Sócio V',
  '-',
  'Sistema',
  true,
  '2024-01-01'
)
ON CONFLICT DO NOTHING;

-- Sócio A: Capital inicial R$ 942,00
INSERT INTO lancamentos_socios (id, socio, tipo, valor, descricao, status_pagamento, criado_por, realizado, data)
VALUES (
  gen_random_uuid(),
  'A',
  'CAPITAL_INICIAL',
  942.00,
  'Capital inicial - Sócio A',
  '-',
  'Sistema',
  true,
  '2024-01-01'
)
ON CONFLICT DO NOTHING;

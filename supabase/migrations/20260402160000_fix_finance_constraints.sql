-- 1. UPDATE lancamentos_socios CONSTRAINTS
ALTER TABLE lancamentos_socios 
  DROP CONSTRAINT IF EXISTS lancamentos_socios_socio_check,
  DROP CONSTRAINT IF EXISTS lancamentos_socios_tipo_check,
  DROP CONSTRAINT IF EXISTS lancamentos_socios_status_pagamento_check;

ALTER TABLE lancamentos_socios 
  ADD CONSTRAINT lancamentos_socios_socio_check 
    CHECK (socio IN ('V', 'A', 'P')),
  ADD CONSTRAINT lancamentos_socios_tipo_check 
    CHECK (tipo IN ('VENDA', 'ADS', 'ETIQUETA', 'MATERIAL', 'LOGISTICA', 'TRANSFERENCIA', 'LUCRO')),
  ADD CONSTRAINT lancamentos_socios_status_pagamento_check 
    CHECK (status_pagamento IN ('pago', 'pendente', '-'));

-- 2. UPDATE financeiro CONSTRAINTS (if needed)
ALTER TABLE financeiro 
  DROP CONSTRAINT IF EXISTS financeiro_tipo_check;

ALTER TABLE financeiro 
  ADD CONSTRAINT financeiro_tipo_check 
    CHECK (tipo IN ('receita', 'despesa', 'receita_pendente', 'LUCRO', 'TRANSFERENCIA'));

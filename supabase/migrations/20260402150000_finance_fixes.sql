-- 1. UPDATE status_pagamento constraint to allow '-'
ALTER TABLE lancamentos_socios 
  DROP CONSTRAINT IF EXISTS lancamentos_socios_status_pagamento_check;

ALTER TABLE lancamentos_socios 
  ADD CONSTRAINT lancamentos_socios_status_pagamento_check 
    CHECK (status_pagamento IN ('pago', 'pendente', '-'));

-- 2. INSERT manual balance adjustment removed as requested.

-- ============================================================================
-- Converte primeira_venda_em e ultima_venda_em de DATE → TIMESTAMPTZ.
--
-- Por quê?
--  - Hoje cron usa data_cliente (timestamptz) com comparações
--    'data_cliente < NOW() - X days'. Se queremos no futuro trocar pra
--    primeira_venda_em mantendo o mesmo comportamento, primeira_venda_em
--    precisa ser timestamptz.
--  - Crons existentes que comparam ultima_venda_em < NOW() - X days
--    continuam funcionando (cast implícito da date pra timestamptz já era
--    feito antes; agora fica direto).
--
-- AÇÕES (todas idempotentes, com USING explícito pra cast 100% seguro):
--  1) ALTER COLUMN primeira_venda_em → TIMESTAMPTZ (preserva valores)
--  2) ALTER COLUMN ultima_venda_em   → TIMESTAMPTZ (preserva valores)
--  3) Recria trigger trigger_contato_virou_cliente usando NEW.created_at
--     (timestamptz nativo do pedido — mais preciso que NEW.data::date)
--  4) Atualiza trigger_sync_data_cliente (sem cast desnecessário)
--  5) Re-backfill: usa MIN/MAX(created_at) dos pedidos
--
-- COMPATIBILIDADE:
--  - Queries antigas que faziam primeira_venda_em < CURRENT_DATE - X
--    continuam funcionando (cast implícito timestamptz → date).
--  - Queries que faziam primeira_venda_em > '2026-01-01'::date também (idem).
--  - Trigger sync_data_cliente continua copiando o valor.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) DROP triggers que dependem das colunas (recriados ao final)
--    Postgres rejeita ALTER COLUMN TYPE se a coluna é usada em qualquer
--    trigger definition. Removemos antes, recriamos depois.
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_sync_data_cliente       ON public.contatos;
DROP TRIGGER IF EXISTS trg_contato_virou_cliente   ON public.pedidos;

-- ----------------------------------------------------------------------------
-- 1) Converte primeira_venda_em DATE → TIMESTAMPTZ
--    USING explícito: meia-noite no TZ Sao_Paulo (preserva o dia visualmente)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_tipo text;
BEGIN
  SELECT data_type INTO v_tipo
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'contatos' AND column_name = 'primeira_venda_em';

  IF v_tipo = 'date' THEN
    ALTER TABLE public.contatos
      ALTER COLUMN primeira_venda_em TYPE timestamptz
      USING primeira_venda_em::timestamp AT TIME ZONE 'America/Sao_Paulo';
    RAISE NOTICE 'primeira_venda_em convertida pra timestamptz.';
  ELSE
    RAISE NOTICE 'primeira_venda_em já é %, pulando ALTER.', v_tipo;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2) Converte ultima_venda_em DATE → TIMESTAMPTZ
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_tipo text;
BEGIN
  SELECT data_type INTO v_tipo
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'contatos' AND column_name = 'ultima_venda_em';

  IF v_tipo = 'date' THEN
    ALTER TABLE public.contatos
      ALTER COLUMN ultima_venda_em TYPE timestamptz
      USING ultima_venda_em::timestamp AT TIME ZONE 'America/Sao_Paulo';
    RAISE NOTICE 'ultima_venda_em convertida pra timestamptz.';
  ELSE
    RAISE NOTICE 'ultima_venda_em já é %, pulando ALTER.', v_tipo;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3) Trigger contato_virou_cliente — usa created_at do pedido (timestamptz)
--    Mantém comportamento correto pra:
--    • Pedidos novos (trigger AFTER INSERT pega created_at = NOW())
--    • Pedidos retroativos com data manual: created_at ainda é NOW() do
--      insert; preferimos a precisão de quando foi REGISTRADO no sistema.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_contato_virou_cliente()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ts timestamptz := COALESCE(NEW.created_at, NOW());
BEGIN
  IF NEW.contato_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status_pedido = 'cancelado' THEN RETURN NEW; END IF;

  UPDATE public.contatos
     SET ja_comprou                = true,
         ultima_interacao          = 'cliente',
         data_cliente              = COALESCE(data_cliente, v_ts),
         data_em_fechamento        = NULL,
         data_aguardando_pagamento = NULL,
         primeira_venda_em         = LEAST(COALESCE(primeira_venda_em, v_ts), v_ts),
         ultima_venda_em           = GREATEST(COALESCE(ultima_venda_em, v_ts), v_ts),
         updated_at                = NOW()
   WHERE id = NEW.contato_id;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_contato_virou_cliente ON public.pedidos;
CREATE TRIGGER trg_contato_virou_cliente
  AFTER INSERT ON public.pedidos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_contato_virou_cliente();

-- ----------------------------------------------------------------------------
-- 4) Trigger sync_data_cliente — sem cast (ambas são timestamptz agora)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_sync_data_cliente()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.primeira_venda_em IS NOT NULL
     AND NEW.primeira_venda_em IS DISTINCT FROM OLD.primeira_venda_em THEN
    NEW.data_cliente := NEW.primeira_venda_em;
  END IF;
  RETURN NEW;
END $$;

-- Recria trigger (foi dropado no passo 0 pra liberar o ALTER COLUMN)
CREATE TRIGGER trg_sync_data_cliente
  BEFORE UPDATE OF primeira_venda_em ON public.contatos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_sync_data_cliente();

-- ----------------------------------------------------------------------------
-- 5) Backfill: alinha primeira/ultima_venda_em + data_cliente usando
--    created_at REAL dos pedidos (precisão timestamptz)
-- ----------------------------------------------------------------------------
UPDATE public.contatos c
   SET primeira_venda_em = sub.min_ts,
       ultima_venda_em   = sub.max_ts,
       data_cliente      = COALESCE(c.data_cliente, sub.min_ts),
       ja_comprou        = true,
       updated_at        = NOW()
  FROM (
    SELECT contato_id,
           MIN(created_at) AS min_ts,
           MAX(created_at) AS max_ts
      FROM public.pedidos
     WHERE contato_id IS NOT NULL AND status_pedido != 'cancelado'
     GROUP BY contato_id
  ) sub
 WHERE c.id = sub.contato_id
   AND (
        c.primeira_venda_em IS NULL
     OR c.ultima_venda_em IS NULL
     OR c.primeira_venda_em > sub.min_ts
     OR c.ultima_venda_em   < sub.max_ts
   );

NOTIFY pgrst, 'reload schema';

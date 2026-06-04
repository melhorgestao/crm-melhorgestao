-- ============================================================================
-- Feature: Automação de envio do link de rastreio SuperFrete via WhatsApp
-- Fluxo:
--   1. superfrete-sync (edge function) extrai a URL pública de rastreio do
--      SuperFrete e salva em link_rastreio assim que o pedido vira 'postado'.
--   2. n8n monitora pedidos com link_rastreio preenchido e rastreio_enviado_em
--      nulo, envia via Evolution e marca rastreio_enviado_em = NOW().
-- ============================================================================

ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS link_rastreio TEXT,
  ADD COLUMN IF NOT EXISTS rastreio_enviado_em TIMESTAMPTZ;

-- Índice parcial: torna a query do n8n "pendentes de envio" instantânea.
CREATE INDEX IF NOT EXISTS idx_pedidos_rastreio_pendente_envio
  ON public.pedidos(status_pedido)
  WHERE status_pedido = 'postado'
    AND rastreio_enviado_em IS NULL
    AND link_rastreio IS NOT NULL;

COMMENT ON COLUMN public.pedidos.link_rastreio IS
  'URL pública SuperFrete para o cliente acompanhar a entrega. Preenchida pela edge function superfrete-sync.';

COMMENT ON COLUMN public.pedidos.rastreio_enviado_em IS
  'Timestamp do envio do link de rastreio ao cliente via WhatsApp. NULL = ainda não enviado.';

NOTIFY pgrst, 'reload schema';

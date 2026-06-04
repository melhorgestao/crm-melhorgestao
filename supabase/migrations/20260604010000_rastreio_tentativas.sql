-- ============================================================================
-- Feature: Contador de tentativas pro envio de rastreio
-- Objetivo:
--   1. Suprime spam de ALERTA quando Evolution cai por minutos (Cloudflare 522)
--   2. Alerta só dispara a partir da 3ª tentativa consecutiva sem sucesso
--   3. Após 5 tentativas, o pedido sai do loop de retry (filtro do índice)
--
-- Fluxo na n8n:
--   SEND MSG EVO falhou? → INCREMENT TENTATIVA (RPC) → IF tentativas >= 3?
--     true  → ALERTA FALHA (te notifica)
--     false → silencioso, próximo ciclo tenta de novo
-- ============================================================================

ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS rastreio_tentativas INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.pedidos.rastreio_tentativas IS
  'Contador de tentativas de envio do link de rastreio via WhatsApp. Incrementado a cada falha. Pedido sai do retry quando >= 5.';

-- RPC pra incrementar contador atomicamente e devolver novo valor.
-- SECURITY DEFINER pra rodar com privilégio do owner (necessário se RLS estiver ativa).
CREATE OR REPLACE FUNCTION public.incrementar_tentativa_rastreio(pedido_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  novo_count INTEGER;
BEGIN
  UPDATE public.pedidos
  SET rastreio_tentativas = COALESCE(rastreio_tentativas, 0) + 1
  WHERE id = pedido_id
  RETURNING rastreio_tentativas INTO novo_count;
  RETURN COALESCE(novo_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.incrementar_tentativa_rastreio(UUID)
  TO authenticated, anon, service_role;

-- Recria índice parcial pra excluir pedidos esgotados (>=5 tentativas).
-- Resultado: query do n8n é instantânea mesmo com milhares de pedidos.
DROP INDEX IF EXISTS idx_pedidos_rastreio_pendente_envio;
CREATE INDEX idx_pedidos_rastreio_pendente_envio
  ON public.pedidos(status_pedido)
  WHERE status_pedido = 'postado'
    AND rastreio_enviado_em IS NULL
    AND link_rastreio IS NOT NULL
    AND rastreio_tentativas < 5;

NOTIFY pgrst, 'reload schema';

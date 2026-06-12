-- ============================================================================
-- Trigger event-driven: quando pedido vira status_pedido='postado' E
-- link_rastreio é preenchido, dispara webhook pra n8n processar rastreio na hora.
-- Substitui o polling 10/10min — o Schedule continua como fallback (1h) caso
-- algum webhook falhe.
--
-- Requer extensão pg_net (já habilitada por padrão no Supabase).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

-- URL do webhook configurada via configuracoes (key='n8n_rastreio_webhook_url')
-- para não hardcodar. Default: produção atual.
INSERT INTO public.configuracoes (chave, valor)
  VALUES ('n8n_rastreio_webhook_url', 'https://n8n.melhorgestao.online/webhook/rastreio-postado')
  ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.trigger_notify_rastreio_n8n()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_url     text;
  v_should  boolean;
BEGIN
  -- Dispara apenas quando ENTRA em "postado com link" pela primeira vez:
  --   - status novo é 'postado' E link_rastreio NOT NULL
  --   - E ainda não foi enviado (rastreio_enviado_em IS NULL)
  --   - E mudou alguma das colunas relevantes (evita loop em outros UPDATEs)
  v_should := NEW.status_pedido = 'postado'
              AND NEW.link_rastreio IS NOT NULL
              AND NEW.rastreio_enviado_em IS NULL
              AND (
                COALESCE(OLD.status_pedido,'') IS DISTINCT FROM NEW.status_pedido
                OR COALESCE(OLD.link_rastreio,'') IS DISTINCT FROM COALESCE(NEW.link_rastreio,'')
              );

  IF NOT v_should THEN RETURN NEW; END IF;

  SELECT valor INTO v_url
    FROM public.configuracoes
   WHERE chave = 'n8n_rastreio_webhook_url'
   LIMIT 1;

  IF v_url IS NULL OR v_url = '' THEN
    RAISE NOTICE 'n8n_rastreio_webhook_url não configurada — webhook ignorado';
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    body    := jsonb_build_object('pedido_id', NEW.id),
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS pedidos_notify_rastreio_n8n ON public.pedidos;
CREATE TRIGGER pedidos_notify_rastreio_n8n
  AFTER INSERT OR UPDATE OF status_pedido, link_rastreio
  ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_notify_rastreio_n8n();

NOTIFY pgrst, 'reload schema';

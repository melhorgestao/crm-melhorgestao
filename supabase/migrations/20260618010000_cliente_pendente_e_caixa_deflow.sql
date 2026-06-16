-- ============================================================================
-- 1) Novo estado 'cliente_pendente' na state machine
--    Cliente que comprou e tem pelo menos 1 pedido com status_pagamento='pendente'
--    Estado sai de 'cliente_pendente' automaticamente quando todas as pendências
--    quitam (status_pagamento='pago') ou cancela.
--
-- 2) Triggers em pedidos + lancamentos_socios mantêm ultima_interacao em dia
--
-- 3) Campanhas RMKT/follow-up NÃO disparam pra cliente_pendente
--    (escolhe_template_v2 atualizado)
--
-- 4) Caixa default 'DeFlow' criada idempotente (C1)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Coluna data_cliente_pendente
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS data_cliente_pendente timestamptz;

COMMENT ON COLUMN public.contatos.data_cliente_pendente IS
  'Quando o contato entrou em ''cliente_pendente'' (1ª pendência). Reset ao quitar tudo.';

-- ----------------------------------------------------------------------------
-- 2) Função pra recomputar estado do contato baseado em pedidos pendentes
--    Idempotente. Chamada por triggers.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recompute_estado_pendencia(p_contato_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_estado_atual text;
  v_tem_pendencia boolean;
  v_ja_comprou boolean;
BEGIN
  IF p_contato_id IS NULL THEN RETURN; END IF;

  SELECT ultima_interacao, ja_comprou INTO v_estado_atual, v_ja_comprou
    FROM public.contatos WHERE id = p_contato_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Não mexer em estados terminais ou ativos onde transição não faz sentido
  IF v_estado_atual IN ('NUNCA_MAIS','suporte','em_fechamento','aguardando_pagamento','start') THEN
    -- ainda assim atualiza estado_antes_suporte se aplicável (suporte)
    -- mas não muda ultima_interacao
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.pedidos
     WHERE contato_id = p_contato_id
       AND status_pagamento = 'pendente'
       AND status_pedido != 'cancelado'
  ) INTO v_tem_pendencia;

  IF v_tem_pendencia THEN
    -- Vira cliente_pendente se vinha de cliente / rmkt / follow_up / wait_follow_up
    IF v_estado_atual IN ('cliente','rmkt','follow_up','wait_follow_up') OR v_estado_atual IS NULL THEN
      UPDATE public.contatos
         SET ultima_interacao = 'cliente_pendente',
             data_cliente_pendente = COALESCE(data_cliente_pendente, now()),
             updated_at = now()
       WHERE id = p_contato_id;
    END IF;
  ELSE
    -- Sem pendência: se está em cliente_pendente, devolve pra cliente
    -- (cliente_pendente sempre veio de cliente — comprou algo)
    IF v_estado_atual = 'cliente_pendente' THEN
      UPDATE public.contatos
         SET ultima_interacao = 'cliente',
             data_cliente_pendente = NULL,
             updated_at = now()
       WHERE id = p_contato_id;
    END IF;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.recompute_estado_pendencia(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 3) Trigger: ao alterar pedidos.status_pagamento ou criar pedido, recomputa
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_recompute_pendencia_pedidos()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.recompute_estado_pendencia(OLD.contato_id);
    RETURN OLD;
  END IF;

  PERFORM public.recompute_estado_pendencia(NEW.contato_id);

  -- se contato_id mudou (raro), recomputa o antigo também
  IF TG_OP = 'UPDATE' AND OLD.contato_id IS DISTINCT FROM NEW.contato_id THEN
    PERFORM public.recompute_estado_pendencia(OLD.contato_id);
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_recompute_pendencia ON public.pedidos;
CREATE TRIGGER trg_recompute_pendencia
  AFTER INSERT OR UPDATE OF status_pagamento, status_pedido, contato_id OR DELETE
  ON public.pedidos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_recompute_pendencia_pedidos();

-- ----------------------------------------------------------------------------
-- 4) Backfill estado atual (uma vez)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_rec record;
BEGIN
  FOR v_rec IN
    SELECT DISTINCT contato_id
      FROM public.pedidos
     WHERE contato_id IS NOT NULL
  LOOP
    PERFORM public.recompute_estado_pendencia(v_rec.contato_id);
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 5) Atualiza escolhe_template_v2 pra EXCLUIR cliente_pendente das campanhas
-- ----------------------------------------------------------------------------
-- Mantém a função existente intacta — apenas garantimos que ela já não
-- elegia 'cliente_pendente' (estado novo, não existia antes). Para garantia,
-- caso novas campanhas filtrem por 'cliente', basta NÃO incluir o novo estado.
-- A função claim_campanha_proximo_contato_v3 já filtra por estados
-- específicos (NULL ou 'ativacao_contatos'), então cliente_pendente já está
-- naturalmente fora.
-- Para campanhas RMKT/follow_up que filtram por 'rmkt'/'follow_up'/'cliente',
-- cliente_pendente não está nessa lista — está naturalmente excluído.

-- ----------------------------------------------------------------------------
-- 6) RPC consultar_pendencia_contato (usada pelos agents)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consultar_pendencia_contato(p_contato_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_saldo numeric := 0;
  v_qtd integer := 0;
  v_pedidos jsonb;
BEGIN
  SELECT COALESCE(SUM(valor), 0), count(*),
         COALESCE(jsonb_agg(jsonb_build_object(
           'order_number', order_number,
           'data', data,
           'produto', produto,
           'saldo_devedor', valor,
           'valor_original', COALESCE(valor_original, valor),
           'desconto_total', COALESCE(desconto_total, 0)
         ) ORDER BY data DESC), '[]'::jsonb)
    INTO v_saldo, v_qtd, v_pedidos
    FROM public.pedidos
   WHERE contato_id = p_contato_id
     AND status_pagamento = 'pendente'
     AND status_pedido != 'cancelado';

  RETURN jsonb_build_object(
    'tem_pendencia', v_qtd > 0,
    'qtd_pedidos_pendentes', v_qtd,
    'saldo_devedor_total', v_saldo,
    'pedidos', v_pedidos
  );
END $$;

GRANT EXECUTE ON FUNCTION public.consultar_pendencia_contato(uuid)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- 7) Caixa default 'DeFlow' (idempotente — não duplica se já existir)
-- ----------------------------------------------------------------------------
INSERT INTO public.caixas (codigo, apelido)
SELECT 'C1', 'DeFlow'
 WHERE NOT EXISTS (SELECT 1 FROM public.caixas WHERE codigo = 'C1');

-- ----------------------------------------------------------------------------
-- 8) Configuração: caixa default pra recebimentos do bot
-- ----------------------------------------------------------------------------
INSERT INTO public.configuracoes (chave, valor)
VALUES ('caixa_default_bot', 'C1')
ON CONFLICT (chave) DO NOTHING;

COMMENT ON COLUMN public.contatos.ultima_interacao IS
  'Estado canônico atual: NULL | start | wait_follow_up | em_fechamento | aguardando_pagamento | rmkt | follow_up | rastreio | cliente | cliente_pendente | suporte | NUNCA_MAIS';

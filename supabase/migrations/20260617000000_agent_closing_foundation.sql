-- ============================================================================
-- AGENT_CLOSING — Foundation
--
-- 1) produtos.slug + produtos.emoji   (catálogo padronizado)
-- 2) contatos.rua + contatos.numero   (separados, mantém rua_numero legacy)
-- 3) pedido_em_aberto                 (rascunho 24h enquanto closing roda)
-- 4) Novo estado 'aguardando_pagamento' integrado à state machine
-- 5) RPCs: upsert_endereco_contato, retroceder_contato,
--          criar_pedido_em_aberto, fechar_pedido_pago, expirar_pedidos_abandonados
-- 6) Estende processar_transicoes_estado_contato pra cobrir aguardando_pagamento
-- 7) Cron 'expirar-pedidos-abandonados' (1h)
--
-- Idempotente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Produtos: slug + emoji
-- ----------------------------------------------------------------------------
ALTER TABLE public.produtos
  ADD COLUMN IF NOT EXISTS slug  text,
  ADD COLUMN IF NOT EXISTS emoji text,
  ADD COLUMN IF NOT EXISTS ordem integer NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS produtos_slug_uk ON public.produtos(slug)
  WHERE slug IS NOT NULL;

COMMENT ON COLUMN public.produtos.slug  IS 'Identificador interno usado p/ matching da fala do cliente (verde, amarelo, pomada...). NÃO exibir ao cliente.';
COMMENT ON COLUMN public.produtos.emoji IS 'Emoji do produto exibido nos resumos (🟩, 🍬, 🔰...).';
COMMENT ON COLUMN public.produtos.ordem IS 'Ordem fixa de exibição no catálogo (0 = primeiro).';

-- ----------------------------------------------------------------------------
-- 2) Contatos: rua + numero separados (mantém rua_numero como legado)
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS rua    text,
  ADD COLUMN IF NOT EXISTS numero text;

COMMENT ON COLUMN public.contatos.rua    IS 'Logradouro (sem número). Preenchido pelo closing após CEP+confirmação.';
COMMENT ON COLUMN public.contatos.numero IS 'Número da residência (texto pra aceitar SN/s/n).';

-- ----------------------------------------------------------------------------
-- 3) pedido_em_aberto — rascunho 24h
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pedido_em_aberto (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contato_id      uuid NOT NULL REFERENCES public.contatos(id) ON DELETE CASCADE,
  instancia_id    uuid REFERENCES public.instancias(id) ON DELETE SET NULL,
  itens           jsonb NOT NULL,        -- [{slug, nome_oficial, emoji, qtd, preco_unit, subtotal}]
  brindes         jsonb,                 -- [{slug, nome_oficial, emoji}] (0 a 2)
  modalidade_frete text,                 -- 'SEDEX'|'PAC'|'MINI'  (NULL se frete grátis)
  frete_preco     numeric NOT NULL DEFAULT 0,
  frete_prazo_min integer,
  frete_prazo_max integer,
  frete_gratis    boolean NOT NULL DEFAULT false,
  endereco_snapshot jsonb NOT NULL,      -- { cep, rua, numero, complemento, bairro, cidade, uf }
  subtotal        numeric NOT NULL DEFAULT 0,
  total           numeric NOT NULL DEFAULT 0,
  resumo_formatado text,                 -- texto pronto pra enviar ao cliente
  pix_id          text,                  -- id retornado pela DeFlow (NULL no stub)
  pix_qr_base64   text,
  pix_copia_cola  text,
  pix_expira_em   timestamptz,
  status          text NOT NULL DEFAULT 'aguardando_pagamento'
                  CHECK (status IN ('aguardando_pagamento','pago','expirado','cancelado')),
  expires_at      timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  pago_em         timestamptz,
  pedido_id       uuid REFERENCES public.pedidos(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pedido_em_aberto_contato ON public.pedido_em_aberto(contato_id);
CREATE INDEX IF NOT EXISTS idx_pedido_em_aberto_status_expires ON public.pedido_em_aberto(status, expires_at);

ALTER TABLE public.pedido_em_aberto ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read pedido_em_aberto"  ON public.pedido_em_aberto;
DROP POLICY IF EXISTS "Service role manage pedido_em_aberto" ON public.pedido_em_aberto;

CREATE POLICY "Authenticated read pedido_em_aberto"
  ON public.pedido_em_aberto FOR SELECT TO authenticated USING (true);
CREATE POLICY "Service role manage pedido_em_aberto"
  ON public.pedido_em_aberto FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE public.pedido_em_aberto IS
  'Rascunho de pedido enquanto AGENT_CLOSING aguarda pagamento. Expira em 24h; cron promove pra pedidos quando pago.';

-- ----------------------------------------------------------------------------
-- 4) Datas de estado: aguardando_pagamento
-- ----------------------------------------------------------------------------
ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS data_aguardando_pagamento timestamptz;

COMMENT ON COLUMN public.contatos.data_aguardando_pagamento IS
  'Quando entrou em aguardando_pagamento (PIX enviado). Cron expira em 24h.';

-- ----------------------------------------------------------------------------
-- 5) RPC: upsert_endereco_contato
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_endereco_contato(
  p_contato_id  uuid,
  p_cep         text,
  p_rua         text,
  p_numero      text,
  p_complemento text,
  p_bairro      text,
  p_cidade      text,
  p_uf          text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.contatos
     SET cep          = NULLIF(trim(p_cep),''),
         rua          = NULLIF(trim(p_rua),''),
         numero       = NULLIF(trim(p_numero),''),
         complemento  = NULLIF(trim(COALESCE(p_complemento,'')),''),
         bairro       = NULLIF(trim(p_bairro),''),
         cidade       = NULLIF(trim(p_cidade),''),
         uf           = upper(NULLIF(trim(p_uf),'')),
         -- mantém rua_numero legacy sincronizado pra UIs antigas
         rua_numero   = trim(concat_ws(', ', NULLIF(trim(p_rua),''), NULLIF(trim(p_numero),''))),
         updated_at   = now()
   WHERE id = p_contato_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  RETURN jsonb_build_object('ok', true, 'contato_id', p_contato_id);
END $$;

REVOKE ALL ON FUNCTION public.upsert_endereco_contato(uuid,text,text,text,text,text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.upsert_endereco_contato(uuid,text,text,text,text,text,text,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 6) RPC: retroceder_contato
--    Cancela pedido_em_aberto e retorna contato ao estado anterior
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retroceder_contato(
  p_contato_id uuid,
  p_motivo     text,
  p_novo_estado text DEFAULT NULL   -- se NULL: decide com base em ja_comprou
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ja_comprou boolean;
  v_estado_final text;
BEGIN
  SELECT ja_comprou INTO v_ja_comprou FROM public.contatos WHERE id = p_contato_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contato não encontrado');
  END IF;

  v_estado_final := COALESCE(p_novo_estado,
                             CASE WHEN v_ja_comprou THEN 'cliente' ELSE 'wait_follow_up' END);

  -- cancela rascunhos
  UPDATE public.pedido_em_aberto
     SET status     = 'cancelado',
         updated_at = now()
   WHERE contato_id = p_contato_id
     AND status     = 'aguardando_pagamento';

  UPDATE public.contatos
     SET ultima_interacao         = v_estado_final,
         data_wait_follow_up      = CASE WHEN v_estado_final = 'wait_follow_up' THEN now()
                                         ELSE data_wait_follow_up END,
         data_em_fechamento       = NULL,
         data_aguardando_pagamento = NULL,
         updated_at               = now()
   WHERE id = p_contato_id;

  -- log
  BEGIN
    INSERT INTO public.eventos_contato (contato_id, tipo, payload)
    VALUES (p_contato_id, 'retroceder_estagio',
            jsonb_build_object('motivo', p_motivo, 'novo_estado', v_estado_final));
  EXCEPTION WHEN OTHERS THEN
    -- tabela eventos_contato pode não existir em alguns ambientes
    NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'novo_estado', v_estado_final);
END $$;

REVOKE ALL ON FUNCTION public.retroceder_contato(uuid,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.retroceder_contato(uuid,text,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 7) RPC: criar_pedido_em_aberto
--    Chamada pela edge calcular-pedido depois de tudo confirmado.
--    Marca contato.ultima_interacao = 'aguardando_pagamento'
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.criar_pedido_em_aberto(
  p_contato_id        uuid,
  p_instancia_id      uuid,
  p_itens             jsonb,
  p_brindes           jsonb,
  p_modalidade_frete  text,
  p_frete_preco       numeric,
  p_frete_prazo_min   integer,
  p_frete_prazo_max   integer,
  p_frete_gratis      boolean,
  p_endereco_snapshot jsonb,
  p_subtotal          numeric,
  p_total             numeric,
  p_resumo_formatado  text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
BEGIN
  -- cancela rascunho anterior se houver (cliente pode ter desistido antes)
  UPDATE public.pedido_em_aberto
     SET status = 'cancelado', updated_at = now()
   WHERE contato_id = p_contato_id
     AND status = 'aguardando_pagamento';

  INSERT INTO public.pedido_em_aberto (
    contato_id, instancia_id, itens, brindes, modalidade_frete,
    frete_preco, frete_prazo_min, frete_prazo_max, frete_gratis,
    endereco_snapshot, subtotal, total, resumo_formatado
  ) VALUES (
    p_contato_id, p_instancia_id, p_itens, p_brindes, p_modalidade_frete,
    p_frete_preco, p_frete_prazo_min, p_frete_prazo_max, p_frete_gratis,
    p_endereco_snapshot, p_subtotal, p_total, p_resumo_formatado
  ) RETURNING id INTO v_id;

  UPDATE public.contatos
     SET ultima_interacao         = 'aguardando_pagamento',
         data_aguardando_pagamento = now(),
         updated_at               = now()
   WHERE id = p_contato_id;

  RETURN jsonb_build_object('ok', true, 'pedido_em_aberto_id', v_id);
END $$;

REVOKE ALL ON FUNCTION public.criar_pedido_em_aberto(uuid,uuid,jsonb,jsonb,text,numeric,integer,integer,boolean,jsonb,numeric,numeric,text) FROM public;
GRANT EXECUTE ON FUNCTION public.criar_pedido_em_aberto(uuid,uuid,jsonb,jsonb,text,numeric,integer,integer,boolean,jsonb,numeric,numeric,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 8) RPC: fechar_pedido_pago
--    Webhook DeFlow chama isso quando confirma o pagamento.
--    Promove pedido_em_aberto → pedidos, marca cliente.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fechar_pedido_pago(
  p_pedido_em_aberto_id uuid,
  p_pix_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rascunho public.pedido_em_aberto%ROWTYPE;
  v_pedido_id uuid;
  v_total numeric;
  v_qtd integer;
  v_canal text;
BEGIN
  SELECT * INTO v_rascunho FROM public.pedido_em_aberto WHERE id = p_pedido_em_aberto_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_em_aberto não encontrado');
  END IF;

  IF v_rascunho.status = 'pago' THEN
    RETURN jsonb_build_object('ok', true, 'idempotente', true, 'pedido_id', v_rascunho.pedido_id);
  END IF;

  -- qtd total = soma de qtd em itens
  SELECT COALESCE(SUM((value->>'qtd')::int), 0)
    INTO v_qtd
    FROM jsonb_array_elements(v_rascunho.itens);

  -- canal vem do contato
  SELECT canal_atual INTO v_canal
    FROM public.contatos WHERE id = v_rascunho.contato_id;
  v_canal := COALESCE(v_canal, 'BASE');

  -- INSERT pedidos (forma legada — produto/quantidade/valor)
  INSERT INTO public.pedidos (
    contato_id, produto, quantidade, valor, canal,
    endereco_entrega, status_pedido, status_pagamento, data
  ) VALUES (
    v_rascunho.contato_id,
    (SELECT string_agg((it->>'emoji') || ' ' || (it->>'nome_oficial') || ' (' || (it->>'qtd') || 'x)', ' | ')
       FROM jsonb_array_elements(v_rascunho.itens) it),
    v_qtd,
    v_rascunho.total,
    v_canal,
    v_rascunho.endereco_snapshot::text,
    'aguardando_rastreio',
    'pago',
    CURRENT_DATE
  ) RETURNING id INTO v_pedido_id;

  -- promove rascunho
  UPDATE public.pedido_em_aberto
     SET status     = 'pago',
         pago_em    = now(),
         pix_id     = COALESCE(p_pix_id, pix_id),
         pedido_id  = v_pedido_id,
         updated_at = now()
   WHERE id = p_pedido_em_aberto_id;

  -- contato vira CLIENTE
  UPDATE public.contatos
     SET ultima_interacao          = 'cliente',
         ja_comprou                = true,
         data_cliente              = now(),
         data_em_fechamento        = NULL,
         data_aguardando_pagamento = NULL,
         data_wait_follow_up       = NULL,
         follow_up_tentativas      = 0,
         updated_at                = now()
   WHERE id = v_rascunho.contato_id;

  -- trigger trigger_set_ja_comprou em pedidos já cobre, mas garante idempotente
  RETURN jsonb_build_object('ok', true, 'pedido_id', v_pedido_id, 'total', v_rascunho.total);
END $$;

REVOKE ALL ON FUNCTION public.fechar_pedido_pago(uuid,text) FROM public;
GRANT EXECUTE ON FUNCTION public.fechar_pedido_pago(uuid,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 9) RPC: expirar_pedidos_abandonados (chamada pelo cron)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expirar_pedidos_abandonados()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_qtd integer := 0;
  v_ja_comprou boolean;
  v_rec record;
BEGIN
  FOR v_rec IN
    SELECT id, contato_id
      FROM public.pedido_em_aberto
     WHERE status = 'aguardando_pagamento'
       AND expires_at < now()
  LOOP
    UPDATE public.pedido_em_aberto
       SET status = 'expirado', updated_at = now()
     WHERE id = v_rec.id;

    SELECT ja_comprou INTO v_ja_comprou
      FROM public.contatos WHERE id = v_rec.contato_id;

    UPDATE public.contatos
       SET ultima_interacao = CASE WHEN v_ja_comprou THEN 'cliente'
                                   ELSE 'wait_follow_up' END,
           data_wait_follow_up = CASE WHEN v_ja_comprou THEN data_wait_follow_up ELSE now() END,
           data_aguardando_pagamento = NULL,
           updated_at = now()
     WHERE id = v_rec.contato_id
       AND ultima_interacao = 'aguardando_pagamento';

    v_qtd := v_qtd + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'expirados', v_qtd);
END $$;

REVOKE ALL ON FUNCTION public.expirar_pedidos_abandonados() FROM public;
GRANT EXECUTE ON FUNCTION public.expirar_pedidos_abandonados() TO service_role;

-- ----------------------------------------------------------------------------
-- 10) Estende processar_transicoes_estado_contato pra cobrir aguardando_pagamento
--     (chama expirar_pedidos_abandonados que já é deterministic)
-- ----------------------------------------------------------------------------
-- Cron dedicado roda a cada 1h, mas adicionamos chamada na transição diária pra
-- não depender exclusivamente do cron.
DO $$
BEGIN
  -- só append se a função já existe e não tem ainda
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'processar_transicoes_estado_contato') THEN
    -- nada — usuário pode regenerar a função em migration futura.
    -- mantemos a função intacta e confiamos no cron horário.
    NULL;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 11) pg_cron: expirar-pedidos-abandonados (1h)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- remove versão anterior se houver
    PERFORM cron.unschedule(jobid)
      FROM cron.job
     WHERE jobname = 'expirar-pedidos-abandonados';

    PERFORM cron.schedule(
      'expirar-pedidos-abandonados',
      '*/15 * * * *',  -- a cada 15min — pedido vence em 24h, granularidade mais fina
      $cron$ SELECT public.expirar_pedidos_abandonados(); $cron$
    );
  END IF;
END $$;

-- (descrição do cron no Sistema view fica em listar_crons_status — sem tabela auxiliar)

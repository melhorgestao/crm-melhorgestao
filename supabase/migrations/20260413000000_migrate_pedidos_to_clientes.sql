-- ============================================================
-- Migration: Garante que todos os contatos com pedidos apareçam na coluna Clientes
-- Rodar no Supabase SQL Editor
-- ============================================================

-- 1. Primeiro, faz a migração retroativa: contatos com pedidos que não estão em Clientes
-- Para BASE: move para Clientes
UPDATE public.contatos
SET 
    status_kanban = 'Clientes',
    canal_atual = COALESCE(canal_atual, canal_origem),
    is_novo = true,
    novo_ate = (CURRENT_DATE + 1)::timestamptz,
    updated_at = now()
WHERE 
    canal_origem = 'BASE'
    AND status_kanban != 'Clientes'
    AND EXISTS (
        SELECT 1 FROM public.pedidos p 
        WHERE p.contato_id = contatos.id 
        AND p.status_pagamento = 'pago'
    );

-- 2. Para ADS: move para Clientes (mas com canal_atual = BASE, pois passaram pelo midnight)
UPDATE public.contatos
SET 
    status_kanban = 'Clientes',
    canal_atual = 'BASE',
    canal_origem = 'ADS',
    is_novo = true,
    novo_ate = (CURRENT_DATE + 1)::timestamptz,
    updated_at = now()
WHERE 
    canal_origem = 'ADS'
    AND status_kanban != 'Clientes'
    AND EXISTS (
        SELECT 1 FROM public.pedidos p 
        WHERE p.contato_id = contatos.id 
        AND p.status_pagamento = 'pago'
    );

-- 3. Atualiza o process_venda para também setar is_novo e novo_ate quando move para Clientes
CREATE OR REPLACE FUNCTION public.process_venda(
  p_contato_id uuid,
  p_canal text,
  p_valor numeric,
  p_socio text DEFAULT 'V',
  p_criado_por text DEFAULT 'V',
  p_produtos jsonb DEFAULT NULL,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_obs text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido_id uuid;
  v_order_number integer;
  v_data_sp date;
  v_produto_text text;
  v_quantidade integer;
  v_canal_lancamento text;
  v_is_base boolean;
  v_next_midnight timestamptz;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;
  v_next_midnight := (CURRENT_DATE + 1)::timestamptz;

  -- Check if it's BASE canal
  v_is_base := (p_canal = 'BASE');

  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(nome_oficial, ', ') FROM jsonb_to_recordset(p_produtos) AS x(nome_oficial text, quantidade integer));
    v_quantidade := (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x);
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem,
    criado_por, produto, quantidade, order_number, data, status_pedido, observacao
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, 'pago', p_modalidade, p_uf_postagem,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio', p_obs
  ) RETURNING id INTO v_pedido_id;

  -- BASE repeat buyers go back to 'Clientes' for LTV flow
  -- ADS/REP go to 'Pagou' as usual
  -- But also set is_novo and novo_ate for BASE
  UPDATE public.contatos 
  SET status_kanban = CASE WHEN v_is_base THEN 'Clientes' ELSE 'Pagou' END,
      canal_atual = CASE WHEN v_is_base THEN 'BASE' ELSE COALESCE(canal_atual, p_canal) END,
      is_novo = v_is_base,
      novo_ate = CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
      updated_at = now()
  WHERE id = p_contato_id;

  INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
  VALUES (p_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

-- 4. Atualiza criar_pedido para também setar is_novo e novo_ate
CREATE OR REPLACE FUNCTION public.criar_pedido(
  p_contato_id uuid DEFAULT NULL,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
  p_produtos jsonb DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido_id uuid;
  v_order_number integer;
  v_data_sp date;
  v_produto_text text;
  v_quantidade integer;
  v_socio text;
  v_canal_lancamento text;
  v_is_base boolean;
  v_next_midnight timestamptz;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;
  v_next_midnight := (CURRENT_DATE + 1)::timestamptz;

  -- Check if it's BASE canal
  v_is_base := (p_canal = 'BASE');

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(nome_oficial, ', ') FROM jsonb_to_recordset(p_produtos) AS x(nome_oficial text, quantidade integer));
    v_quantidade := (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x);
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  v_socio := CASE WHEN p_criado_por ILIKE 'v%' OR p_criado_por ILIKE 'v@%' THEN 'V' ELSE 'A' END;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;

  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem,
    criado_por, produto, quantidade, order_number, data, status_pedido,
    representante_id, tipo_origem, entrega_em_maos
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, p_status_pagamento, p_modalidade, p_uf_postagem,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio',
    p_representante_id,
    CASE WHEN p_representante_id IS NOT NULL THEN 'rep' WHEN p_canal = 'ADS' THEN 'ads' ELSE 'base' END,
    false
  ) RETURNING id INTO v_pedido_id;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
    SELECT v_pedido_id, (x->>'produto_id')::uuid, COALESCE(x->>'produto', x->>'nome_oficial'), (x->>'quantidade')::integer, (x->>'valor_unit')::numeric
    FROM jsonb_array_elements(p_produtos) AS x;
  END IF;

  -- BASE repeat buyers -> Clientes | Others -> Pagou
  -- Also set is_novo and novo_ate for BASE
  IF p_contato_id IS NOT NULL AND p_status_pagamento = 'pago' THEN
    UPDATE public.contatos 
    SET status_kanban = CASE WHEN v_is_base THEN 'Clientes' ELSE 'Pagou' END,
        canal_atual = CASE WHEN v_is_base THEN 'BASE' ELSE COALESCE(canal_atual, p_canal) END,
        is_novo = v_is_base,
        novo_ate = CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
        updated_at = now()
    WHERE id = p_contato_id;
  END IF;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
    VALUES (v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);
  END IF;

  -- Abate estoque automaticamente se tiver UF de postagem (Admin)
  IF p_uf_postagem IS NOT NULL AND p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    PERFORM public.processar_pedido_estoque_trigger(v_pedido_id, p_uf_postagem);
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

-- 5. Atualiza o perform_midnight_lead_migration para também processar pedidos do dia (não só ontem)
-- Isso garante que pedidos criados manualmente no dia também participem da migração
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_base_instance_id uuid;
  v_migrated_count integer := 0;
  v_next_midnight timestamptz;
  v_data_sp date;
BEGIN
  v_next_midnight := (CURRENT_DATE + 1)::timestamptz;
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;

  SELECT id INTO v_base_instance_id 
  FROM public.instancias 
  WHERE tipo = 'base' AND ativo = true
  ORDER BY is_default_base DESC, created_at ASC 
  LIMIT 1;

  -- ADS -> BASE: canal_atual muda, is_novo = true até próximo midnight
  -- Agora também processa pedidos de HOJE (v_data_sp) além de ontem
  UPDATE public.contatos
  SET 
      canal_atual = 'BASE',
      status_kanban = 'Clientes',
      instancia_id = COALESCE(v_base_instance_id, instancia_id),
      is_novo = true,
      novo_ate = v_next_midnight,
      updated_at = now()
  WHERE 
      canal_origem = 'ADS' 
      AND ultima_venda_em = v_data_sp;

  GET DIAGNOSTICS v_migrated_count = ROW_COUNT;

  -- BASE Pagou -> Clientes (hoje)
  UPDATE public.contatos
  SET 
      status_kanban = 'Clientes',
      is_novo = true,
      novo_ate = v_next_midnight,
      updated_at = now()
  WHERE 
      canal_origem = 'BASE' 
      AND status_kanban = 'Pagou'
      AND ultima_venda_em = v_data_sp;

  GET DIAGNOSTICS v_migrated_count = v_migrated_count + ROW_COUNT;

  -- Desativa tags expiradas
  UPDATE public.contatos 
  SET is_novo = false 
  WHERE is_novo = true 
    AND novo_ate IS NOT NULL 
    AND novo_ate <= now();

  INSERT INTO public.configuracoes (chave, valor) 
  VALUES ('ultimo_auto_lead_migration', v_data_sp::text)
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

  RETURN json_build_object(
      'success', true,
      'migrated_count', v_migrated_count,
      'target_instance_id', v_base_instance_id,
      'execution_date', v_data_sp
  );
END;
$$;

-- 6. Verifica resultado
SELECT canal_origem, canal_atual, status_kanban, count(*) as total
FROM contatos 
GROUP BY canal_origem, canal_atual, status_kanban
ORDER BY canal_origem, canal_atual, status_kanban;

-- 7. Verifica quantos contatos têm pedidos
SELECT 
    'Contatos com pedidos' as tipo,
    count(distinct contato_id) as total
FROM pedidos 
WHERE contato_id IS NOT NULL AND status_pagamento = 'pago'
UNION ALL
SELECT 
    'Contatos em Clientes' as tipo,
    count(*) as total
FROM contatos 
WHERE status_kanban = 'Clientes';

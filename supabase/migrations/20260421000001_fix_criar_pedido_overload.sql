-- ==============================================================================
-- criar_pedido_v2 - COMPLETO E CORRIGIDO (todas colunas + trigger de estoque)
-- Execute NO SUPABASE SQL EDITOR
-- ==============================================================================

DROP FUNCTION IF EXISTS public.criar_pedido_v2(uuid, text, numeric, text, text, text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.criar_pedido_v2(
  p_contato_id uuid,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido_id uuid;
  v_contato_id uuid;
  v_produto_id uuid;
  v_qtd integer;
  v_lote_rec record;
  v_order_number integer;
  v_data_sp date;
  v_uf_postagem_calc text;
  v_uf_cliente text;
  v_modalidade_calc text;
  v_socio text;
  v_canal_lancamento text;
  v_quantidade_total integer;
  v_produto_text text;
BEGIN
  -- order_number automático
  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Valida contato obrigatório
  IF p_contato_id IS NULL THEN
    RAISE EXCEPTION 'p_contato_id é obrigatório';
  END IF;

  -- Verifica se contato existe
  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN
    RAISE EXCEPTION 'Contato não encontrado: %', p_contato_id;
  END IF;

  -- Determina sócio (V ou A)
  IF p_criado_por = 'V' OR UPPER(p_criado_por) LIKE '%V%' THEN
    v_socio := 'V';
  ELSIF p_criado_por = 'A' OR UPPER(p_criado_por) LIKE '%A%' THEN
    v_socio := 'A';
  ELSE
    v_socio := 'V';
  END IF;

  -- Canal do lançamento
  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS';
  END IF;

  -- Qtd total produtos
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM((item->>'quantidade')::integer), 1)::int INTO v_quantidade_total
    FROM jsonb_array_elements(p_produtos) AS item;
  ELSE
    v_quantidade_total := 1;
  END IF;

  -- UF do cliente
  BEGIN
    SELECT cidade_uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  -- UF postagem
  IF p_uf_postagem IS NOT NULL AND LENGTH(p_uf_postagem) = 2 THEN
    v_uf_postagem_calc := p_uf_postagem;
  ELSE
    v_uf_postagem_calc := COALESCE(v_uf_cliente, 'SC');
  END IF;

  v_modalidade_calc := COALESCE(p_modalidade, 'mini');

  -- Define produto: se 1 = texto, se +1 = JSON
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    v_quantidade_total := 0;
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      v_quantidade_total := v_quantidade_total + COALESCE(v_qtd, 1);
    END LOOP;
    
    -- Se 1 produto = texto, se +1 = JSON
    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := (p_produtos->0->>'produto');
    ELSE
      v_produto_text := p_produtos::text;  -- Converte JSON para text
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
  END IF;

-- CRIA PEDIDO com todas as colunas (produto e quantidade são text/integer conforme tabela original)
  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, observacao, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, ''), COALESCE(p_criado_por, 'V'), v_order_number, v_data_sp,
    false, now(),
    COALESCE(v_produto_text, ''), v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  -- Processa produtos e ABATE ESTOQUE (sempre, mesmo negativo!)
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      -- Busca lote
      SELECT * INTO v_lote_rec FROM public.lotes l
      WHERE l.produto_id = v_produto_id AND l.uf = v_uf_postagem_calc
      ORDER BY l.data_producao ASC LIMIT 1;

      IF NOT FOUND THEN
        SELECT * INTO v_lote_rec FROM public.lotes l
        WHERE l.produto_id = v_produto_id
        ORDER BY l.data_producao ASC LIMIT 1;
      END IF;

      -- ABATE SEMPRE (pode ficar negativo)
      IF FOUND THEN
        UPDATE public.lotes SET quantidade_atual = quantidade_atual - v_qtd WHERE id = v_lote_rec.id;
        
        -- Registra movimentação
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, lote_id, uf_origem, observacao)
        VALUES (v_produto_id, v_qtd, 'saida', v_lote_rec.id, v_lote_rec.uf, 'Pedido: ' || v_pedido_id);
      END IF;

      -- Insere item no pedido
      INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco)
      VALUES (v_pedido_id, v_produto_id, COALESCE(v_qtd, 1), 0);
    END LOOP;
  END IF;

  -- CRIA LANÇAMENTO DO SÓCIO (só se pago)
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento,
      p_criado_por, v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_v2 TO anon, authenticated, service_role;

-- ==============================================================================
-- GET_ESTOQUE_COMPLETO (igual ao V1 - commit 69e35c1)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_atual)::int as qtd_ent
    FROM public.lotes l 
    WHERE l.quantidade_atual > 0 
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas_produto_id AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, p.quantidade as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL
  ),
  itens_json AS (
    SELECT 
      (jsonb_array_elements(p.produto::jsonb)->>'produto_id')::uuid as pid,
      COALESCE(p.uf_postagem, 'SP') as uff,
      (jsonb_array_elements(p.produto::jsonb)->>'quantidade')::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto LIKE '[%'
  ),
  todas_saidas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM saidas_produto_id WHERE pid IS NOT NULL GROUP BY pid, uff
    UNION ALL
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM itens_json WHERE pid IS NOT NULL GROUP BY pid, uff
  ),
  saidas AS (
    SELECT pid, uff, SUM(qtd_sai)::int as qtd_sai FROM todas_saidas GROUP BY pid, uff
  )
  SELECT 
    COALESCE(e.pid, s.pid) as prod_id,
    pr.pnome as prod_nome,
    COALESCE(e.uff, s.uff, 'SP') as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM produtos_ativos pr
  LEFT JOIN entradas e ON e.pid = pr.pid
  LEFT JOIN saidas s ON s.pid = pr.pid
  WHERE COALESCE(e.qtd_ent, 0) > 0 OR COALESCE(s.qtd_sai, 0) > 0
  ORDER BY pr.pnome, COALESCE(e.uff, s.uff, 'SP');
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_estoque_completo TO anon, authenticated, service_role;

-- ==============================================================================
-- TRIGGER (igual ao V1)
-- ==============================================================================

DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque();

CREATE OR REPLACE FUNCTION public.trigger_novo_pedido_estoque()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_item jsonb;
  v_produto_id uuid;
  v_qtd integer;
  v_uf text;
  v_lote_rec record;
BEGIN
  v_uf := COALESCE(NEW.uf_postagem, 'SP');
  
  -- Se tem produto_id direto (1 item)
  IF NEW.produto_id IS NOT NULL THEN
    -- Abate lote
    SELECT * INTO v_lote_rec FROM lotes l
    WHERE l.produto_id = NEW.produto_id AND l.uf = v_uf AND l.quantidade_atual > 0
    ORDER BY l.data_producao ASC LIMIT 1;
    IF NOT FOUND THEN
      SELECT * INTO v_lote_rec FROM lotes l
      WHERE l.produto_id = NEW.produto_id AND l.quantidade_atual > 0
      ORDER BY l.data_producao ASC LIMIT 1;
    END IF;
    
    IF FOUND THEN
      UPDATE lotes SET quantidade_atual = quantidade_atual - NEW.quantidade WHERE id = v_lote_rec.id;
    END IF;
    
    -- Registra movimentação
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
    VALUES (NEW.produto_id, NEW.quantidade, 'saida', 'Venda', v_uf, NEW.id, 'Pedido #' || NEW.id::text);
  
  -- Se tem JSON array (múltiplos itens)
  ELSIF NEW.produto IS NOT NULL AND NEW.produto LIKE '[%' THEN
    FOR v_item IN SELECT jsonb_array_elements(NEW.produto::jsonb)
    LOOP
      v_produto_id := (v_item->>'produto_id')::uuid;
      v_qtd := (v_item->>'quantidade')::int;
      
      IF v_produto_id IS NOT NULL THEN
        -- Abate lote
        SELECT * INTO v_lote_rec FROM lotes l
        WHERE l.produto_id = v_produto_id AND l.uf = v_uf AND l.quantidade_atual > 0
        ORDER BY l.data_producao ASC LIMIT 1;
        IF NOT FOUND THEN
          SELECT * INTO v_lote_rec FROM lotes l
          WHERE l.produto_id = v_produto_id AND l.quantidade_atual > 0
          ORDER BY l.data_producao ASC LIMIT 1;
        END IF;
        
        IF FOUND THEN
          UPDATE lotes SET quantidade_atual = quantidade_atual - v_qtd WHERE id = v_lote_rec.id;
        END IF;
        
        -- Registra movimentação
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
        VALUES (v_produto_id, v_qtd, 'saida', 'Venda', v_uf, NEW.id, 'Pedido #' || NEW.id::text);
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_novo_pedido_estoque TO anon, authenticated, service_role;

-- Cria/atualiza trigger
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
CREATE TRIGGER trg_novo_pedido_estoque AFTER INSERT ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.trigger_novo_pedido_estoque();
END $$;
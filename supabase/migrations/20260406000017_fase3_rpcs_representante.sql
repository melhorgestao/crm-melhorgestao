-- ============================================================
-- Major Update V2 - Fase 3: RPCs para Representante
-- ============================================================

-- 1. ALTER RPC criar_pedido para suportar representante
-- 2. CREATE RPC criar_usuario
-- 3. CREATE RPC deletar_usuario
-- 4. CREATE RPC update_produto_estoque
-- 5. CREATE TRIGGER comissao on pedidos postado

BEGIN;

-- ============================================================
-- 1. ALTER RPC criar_pedido - adicionar p_representante_id
-- ============================================================

-- Drop e recriar com parametro novo
DROP FUNCTION IF EXISTS public.criar_pedido(uuid, text, numeric, text, text, text, text, jsonb, uuid);

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
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Get next order number
  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  -- Determine produto text
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(nome_oficial, ', ') FROM jsonb_to_recordset(p_produtos) AS x(nome_oficial text, quantidade integer));
    v_quantidade := (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x);
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  -- Determine socio
  v_socio := CASE WHEN p_criado_por ILIKE 'v%' OR p_criado_por ILIKE 'v@%' THEN 'V' ELSE 'A' END;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;

  -- Insert pedido
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

  -- Insert produtos if provided
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
    SELECT v_pedido_id, (x->>'produto_id')::uuid, COALESCE(x->>'produto', x->>'nome_oficial'), (x->>'quantidade')::integer, (x->>'valor_unit')::numeric
    FROM jsonb_array_elements(p_produtos) AS x;
  END IF;

  -- Processar estoque se nao for entrega em maos e tiver uf_postagem
  IF p_uf_postagem IS NOT NULL AND p_representante_id IS NULL THEN
    -- Chama trigger de estoque admin
    PERFORM public.processar_pedido_estoque_trigger(v_pedido_id, p_uf_postagem);
  END IF;

  -- Cria lancamento se pago
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
    VALUES (v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);
  END IF;

  -- Atualiza contato status
  IF p_contato_id IS NOT NULL THEN
    UPDATE public.contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

-- ============================================================
-- 2. RPC criar_usuario (suporta senha OU convite email)
-- ============================================================

CREATE OR REPLACE FUNCTION public.criar_usuario(
  p_tipo text,
  p_email text,
  p_senha text DEFAULT NULL,
  p_apelido text,
  p_servico_tipo text DEFAULT NULL,
  p_uf text DEFAULT NULL,
  p_instancia_nome text DEFAULT NULL,
  p_instancia_uf text DEFAULT NULL,
  p_send_invite boolean DEFAULT false,
  p_criado_por uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_perfil_id uuid;
  v_instancia_id uuid;
BEGIN
  -- Tenta encontrar user pelo email
  SELECT id INTO v_user_id FROM auth.users WHERE email = p_email;

  IF v_user_id IS NULL AND p_senha IS NOT NULL THEN
    -- Se nao existe e tem senha, cria via auth com senha
    -- Nota: requires service role key in production
    -- For now, returns error instructing manual creation
    RETURN jsonb_build_object('status', 'error', 'message', 'Usuario nao existe no auth. Crie via Supabase Dashboard ou use Edge Function com service role key.');
  END IF;

  IF v_user_id IS NULL AND p_send_invite THEN
    -- Se nao existe e quer enviar convite
    -- Nota: requires supabase.auth.admin.inviteUserByEmail() via Edge Function
    RETURN jsonb_build_object('status', 'error', 'message', 'Envio de convite requer Edge Function. Crie o usuario via Supabase Dashboard primeiro.');
  END IF;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Usuario nao encontrado. Crie via Supabase Dashboard > Authentication > Users.');
  END IF;

  -- Se representante, cria nova instancia
  IF p_tipo = 'representante' AND p_instancia_nome IS NOT NULL THEN
    INSERT INTO public.instancias (nome, tipo, dono_tipo, uf_fixa, representante_user_id, ativo)
    VALUES (p_instancia_nome, 'rep', 'representante', p_instancia_uf, v_user_id, true)
    RETURNING id INTO v_instancia_id;
  END IF;

  -- Cria perfil
  INSERT INTO public.perfis_usuario (user_id, nome, acesso_kanban, ver_menu, pode_excluir_card, tipo_usuario, servico_tipo, uf_fixa, instancia_id, criado_por, socio_key)
  VALUES (
    v_user_id,
    p_apelido,
    CASE WHEN p_tipo = 'servico' AND p_servico_tipo = 'atendimento' THEN 'kanban'
         WHEN p_tipo = 'servico' AND p_servico_tipo = 'logistica' THEN 'logistica'
         ELSE 'todos' END,
    CASE WHEN p_tipo = 'representante' THEN ARRAY['representante']::text[]
         WHEN p_tipo = 'servico' THEN ARRAY[p_servico_tipo]::text[]
         ELSE ARRAY['todos']::text[] END,
    true,
    p_tipo,
    p_servico_tipo,
    p_uf,
    v_instancia_id,
    p_criado_por,
    CASE WHEN p_tipo = 'admin' THEN UPPER(LEFT(p_apelido, 1)) ELSE NULL END
  ) RETURNING id INTO v_perfil_id;

  RETURN jsonb_build_object('status', 'ok', 'user_id', v_user_id, 'perfil_id', v_perfil_id, 'instancia_id', v_instancia_id);
END;
$$;

-- ============================================================
-- 3. RPC deletar_usuario (placeholder)
-- ============================================================

CREATE OR REPLACE FUNCTION public.deletar_usuario(
  p_user_id uuid,
  p_admin_password text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- NOTA: Deletar usuario do Supabase Auth requer Service Role Key
  -- Este RPC é um placeholder. A delecao real deve ser feita via Edge Function.

  -- Deleta perfil
  DELETE FROM public.perfis_usuario WHERE user_id = p_user_id;

  -- NOTA: O user em auth.users permanece. Para deletar completamente, use Edge Function.
  RETURN jsonb_build_object('status', 'ok', 'message', 'Perfil deletado. User auth requer Edge Function.');
END;
$$;

-- ============================================================
-- 4. RPC update_produto_estoque
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_produto_estoque(p_produto_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_entradas numeric;
  v_saidas numeric;
BEGIN
  SELECT COALESCE(SUM(quantidade), 0) INTO v_entradas FROM public.estoque_movimentacoes WHERE produto_id = p_produto_id AND tipo = 'entrada';
  SELECT COALESCE(SUM(quantidade), 0) INTO v_saidas FROM public.estoque_movimentacoes WHERE produto_id = p_produto_id AND tipo = 'saida';

  UPDATE public.produtos SET estoque_atual = v_entradas - v_saidas WHERE id = p_produto_id;
END;
$$;

-- ============================================================
-- 5. TRIGGER comissao on pedido postado (representante)
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_comissao_pedido_postado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_produto_record record;
  v_comissao numeric;
BEGIN
  -- So processa se for representante e status mudou para postado
  IF NEW.representante_id IS NULL OR NEW.status_pedido != 'postado' OR (OLD.status_pedido = 'postado') THEN
    RETURN NEW;
  END IF;

  -- Processa cada produto do pedido
  IF NEW.produto IS NOT NULL THEN
    BEGIN
      FOR v_produto_record IN
        SELECT nome_oficial as produto, quantidade
        FROM jsonb_to_recordset(NEW.produto::jsonb) AS x(nome_oficial text, quantidade integer)
      LOOP
        -- Busca comissao configurada
        SELECT valor_comissao INTO v_comissao
        FROM public.config_comissao_produto
        WHERE produto_tag = LOWER(v_produto_record.produto)
        AND ativo = true;

        IF v_comissao IS NOT NULL THEN
          INSERT INTO public.comissoes (representante_id, pedido_id, produto, valor_fixo, status)
          VALUES (NEW.representante_id, NEW.id, v_produto_record.produto, v_comissao * v_produto_record.quantidade, 'pendente');
        END IF;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      -- Se falhar parse JSON, ignora comissao
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_comissao_pedido_postado ON public.pedidos;
CREATE TRIGGER trg_comissao_pedido_postado
  AFTER UPDATE OF status_pedido ON public.pedidos
  FOR EACH ROW
  WHEN (NEW.status_pedido = 'postado' AND OLD.status_pedido != 'postado')
  EXECUTE FUNCTION public.trg_comissao_pedido_postado();

COMMIT;

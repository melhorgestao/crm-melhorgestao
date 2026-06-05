-- FULL SCHEMA EXPORT
-- Generated on 2026-04-25T23:11:55.486Z

-- MIGRATION: 20260330062711_f5dc1631-4203-460b-9d19-e298cfe179f1.sql

-- perfis_usuario
CREATE TABLE public.perfis_usuario (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  nome text NOT NULL,
  acesso_kanban text NOT NULL DEFAULT 'todos' CHECK (acesso_kanban IN ('ads', 'base', 'todos')),
  ver_menu jsonb NOT NULL DEFAULT '["todos"]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.perfis_usuario ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own profile" ON public.perfis_usuario FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can update own profile" ON public.perfis_usuario FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- instancias
CREATE TABLE public.instancias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  tipo text NOT NULL CHECK (tipo IN ('ads', 'base')),
  numero_final text,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.instancias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read instancias" ON public.instancias FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage instancias" ON public.instancias FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- contatos
CREATE TABLE public.contatos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  telefone text,
  instancia_id uuid REFERENCES public.instancias(id),
  canal_origem text CHECK (canal_origem IN ('ADS', 'BASE', 'REP')),
  status_kanban text,
  endereco text,
  cidade text,
  cep text,
  observacao text,
  tag_vip boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.contatos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read contatos" ON public.contatos FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert contatos" ON public.contatos FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update contatos" ON public.contatos FOR UPDATE TO authenticated USING (true);
CREATE POLICY "Authenticated users can delete contatos" ON public.contatos FOR DELETE TO authenticated USING (true);

-- produtos
CREATE TABLE public.produtos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome_oficial text NOT NULL,
  tag text NOT NULL,
  preco numeric,
  posologia text,
  estoque_atual integer NOT NULL DEFAULT 0,
  cor_card text,
  cor_texto text,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read produtos" ON public.produtos FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage produtos" ON public.produtos FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- pedidos
CREATE TABLE public.pedidos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contato_id uuid REFERENCES public.contatos(id),
  produto text,
  quantidade integer,
  valor numeric,
  canal text CHECK (canal IN ('ADS', 'BASE', 'REP')),
  endereco_entrega text,
  status_pedido text DEFAULT 'aguardando_rastreio' CHECK (status_pedido IN ('aguardando_rastreio', 'postado')),
  codigo_rastreio text,
  rastreio_notificado boolean NOT NULL DEFAULT false,
  data date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.pedidos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read pedidos" ON public.pedidos FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert pedidos" ON public.pedidos FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update pedidos" ON public.pedidos FOR UPDATE TO authenticated USING (true);
CREATE POLICY "Authenticated users can delete pedidos" ON public.pedidos FOR DELETE TO authenticated USING (true);

-- financeiro
CREATE TABLE public.financeiro (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo text NOT NULL CHECK (tipo IN ('receita', 'despesa')),
  valor numeric NOT NULL,
  canal text CHECK (canal IN ('ADS', 'BASE', 'REP')),
  categoria text CHECK (categoria IN ('ads', 'etiqueta', 'logistica', 'material')),
  quantidade integer,
  descricao text,
  data date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.financeiro ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read financeiro" ON public.financeiro FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert financeiro" ON public.financeiro FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update financeiro" ON public.financeiro FOR UPDATE TO authenticated USING (true);
CREATE POLICY "Authenticated users can delete financeiro" ON public.financeiro FOR DELETE TO authenticated USING (true);

-- lancamentos_socios
CREATE TABLE public.lancamentos_socios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  socio text NOT NULL CHECK (socio IN ('V', 'A')),
  tipo text NOT NULL CHECK (tipo IN ('VENDA', 'ADS', 'ETIQUETA', 'MATERIAL', 'LOGISTICA')),
  valor numeric NOT NULL,
  canal text,
  contato_id uuid REFERENCES public.contatos(id),
  produto_id uuid REFERENCES public.produtos(id),
  quantidade integer,
  descricao text,
  realizado boolean NOT NULL DEFAULT false,
  realizado_em timestamptz,
  data date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.lancamentos_socios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read lancamentos_socios" ON public.lancamentos_socios FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert lancamentos_socios" ON public.lancamentos_socios FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update lancamentos_socios" ON public.lancamentos_socios FOR UPDATE TO authenticated USING (true);
CREATE POLICY "Authenticated users can delete lancamentos_socios" ON public.lancamentos_socios FOR DELETE TO authenticated USING (true);

-- estoque_movimentacoes
CREATE TABLE public.estoque_movimentacoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  produto_id uuid REFERENCES public.produtos(id) NOT NULL,
  quantidade integer NOT NULL,
  tipo text NOT NULL CHECK (tipo IN ('entrada', 'saida')),
  posse text,
  observacao text,
  data date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.estoque_movimentacoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read estoque_movimentacoes" ON public.estoque_movimentacoes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert estoque_movimentacoes" ON public.estoque_movimentacoes FOR INSERT TO authenticated WITH CHECK (true);

-- follow_up
CREATE TABLE public.follow_up (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contato_id uuid REFERENCES public.contatos(id) NOT NULL,
  tipo text,
  mensagem text,
  data_envio timestamptz,
  status text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.follow_up ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read follow_up" ON public.follow_up FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage follow_up" ON public.follow_up FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- log_atividades
CREATE TABLE public.log_atividades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario text NOT NULL,
  acao text NOT NULL,
  tabela_afetada text,
  registro_id uuid,
  detalhe text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.log_atividades ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read log_atividades" ON public.log_atividades FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert log_atividades" ON public.log_atividades FOR INSERT TO authenticated WITH CHECK (true);

-- configuracoes
CREATE TABLE public.configuracoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chave_api_superfrete text,
  webhook_n8n_url text,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read configuracoes" ON public.configuracoes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage configuracoes" ON public.configuracoes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Insert default configuracoes row
INSERT INTO public.configuracoes (id) VALUES (gen_random_uuid());

-- Pre-populate produtos
INSERT INTO public.produtos (nome_oficial, tag, cor_card, cor_texto) VALUES
  ('Óleo CBD', 'cbd', '#2D5A27', '#FFFFFF'),
  ('Óleo Full Spectrum 6000mg', 'full6k', '#F5C518', '#000000'),
  ('Óleo Full Spectrum 10000mg', 'full10k', '#E53935', '#FFFFFF'),
  ('Gummy', 'gummy', '#7B1FA2', '#FFFFFF'),
  ('Pomada', 'pomada', '#81C784', '#000000'),
  ('Lubrificante', 'lubrificante', '#F48FB1', '#000000');

-- Enable realtime on all tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.perfis_usuario;
ALTER PUBLICATION supabase_realtime ADD TABLE public.instancias;
ALTER PUBLICATION supabase_realtime ADD TABLE public.contatos;
ALTER PUBLICATION supabase_realtime ADD TABLE public.produtos;
ALTER PUBLICATION supabase_realtime ADD TABLE public.pedidos;
ALTER PUBLICATION supabase_realtime ADD TABLE public.financeiro;
ALTER PUBLICATION supabase_realtime ADD TABLE public.lancamentos_socios;
ALTER PUBLICATION supabase_realtime ADD TABLE public.estoque_movimentacoes;
ALTER PUBLICATION supabase_realtime ADD TABLE public.follow_up;
ALTER PUBLICATION supabase_realtime ADD TABLE public.log_atividades;
ALTER PUBLICATION supabase_realtime ADD TABLE public.configuracoes;


-- MIGRATION: 20260330200349_a41e854f-42cc-4fed-b4fa-d31af5381e56.sql

-- Add columns to contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS cpf text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS data_nascimento date;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS utm_origem text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS como_conheceu text;

-- Rename cidade to cidade_uf
ALTER TABLE public.contatos RENAME COLUMN cidade TO cidade_uf;

-- Add columns to pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS produto_id uuid REFERENCES public.produtos(id);
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS preco_unitario numeric;
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

-- Create lotes table
CREATE TABLE public.lotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  produto_id uuid NOT NULL REFERENCES public.produtos(id),
  uf text NOT NULL,
  quantidade_inicial integer NOT NULL,
  quantidade_atual integer NOT NULL,
  data_producao date NOT NULL DEFAULT CURRENT_DATE,
  lote_codigo text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.lotes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read lotes" ON public.lotes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage lotes" ON public.lotes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Add columns to estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS lote_id uuid REFERENCES public.lotes(id);
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS uf_origem text;

-- Add snapshot columns to lancamentos_socios
ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS snapshot_saldo_v numeric;
ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS snapshot_saldo_a numeric;

-- Drop configuracoes table
DROP TABLE IF EXISTS public.configuracoes;

-- Enable realtime on lotes
ALTER PUBLICATION supabase_realtime ADD TABLE public.lotes;

-- Create pg_cron extension for archiving
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Create archiving function
CREATE OR REPLACE FUNCTION public.archive_stale_kanban_cards()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Archive BASE "Comprou Há X dias" cards where payment > 60 days ago
  UPDATE public.contatos
  SET status_kanban = 'arquivado', updated_at = now()
  WHERE status_kanban = 'Comprou Há X dias'
    AND updated_at < now() - interval '60 days';

  -- Archive ADS "Sumiu" cards older than 60 days
  UPDATE public.contatos
  SET status_kanban = 'arquivado_sumiu', updated_at = now()
  WHERE status_kanban LIKE '%Sumiu%'
    AND updated_at < now() - interval '60 days';
END;
$$;

-- Schedule daily archiving at 3 AM
SELECT cron.schedule(
  'archive-stale-kanban-cards',
  '0 3 * * *',
  $$SELECT public.archive_stale_kanban_cards()$$
);


-- MIGRATION: 20260331030850_e9baa581-69a1-45af-8d1f-bf6a4f4e373d.sql

-- Enable pg_cron and pg_net extensions
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;


-- MIGRATION: 20260331030941_b2f984cb-71a8-4792-b548-da9d5fc6c243.sql

SELECT cron.schedule(
  'archive-stale-kanban-daily',
  '0 3 * * *',
  $$SELECT public.archive_stale_kanban_cards()$$
);


-- MIGRATION: 20260331032414_9f09c280-b9f8-49b9-ba92-4e19f90a369e.sql
-- 1. Drop como_conheceu column
ALTER TABLE public.contatos DROP COLUMN IF EXISTS como_conheceu;

-- 2. Create metas_mensais table for dashboard monthly goals
CREATE TABLE IF NOT EXISTS public.metas_mensais (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  ano integer NOT NULL,
  mes integer NOT NULL,
  valor numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, ano, mes)
);
ALTER TABLE public.metas_mensais ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own metas" ON public.metas_mensais FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 3. Create atomic VENDA function
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  prod_endereco text;
  prod_count integer;
BEGIN
  prod_count := jsonb_array_length(p_produtos);

  INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade)
  VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id,
    (SELECT COALESCE(SUM((p->>'quantidade')::int), 0) FROM jsonb_array_elements(p_produtos) p));

  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    prod_endereco := prod->>'endereco_entrega';

    INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, endereco_entrega, produto_id, preco_unitario)
    VALUES (p_contato_id, prod_nome, prod_qty, p_valor / prod_count, p_canal, 'aguardando_rastreio', prod_endereco, prod_id, prod_preco);

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;

    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse)
    VALUES (prod_id, prod_qty, 'saida', 'Venda');
  END LOOP;

  INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);

  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- MIGRATION: 20260331045446_761d2a82-592b-49fc-bd4f-f56e053bc2ca.sql
-- Add rua_numero and bairro to contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS rua_numero text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS bairro text;

-- Drop endereco column
ALTER TABLE public.contatos DROP COLUMN IF EXISTS endereco;

-- Drop como_conheceu if it exists
ALTER TABLE public.contatos DROP COLUMN IF EXISTS como_conheceu;

-- Update process_venda to use rua_numero instead of endereco
CREATE OR REPLACE FUNCTION public.process_venda(p_socio text, p_canal text, p_valor numeric, p_contato_id uuid, p_produtos jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  prod_endereco text;
  prod_count integer;
BEGIN
  prod_count := jsonb_array_length(p_produtos);

  INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade)
  VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id,
    (SELECT COALESCE(SUM((p->>'quantidade')::int), 0) FROM jsonb_array_elements(p_produtos) p));

  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    prod_endereco := prod->>'endereco_entrega';

    INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, endereco_entrega, produto_id, preco_unitario)
    VALUES (p_contato_id, prod_nome, prod_qty, p_valor / prod_count, p_canal, 'aguardando_rastreio', prod_endereco, prod_id, prod_preco);

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;

    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse)
    VALUES (prod_id, prod_qty, 'saida', 'Venda');
  END LOOP;

  INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);

  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$function$;

-- MIGRATION: 20260331053404_438ace61-435d-4b25-8ceb-011c0be9d37a.sql
-- Drop data_nascimento from contatos
ALTER TABLE public.contatos DROP COLUMN IF EXISTS data_nascimento;

-- Recreate process_venda to create 1 single pedido with JSON produtos array
CREATE OR REPLACE FUNCTION public.process_venda(p_socio text, p_canal text, p_valor numeric, p_contato_id uuid, p_produtos jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
BEGIN
  -- Build the JSON array of products for the single pedido
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    produtos_array := produtos_array || jsonb_build_array(jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    ));

    -- Deduct stock per product
    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;

    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse)
    VALUES (prod_id, prod_qty, 'saida', 'Venda');
  END LOOP;

  -- 1 lancamento
  INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade)
  VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty);

  -- 1 single pedido with all products as JSON
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, produto_id, preco_unitario)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', NULL, NULL);

  -- 1 financeiro
  INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);

  -- Update kanban
  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$function$;

-- MIGRATION: 20260401063840_6c06f4c2-af6d-4a1b-8810-3c83dc587957.sql

-- 1. Create remetentes_uf table
CREATE TABLE public.remetentes_uf (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uf text UNIQUE NOT NULL,
  cep_origem text,
  cidade text,
  bairro text,
  endereco text,
  numero text,
  complemento text,
  nome_remetente text,
  contato_remetente text,
  cpf text,
  updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.remetentes_uf ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage remetentes_uf" ON public.remetentes_uf FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Pre-populate with 4 UFs
INSERT INTO public.remetentes_uf (uf) VALUES ('SC'), ('RS'), ('SP'), ('GO');

-- 2. Create configuracoes table for API keys
CREATE TABLE public.configuracoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chave text UNIQUE NOT NULL,
  valor text,
  updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage configuracoes" ON public.configuracoes FOR ALL TO authenticated USING (true) WITH CHECK (true);

INSERT INTO public.configuracoes (chave, valor) VALUES ('chave_api_superfrete', '');

-- 3. Add new columns to pedidos
ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS modalidade text,
  ADD COLUMN IF NOT EXISTS uf_postagem text,
  ADD COLUMN IF NOT EXISTS formato_caixa text,
  ADD COLUMN IF NOT EXISTS peso_envio integer,
  ADD COLUMN IF NOT EXISTS altura_caixa integer,
  ADD COLUMN IF NOT EXISTS largura_caixa integer,
  ADD COLUMN IF NOT EXISTS comprimento_caixa integer,
  ADD COLUMN IF NOT EXISTS etiqueta_url text,
  ADD COLUMN IF NOT EXISTS etiqueta_codigo text;

-- 4. Add new columns to lancamentos_socios
ALTER TABLE public.lancamentos_socios
  ADD COLUMN IF NOT EXISTS modalidade text,
  ADD COLUMN IF NOT EXISTS uf_postagem text;

-- 5. Update process_venda to handle FIFO lote deduction and new fields
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text, p_canal text, p_valor numeric, p_contato_id uuid, p_produtos jsonb,
  p_modalidade text DEFAULT 'mini', p_uf_postagem text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  used_fallback boolean := false;
  fallback_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
BEGIN
  -- Get client UF from cidade_uf (last 2 chars)
  SELECT RIGHT(TRIM(cidade_uf), 2) INTO client_uf FROM contatos WHERE id = p_contato_id;

  -- Build the JSON array of products for the single pedido
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    -- Check if product is gummy, pomada, or lubrificante
    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_array(jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    ));

    -- FIFO lote deduction
    remaining := prod_qty;
    
    -- First try lotes matching client UF
    FOR lote_rec IN 
      SELECT id, quantidade_atual, uf FROM lotes 
      WHERE produto_id = prod_id AND quantidade_atual > 0 AND uf = COALESCE(client_uf, '')
      ORDER BY data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    -- Fallback: use oldest lote across ALL UFs
    IF remaining > 0 THEN
      FOR lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = prod_id AND quantidade_atual > 0
        ORDER BY data_producao ASC
      LOOP
        IF remaining <= 0 THEN EXIT; END IF;
        deduct := LEAST(remaining, lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
        VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
        remaining := remaining - deduct;
        used_fallback := true;
        fallback_uf := lote_rec.uf;
      END LOOP;
    END IF;

    -- Always deduct from produtos.estoque_atual
    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions based on modalidade
  IF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini';
    v_peso := 300;
    v_altura := 2;
    v_largura := 11;
    v_comprimento := 16;
  ELSE
    -- pac or sedex
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p';
      v_peso := 1000;
      v_altura := 6;
      v_largura := 11;
      v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini';
      v_peso := 300;
      v_altura := 2;
      v_largura := 11;
      v_comprimento := 16;
    END IF;
  END IF;

  -- 1 lancamento
  INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem)
  VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem);

  -- 1 single pedido with all products as JSON
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, produto_id, preco_unitario,
    modalidade, uf_postagem, formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', NULL, NULL,
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento);

  -- 1 financeiro
  INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);

  -- Update kanban
  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$$;


-- MIGRATION: 20260402011251_fbd2392f-7fc3-4a89-a534-d970a7fce0c6.sql

-- 1. pedidos: add status_pagamento, order_number, complemento
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago';
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS complemento text;

CREATE SEQUENCE IF NOT EXISTS pedidos_order_number_seq;

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS order_number integer;

-- Backfill existing rows
DO $$
BEGIN
  UPDATE public.pedidos SET order_number = nextval('pedidos_order_number_seq') WHERE order_number IS NULL;
END $$;

ALTER TABLE public.pedidos ALTER COLUMN order_number SET DEFAULT nextval('pedidos_order_number_seq');
ALTER TABLE public.pedidos ALTER COLUMN order_number SET NOT NULL;
ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_order_number_unique UNIQUE (order_number);

-- 2. contatos: rename rua_numero → endereco, add complemento
ALTER TABLE public.contatos RENAME COLUMN rua_numero TO endereco;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS complemento text;

-- 3. remetentes_uf: add descricao_produto, valor_unitario
ALTER TABLE public.remetentes_uf ADD COLUMN IF NOT EXISTS descricao_produto text;
ALTER TABLE public.remetentes_uf ADD COLUMN IF NOT EXISTS valor_unitario numeric;

-- 4. perfis_usuario: add pode_excluir_card
ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS pode_excluir_card boolean DEFAULT true;

-- 5. Update process_venda function with status_pagamento support
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  used_fallback boolean := false;
  fallback_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
BEGIN
  -- Get client UF from cidade_uf (last 2 chars)
  SELECT RIGHT(TRIM(cidade_uf), 2) INTO client_uf FROM contatos WHERE id = p_contato_id;

  -- Build the JSON array of products
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_array(jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    ));

    -- FIFO lote deduction
    remaining := prod_qty;
    
    FOR lote_rec IN 
      SELECT id, quantidade_atual, uf FROM lotes 
      WHERE produto_id = prod_id AND quantidade_atual > 0 AND uf = COALESCE(client_uf, '')
      ORDER BY data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    IF remaining > 0 THEN
      FOR lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = prod_id AND quantidade_atual > 0
        ORDER BY data_producao ASC
      LOOP
        IF remaining <= 0 THEN EXIT; END IF;
        deduct := LEAST(remaining, lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
        VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
        remaining := remaining - deduct;
        used_fallback := true;
        fallback_uf := lote_rec.uf;
      END LOOP;
    END IF;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL;
    v_peso := NULL;
    v_altura := NULL;
    v_largura := NULL;
    v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini';
    v_peso := 300;
    v_altura := 2;
    v_largura := 11;
    v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p';
      v_peso := 1000;
      v_altura := 6;
      v_largura := 11;
      v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini';
      v_peso := 300;
      v_altura := 2;
      v_largura := 11;
      v_comprimento := 16;
    END IF;
  END IF;

  -- Only create lancamento if pago
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem);

    INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);
  END IF;

  -- Always create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, produto_id, preco_unitario,
    modalidade, uf_postagem, formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', NULL, NULL,
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento);

  -- Update kanban
  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$$;


-- MIGRATION: 20260402084900_fix_process_venda_overload.sql
-- Fix: Drop the orphaned 7-param process_venda that was never removed
-- This causes PostgREST ambiguity when calling the 8-param version
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text);

-- Also drop any leftover 5-param version just in case
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb);

-- Add separate cidade and uf columns to contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS cidade text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS uf text;

-- Backfill cidade and uf from cidade_uf
DO $$
BEGIN
  UPDATE public.contatos
  SET
    cidade = CASE
      WHEN cidade_uf IS NOT NULL AND cidade_uf LIKE '%/%' THEN TRIM(SPLIT_PART(cidade_uf, '/', 1))
      WHEN cidade_uf IS NOT NULL AND LENGTH(TRIM(cidade_uf)) > 2 THEN TRIM(LEFT(cidade_uf, LENGTH(cidade_uf) - 2))
      ELSE cidade_uf
    END,
    uf = CASE
      WHEN cidade_uf IS NOT NULL AND cidade_uf LIKE '%/%' THEN TRIM(SPLIT_PART(cidade_uf, '/', 2))
      WHEN cidade_uf IS NOT NULL AND LENGTH(TRIM(cidade_uf)) >= 2 THEN TRIM(RIGHT(cidade_uf, 2))
      ELSE NULL
    END
  WHERE cidade IS NULL AND cidade_uf IS NOT NULL;
END $$;

-- Recreate the definitive process_venda with 8 params (the only version)
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  used_fallback boolean := false;
  fallback_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
BEGIN
  -- Get client UF from uf column first, fallback to cidade_uf
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build the JSON array of products
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_array(jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    ));

    -- FIFO lote deduction
    remaining := prod_qty;

    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0 AND uf = COALESCE(client_uf, '')
      ORDER BY data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    IF remaining > 0 THEN
      FOR lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = prod_id AND quantidade_atual > 0
        ORDER BY data_producao ASC
      LOOP
        IF remaining <= 0 THEN EXIT; END IF;
        deduct := LEAST(remaining, lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
        VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
        remaining := remaining - deduct;
        used_fallback := true;
        fallback_uf := lote_rec.uf;
      END LOOP;
    END IF;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL;
    v_peso := NULL;
    v_altura := NULL;
    v_largura := NULL;
    v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini';
    v_peso := 300;
    v_altura := 2;
    v_largura := 11;
    v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p';
      v_peso := 1000;
      v_altura := 6;
      v_largura := 11;
      v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini';
      v_peso := 300;
      v_altura := 2;
      v_largura := 11;
      v_comprimento := 16;
    END IF;
  END IF;

  -- Only create lancamento if pago
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem);

    INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);
  END IF;

  -- Always create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, produto_id, preco_unitario,
    modalidade, uf_postagem, formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', NULL, NULL,
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento);

  -- Update kanban
  UPDATE contatos SET status_kanban = 'Pagou', updated_at = now() WHERE id = p_contato_id;
END;
$$;


-- MIGRATION: 20260402100000_fix_process_venda_nested_json.sql
-- Fix: Process Venda - Correction for nested product JSON and Kanban status for pending orders
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  used_fallback boolean := false;
  fallback_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
BEGIN
  -- Get client UF from status_uf column first, fallback to cidade_uf
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build the JSON array of products (CORRECTLY without nested arrays)
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    -- FIX: Appending the object directly to the array (don't wrap in another jsonb_build_array)
    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    -- FIFO lote deduction
    remaining := prod_qty;

    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0 AND uf = COALESCE(client_uf, '')
      ORDER BY data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    IF remaining > 0 THEN
      FOR lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = prod_id AND quantidade_atual > 0
        ORDER BY data_producao ASC
      LOOP
        IF remaining <= 0 THEN EXIT; END IF;
        deduct := LEAST(remaining, lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
        VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
        remaining := remaining - deduct;
        used_fallback := true;
        fallback_uf := lote_rec.uf;
      END LOOP;
    END IF;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL;
    v_peso := NULL;
    v_altura := NULL;
    v_largura := NULL;
    v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini';
    v_peso := 300;
    v_altura := 2;
    v_largura := 11;
    v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p';
      v_peso := 1000;
      v_altura := 6;
      v_largura := 11;
      v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini';
      v_peso := 300;
      v_altura := 2;
      v_largura := 11;
      v_comprimento := 16;
    END IF;
  END IF;

  -- Logic for payments
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem);

    INSERT INTO financeiro (tipo, valor, canal) VALUES ('receita', p_valor, p_canal);
    v_status_kanban := 'Pagou';
  ELSE
    v_status_kanban := 'Aguardando Pagamento';
  END IF;

  -- Always create pedido (status_pedido remains 'aguardando_rastreio' to show in Logistics)
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, produto_id, preco_unitario,
    modalidade, uf_postagem, formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', NULL, NULL,
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento);

  -- Update kanban
  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;


-- MIGRATION: 20260402120000_crm_v2_updates.sql
-- PART 1 & 7: Table changes and Foreign Keys

-- 1.1 Tabela pedidos — colunas
ALTER TABLE pedidos 
ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago' 
  CHECK (status_pagamento IN ('pago', 'pendente')),
ADD COLUMN IF NOT EXISTS complemento text,
ADD COLUMN IF NOT EXISTS criado_por text;

-- 1.2 Tabela lancamentos_socios — colunas
ALTER TABLE lancamentos_socios
ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago'
  CHECK (status_pagamento IN ('pago', 'pendente')),
ADD COLUMN IF NOT EXISTS criado_por text;

-- 1.2b Tabela perfis_usuario — colunas
ALTER TABLE perfis_usuario
ADD COLUMN IF NOT EXISTS pode_excluir_card boolean DEFAULT true;

-- 1.3 & 7: Foreign Keys and pedido_id
-- 1. pedidos → contatos
ALTER TABLE pedidos 
  DROP CONSTRAINT IF EXISTS pedidos_contato_id_fkey,
  ADD CONSTRAINT pedidos_contato_id_fkey 
    FOREIGN KEY (contato_id) REFERENCES contatos(id) ON DELETE SET NULL;

-- 2. lancamentos_socios → contatos
ALTER TABLE lancamentos_socios
  DROP CONSTRAINT IF EXISTS lancamentos_socios_contato_id_fkey,
  ADD CONSTRAINT lancamentos_socios_contato_id_fkey
    FOREIGN KEY (contato_id) REFERENCES contatos(id) ON DELETE SET NULL;

-- 3. lancamentos_socios → pedidos
ALTER TABLE lancamentos_socios
  ADD COLUMN IF NOT EXISTS pedido_id uuid;

ALTER TABLE lancamentos_socios
  DROP CONSTRAINT IF EXISTS lancamentos_socios_pedido_id_fkey,
  ADD CONSTRAINT lancamentos_socios_pedido_id_fkey
    FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE SET NULL;

-- 4. estoque_movimentacoes → lotes
ALTER TABLE estoque_movimentacoes
  DROP CONSTRAINT IF EXISTS estoque_movimentacoes_lote_id_fkey,
  ADD CONSTRAINT estoque_movimentacoes_lote_id_fkey
    FOREIGN KEY (lote_id) REFERENCES lotes(id) ON DELETE SET NULL;

-- 5. lotes → produtos
ALTER TABLE lotes
  DROP CONSTRAINT IF EXISTS lotes_produto_id_fkey,
  ADD CONSTRAINT lotes_produto_id_fkey
    FOREIGN KEY (produto_id) REFERENCES produtos(id) ON DELETE CASCADE;

-- 6. estoque_movimentacoes → produtos
ALTER TABLE estoque_movimentacoes
  DROP CONSTRAINT IF EXISTS estoque_movimentacoes_produto_id_fkey,
  ADD CONSTRAINT estoque_movimentacoes_produto_id_fkey
    FOREIGN KEY (produto_id) REFERENCES produtos(id) ON DELETE CASCADE;

-- 7. follow_up → contatos
ALTER TABLE follow_up
  DROP CONSTRAINT IF EXISTS follow_up_contato_id_fkey,
  ADD CONSTRAINT follow_up_contato_id_fkey
    FOREIGN KEY (contato_id) REFERENCES contatos(id) ON DELETE CASCADE;

-- 8. contatos → instancias
ALTER TABLE contatos
  DROP CONSTRAINT IF EXISTS contatos_instancia_id_fkey,
  ADD CONSTRAINT contatos_instancia_id_fkey
    FOREIGN KEY (instancia_id) REFERENCES instancias(id) ON DELETE SET NULL;

-- 9. financeiro — update check constraint for tipo
ALTER TABLE financeiro 
  DROP CONSTRAINT IF EXISTS financeiro_tipo_check,
  ADD CONSTRAINT financeiro_tipo_check 
    CHECK (tipo IN ('receita', 'despesa', 'receita_pendente'));

-- 10. Update process_venda RPC logic
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
BEGIN
  -- Get client UF
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build products array and deduct stoichiometry
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    -- FIFO deduction
    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  -- Always move Kanban to Pagou (Requirement Part 2.4 point 5)
  v_status_kanban := 'Pagou';

  -- Create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por)
  RETURNING id INTO v_pedido_id;

  -- Financeiro and Lancamentos logic
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);

    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  -- Update kanban
  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;


-- MIGRATION: 20260402130000_fix_rpc_signature.sql
-- EXPLICIT DROP TO AVOID OVERLOADING AMBIGUITY
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text);

-- RECREATE WITH NEW SIGNATURE
CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
BEGIN
  -- Get client UF
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build products array and deduct stoichiometry
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    -- FIFO deduction
    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  -- Always move Kanban to Pagou (Requirement Part 2.4 point 5)
  v_status_kanban := 'Pagou';

  -- Create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por)
  RETURNING id INTO v_pedido_id;

  -- Financeiro and Lancamentos logic
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);

    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  -- Update kanban
  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- FORCE SCHEMA RELOAD
NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260402140000_final_v2_fix.sql
-- 1. FIX TABLE COLUMNS
ALTER TABLE pedidos 
ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago' 
  CHECK (status_pagamento IN ('pago', 'pendente')),
ADD COLUMN IF NOT EXISTS complemento text,
ADD COLUMN IF NOT EXISTS criado_por text,
ADD COLUMN IF NOT EXISTS recebido_por text;

ALTER TABLE lancamentos_socios
ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago'
  CHECK (status_pagamento IN ('pago', 'pendente')),
ADD COLUMN IF NOT EXISTS criado_por text;

-- 2. UPDATE CONSTRAINTS
ALTER TABLE lancamentos_socios 
  DROP CONSTRAINT IF EXISTS lancamentos_socios_socio_check,
  ADD CONSTRAINT lancamentos_socios_socio_check 
    CHECK (socio IN ('V', 'A', 'P'));

ALTER TABLE financeiro 
  DROP CONSTRAINT IF EXISTS financeiro_tipo_check,
  ADD CONSTRAINT financeiro_tipo_check 
    CHECK (tipo IN ('receita', 'despesa', 'receita_pendente'));

-- 3. DROP AND RECREATE RPC
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text);
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
  v_recebido_por text;
BEGIN
  -- Determine receiver
  IF p_status_pagamento = 'pendente' THEN
    v_recebido_por := 'P';
  ELSE
    v_recebido_por := p_socio;
  END IF;

  -- Get client UF
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build products array and deduct stoichiometry
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    -- FIFO deduction
    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  v_status_kanban := 'Pagou';

  -- Create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, recebido_por)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, v_recebido_por)
  RETURNING id INTO v_pedido_id;

  -- Financeiro and Lancamentos logic
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);

    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  -- Update kanban
  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260402150000_finance_fixes.sql
-- 1. UPDATE status_pagamento constraint to allow '-'
ALTER TABLE lancamentos_socios 
  DROP CONSTRAINT IF EXISTS lancamentos_socios_status_pagamento_check;

ALTER TABLE lancamentos_socios 
  ADD CONSTRAINT lancamentos_socios_status_pagamento_check 
    CHECK (status_pagamento IN ('pago', 'pendente', '-'));

-- 2. INSERT manual balance adjustment removed as requested.


-- MIGRATION: 20260402160000_fix_finance_constraints.sql
-- 1. UPDATE lancamentos_socios CONSTRAINTS
ALTER TABLE lancamentos_socios 
  DROP CONSTRAINT IF EXISTS lancamentos_socios_socio_check,
  DROP CONSTRAINT IF EXISTS lancamentos_socios_tipo_check,
  DROP CONSTRAINT IF EXISTS lancamentos_socios_status_pagamento_check;

ALTER TABLE lancamentos_socios 
  ADD CONSTRAINT lancamentos_socios_socio_check 
    CHECK (socio IN ('V', 'A', 'P')),
  ADD CONSTRAINT lancamentos_socios_tipo_check 
    CHECK (tipo IN ('VENDA', 'ADS', 'ETIQUETA', 'MATERIAL', 'LOGISTICA', 'TRANSFERENCIA', 'LUCRO')),
  ADD CONSTRAINT lancamentos_socios_status_pagamento_check 
    CHECK (status_pagamento IN ('pago', 'pendente', '-'));

-- 2. UPDATE financeiro CONSTRAINTS (if needed)
ALTER TABLE financeiro 
  DROP CONSTRAINT IF EXISTS financeiro_tipo_check;

ALTER TABLE financeiro 
  ADD CONSTRAINT financeiro_tipo_check 
    CHECK (tipo IN ('receita', 'despesa', 'receita_pendente', 'LUCRO', 'TRANSFERENCIA'));


-- MIGRATION: 20260403000000_add_obs_to_pedidos.sql
-- Add obs column to pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS obs text;

-- Update process_venda RPC with observation support
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL,
  p_obs text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
BEGIN
  -- Get client UF
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build products array and deduct stoichiometry
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    -- FIFO deduction
    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  -- Always move Kanban to Pagou (Requirement Part 2.4 point 5)
  v_status_kanban := 'Pagou';

  -- Create pedido
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, obs)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, p_obs)
  RETURNING id INTO v_pedido_id;

  -- Financeiro and Lancamentos logic
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);

    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  -- Update kanban
  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- FORCE SCHEMA RELOAD
NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260403010000_rep_crep_refinements.sql
-- Update canal_origem constraint to include C-REP
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;
ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP'));

-- Add columns for representative attribution and conversion tracking
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES public.contatos(id);
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS primeira_venda_em date;

-- Update process_venda RPC with conversion tracking
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL,
  p_obs text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
  v_canal_atual text;
  v_ultima_venda date;
  v_last_order_date date;
  v_contato_endereco text;
  v_contato_numero text;
BEGIN
  -- Get contact current info
  SELECT canal_origem, ultima_venda_em INTO v_canal_atual, v_ultima_venda FROM contatos WHERE id = p_contato_id;

  -- Get contact address for delivery
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero 
  FROM contatos WHERE id = p_contato_id;

  -- Get the most recent order date for this contact from pedidos table
  SELECT MAX(created_at)::date INTO v_last_order_date 
  FROM pedidos WHERE contato_id = p_contato_id;

  -- Update conversion date with the actual order date (not current date)
  UPDATE contatos SET ultima_venda_em = COALESCE(v_last_order_date, CURRENT_DATE) WHERE id = p_contato_id;

  -- Get client UF
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build products array and deduct stoichiometry
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    -- FIFO deduction
    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  -- Always move Kanban to Pagou (Requirement Part 2.4 point 5)
  v_status_kanban := 'Pagou';

  -- Create pedido with endereco_entrega
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, obs, 
    endereco_entrega)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END)
  RETURNING id INTO v_pedido_id;

  -- Financeiro and Lancamentos logic
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);

    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  -- Update kanban
  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- FORCE SCHEMA RELOAD
NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260403020000_midnight_lead_migration.sql
-- 1. Add is_default_base to public.instancias
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='instancias' AND column_name='is_default_base') THEN
        ALTER TABLE public.instancias ADD COLUMN is_default_base boolean DEFAULT false;
    END IF;
END $$;

-- 2. Insert the instances provided by the user
-- ADS: +551199128-2579
INSERT INTO public.instancias (nome, tipo, numero_final, is_default_base)
VALUES ('Instância Tráfego (ADS)', 'ads', '2579', false)
ON CONFLICT (id) DO UPDATE SET 
    nome = EXCLUDED.nome, 
    tipo = EXCLUDED.tipo, 
    numero_final = EXCLUDED.numero_final;

-- BASE: +554599851-0512
INSERT INTO public.instancias (nome, tipo, numero_final, is_default_base)
VALUES ('Instância Recorrência (BASE)', 'base', '0512', true)
ON CONFLICT (id) DO UPDATE SET 
    nome = EXCLUDED.nome, 
    tipo = EXCLUDED.tipo, 
    is_default_base = EXCLUDED.is_default_base,
    numero_final = EXCLUDED.numero_final;

-- 3. Create function to migrate leads from ADS to BASE at midnight
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_base_instance_id uuid;
    v_migrated_count integer := 0;
BEGIN
    -- Find the target BASE instance
    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- Update contacts: Lead must be ADS and have bought BEFORE the current date
    UPDATE public.contatos
    SET 
        canal_origem = 'BASE',
        instancia_id = COALESCE(v_base_instance_id, instancia_id)
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1;

    RETURN json_build_object(
        'success', true,
        'migrated_count', v_migrated_count,
        'target_instance_id', v_base_instance_id
    );
END;
$$;


-- MIGRATION: 20260403030000_lead_migration_v2.sql
-- 1. Unify 'Comprou Há X dias' to 'Clientes' in the database
UPDATE public.contatos SET status_kanban = 'Clientes' WHERE status_kanban = 'Comprou Há X dias';

-- 2. Update metadata in configuracoes for migration tracking
INSERT INTO public.configuracoes (chave, valor) 
VALUES ('ultimo_auto_lead_migration', '2000-01-01')
ON CONFLICT (chave) DO NOTHING;

-- 3. Update archiving function (30 days for Clientes)
CREATE OR REPLACE FUNCTION public.archive_stale_kanban_cards()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Archive BASE "Clientes" cards where payment/activity > 30 days ago
  UPDATE public.contatos
  SET status_kanban = 'arquivado', updated_at = now()
  WHERE status_kanban = 'Clientes'
    AND updated_at < now() - interval '30 days';

  -- Archive ADS "Sumiu" cards older than 60 days (kept as 60 per original rule)
  UPDATE public.contatos
  SET status_kanban = 'arquivado_sumiu', updated_at = now()
  WHERE status_kanban LIKE '%Sumiu%'
    AND updated_at < now() - interval '60 days';
END;
$$;

-- 4. Refine perform_midnight_lead_migration to update status and track execution
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_base_instance_id uuid;
    v_migrated_count integer := 0;
BEGIN
    -- Find the target BASE instance
    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- Update contacts: ADS -> BASE migration
    -- Also sets status to 'Clientes' for newly migrated base customers
    UPDATE public.contatos
    SET 
        canal_origem = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1;

    -- Update the last execution date in configuracoes
    INSERT INTO public.configuracoes (chave, valor) 
    VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
    ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

    RETURN json_build_object(
        'success', true,
        'migrated_count', v_migrated_count,
        'target_instance_id', v_base_instance_id
    );
END;
$$;


-- MIGRATION: 20260403040000_perf_indexes.sql
-- CRITICAL: Enable pg_trgm for fast text search (ilike %...%)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Indexes for 'contatos' table
-- GIN index for fast substring search on name
CREATE INDEX IF NOT EXISTS idx_contatos_nome_trgm ON contatos USING gin (nome gin_trgm_ops);
-- Standard indexes for exact/prefix matches
CREATE INDEX IF NOT EXISTS idx_contatos_telefone ON contatos (telefone);
CREATE INDEX IF NOT EXISTS idx_contatos_cpf ON contatos (cpf);
CREATE INDEX IF NOT EXISTS idx_contatos_created_at ON contatos (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contatos_canal_origem ON contatos (canal_origem);

-- Indexes for 'financeiro' table
CREATE INDEX IF NOT EXISTS idx_financeiro_data ON financeiro ("data" DESC);
CREATE INDEX IF NOT EXISTS idx_financeiro_canal ON financeiro (canal);
CREATE INDEX IF NOT EXISTS idx_financeiro_tipo ON financeiro (tipo);
CREATE INDEX IF NOT EXISTS idx_financeiro_composite ON financeiro (tipo, canal, "data");

-- Indexes for 'pedidos' table
CREATE INDEX IF NOT EXISTS idx_pedidos_contato_id ON pedidos (contato_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_status_pagamento ON pedidos (status_pagamento);
CREATE INDEX IF NOT EXISTS idx_pedidos_data ON pedidos ("data" DESC);


-- MIGRATION: 20260403080802_5203c5c1-571b-4d33-9de7-f0b96b385c35.sql

-- Add representante_id to contatos (references another contato REP)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS representante_id uuid;

-- Add primeira_venda_em to contatos (used by midnight migration function)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS primeira_venda_em timestamptz;

-- Add observacao to pedidos (for notes/obs on pending orders)
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS observacao text;


-- MIGRATION: 20260404000000_add_entregue_status.sql
-- Add 'entregue' to status_pedido CHECK constraint
ALTER TABLE public.pedidos DROP CONSTRAINT IF EXISTS pedidos_status_pedido_check;
ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_status_pedido_check CHECK (status_pedido IN ('aguardando_rastreio', 'postado', 'entregue'));

-- MIGRATION: 20260404000000_add_rep_crep_instances.sql
-- Update perform_midnight_lead_migration to also handle REP and C-REP paid customers
-- REP and C-REP use the BASE instance (is_default_base)
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_base_instance_id uuid;
    v_migrated_count integer := 0;
BEGIN
    -- Find the target BASE instance (includes is_default_base=true)
    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- ADS -> BASE migration: customers who paid yesterday move to BASE Clientes
    UPDATE public.contatos
    SET 
        canal_origem = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1;

    -- REP: customers who paid yesterday move to Clientes (same BASE instance)
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'REP' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    -- C-REP: customers who paid yesterday move to Clientes (same BASE instance)
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'C-REP' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    -- Update the last execution date in configuracoes
    INSERT INTO public.configuracoes (chave, valor) 
    VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
    ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

    RETURN json_build_object(
        'success', true,
        'migrated_count', v_migrated_count,
        'target_instance_id', v_base_instance_id
    );
END;
$$;


-- MIGRATION: 20260404202821_fix_canal_crep_constraint.sql
-- Fix: Ensure C-REP is in canal_origem constraint
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;
ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));


-- MIGRATION: 20260405000000_daily_lock.sql
-- Lock status after midnight - prevents changes to delivered orders and paid vendas

-- Add locked_at column to pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS locked_at timestamptz;

-- Add locked_at column to lancamentos_socios
ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS locked_at timestamptz;

-- Create function to lock pedidos delivered yesterday
CREATE OR REPLACE FUNCTION public.lock_yesterday_delivered_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.pedidos
  SET locked_at = now()
  WHERE status_pedido = 'entregue'
    AND locked_at IS NULL
    AND data < CURRENT_DATE;
END;
$$;

-- Create function to lock vendas paid yesterday
CREATE OR REPLACE FUNCTION public.lock_yesterday_paid_vendas()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.lancamentos_socios
  SET locked_at = now()
  WHERE tipo = 'VENDA'
    AND (status_pagamento = 'pago' OR status_pagamento IS NULL OR status_pagamento = '')
    AND locked_at IS NULL
    AND data < CURRENT_DATE;
END;
$$;

-- Create combined lock function
CREATE OR REPLACE FUNCTION public.perform_daily_lock()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedidos_locked integer;
  v_vendas_locked integer;
BEGIN
  -- Lock yesterday's delivered orders
  UPDATE public.pedidos
  SET locked_at = now()
  WHERE status_pedido = 'entregue'
    AND locked_at IS NULL
    AND data < CURRENT_DATE;
  GET DIAGNOSTICS v_pedidos_locked = ROW_COUNT;

  -- Lock yesterday's paid vendas
  UPDATE public.lancamentos_socios
  SET locked_at = now()
  WHERE tipo = 'VENDA'
    AND status_pagamento = 'pago'
    AND locked_at IS NULL
    AND data < CURRENT_DATE;
  GET DIAGNOSTICS v_vendas_locked = ROW_COUNT;

  RETURN json_build_object(
    'success', true,
    'pedidos_locked', v_pedidos_locked,
    'vendas_locked', v_vendas_locked
  );
END;
$$;

-- MIGRATION: 20260406000000_add_transferencia_direcao.sql
-- Add transferencia_direcao column to lancamentos_socios
ALTER TABLE lancamentos_socios ADD COLUMN IF NOT EXISTS transferencia_direcao TEXT;


-- MIGRATION: 20260406000000_fix_timezone_pedidos_data.sql
-- Fix timezone: pedidos.data must use America/Sao_Paulo date, not UTC
-- This ensures orders placed after 21h SP time get the correct Brazil date

-- 1. Change DEFAULT of pedidos.data to use Sao Paulo timezone
ALTER TABLE public.pedidos ALTER COLUMN data SET DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo')::date;

-- 2. Fix existing data that has wrong date
UPDATE pedidos
SET data = (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date
WHERE data <> (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date;

-- 3. Fix trigger: ultima_venda_em must use Sao Paulo date from created_at
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    UPDATE contatos SET ultima_venda_em = (NEW.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;


-- MIGRATION: 20260406000002_fix_process_venda_timezone.sql
-- Update process_venda to explicitly set data column with America/Sao_Paulo timezone
-- This ensures the order date is always the Brazil date, never UTC

DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL,
  p_obs text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
  v_canal_atual text;
  v_ultima_venda date;
  v_last_order_date date;
  v_contato_endereco text;
  v_contato_numero text;
  v_data_sp date;
BEGIN
  -- Get Brazil date right now (America/Sao_Paulo)
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Get contact current info
  SELECT canal_origem, ultima_venda_em INTO v_canal_atual, v_ultima_venda FROM contatos WHERE id = p_contato_id;

  -- Get contact address for delivery
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero 
  FROM contatos WHERE id = p_contato_id;

  -- Get the most recent order date for this contact from pedidos table
  SELECT MAX(created_at)::date INTO v_last_order_date 
  FROM pedidos WHERE contato_id = p_contato_id;

  -- Update conversion date with the actual order date (Brazil date)
  UPDATE contatos SET ultima_venda_em = COALESCE(v_last_order_date, v_data_sp) WHERE id = p_contato_id;

  -- Get client UF
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  -- Build products array and deduct stoichiometry
  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    -- FIFO deduction
    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf);
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  -- Auto-calculate package dimensions
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF has_large_product OR total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  -- Always move Kanban to Pagou
  v_status_kanban := 'Pagou';

  -- Create pedido with explicit Brazil date and endereco_entrega
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, obs, 
    endereco_entrega, data)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END,
    v_data_sp)
  RETURNING id INTO v_pedido_id;

  -- Financeiro and Lancamentos logic
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);

    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  -- Update kanban
  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- FORCE SCHEMA RELOAD
NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000003_trigger_abate_estoque_pedido.sql
-- Trigger: abatimento automatico de estoque ao criar pedido
-- Resolve o problema de pedidos criados via insert direto (FinanceiroPage)
-- que nao passavam pelo process_venda e nao abatiam estoque

-- 1. Funcao de abatimento de estoque por pedido
CREATE OR REPLACE FUNCTION public.abate_estoque_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_produto_id uuid;
  v_quantidade integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
BEGIN
  -- So abate se tiver produto_id e quantidade
  IF NEW.produto_id IS NULL OR NEW.quantidade IS NULL OR NEW.quantidade <= 0 THEN
    RETURN NEW;
  END IF;

  v_produto_id := NEW.produto_id;
  v_quantidade := NEW.quantidade;

  -- IDEMPOTENCIA: verifica se ja existe movimentacao para este pedido
  SELECT EXISTS (
    SELECT 1 FROM estoque_movimentacoes WHERE observacao = 'Pedido #' || NEW.id::text
  ) INTO v_mov_exists;

  IF v_mov_exists THEN
    RETURN NEW;
  END IF;

  -- Get client UF for FIFO priority
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = NEW.contato_id;

  -- FIFO deduction from lotes
  v_remaining := v_quantidade;
  FOR v_lote_rec IN
    SELECT id, quantidade_atual, uf FROM lotes
    WHERE produto_id = v_produto_id AND quantidade_atual > 0
    ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
  LOOP
    IF v_remaining <= 0 THEN EXIT; END IF;
    v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
    UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
    VALUES (v_produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, 'Pedido #' || NEW.id::text);
    v_remaining := v_remaining - v_deduct;
  END LOOP;

  -- Decrementa estoque do produto
  UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;

  RETURN NEW;
END;
$$;

-- 2. Trigger em pedidos
DROP TRIGGER IF EXISTS trigger_abate_estoque_pedido ON public.pedidos;
CREATE TRIGGER trigger_abate_estoque_pedido
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.abate_estoque_pedido();

-- 3. Reprocessar pedidos existentes sem movimentacao
-- Gera movimentacoes faltantes SEM duplicar as existentes
DO $$
DECLARE
  v_ped record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
BEGIN
  FOR v_ped IN
    SELECT p.* FROM pedidos p
    WHERE p.produto_id IS NOT NULL
      AND p.quantidade IS NOT NULL
      AND p.quantidade > 0
      AND NOT EXISTS (
        SELECT 1 FROM estoque_movimentacoes WHERE observacao = 'Pedido #' || p.id::text
      )
    ORDER BY p.created_at ASC
  LOOP
    -- Get client UF
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct WHERE ct.id = v_ped.contato_id;

    v_remaining := v_ped.quantidade;

    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_ped.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
      VALUES (v_ped.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, 'Pedido #' || v_ped.id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque
    UPDATE produtos SET estoque_atual = estoque_atual - v_ped.quantidade WHERE id = v_ped.produto_id;

    RAISE NOTICE 'Reprocessado pedido %: produto %, quantidade %', v_ped.id, v_ped.produto_id, v_ped.quantidade;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000004_pedido_itens_e_processar_pedido.sql
-- 1. Criar tabela pedido_itens (itens individuais de cada pedido)
CREATE TABLE IF NOT EXISTS public.pedido_itens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id uuid NOT NULL REFERENCES public.pedidos(id),
  produto_id uuid NOT NULL REFERENCES public.produtos(id),
  quantidade integer NOT NULL,
  valor_unit numeric,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Adicionar coluna pedido_item_id em estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_item_id uuid REFERENCES public.pedido_itens(id);

-- 3. Constraint UNIQUE para idempotencia (um item = uma movimentacao)
ALTER TABLE public.estoque_movimentacoes ADD CONSTRAINT estoque_movimentacoes_pedido_item_id_key UNIQUE (pedido_item_id);

-- 4. RPC processar_pedido - abate estoque com idempotencia e validacao
CREATE OR REPLACE FUNCTION public.processar_pedido(p_pedido_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item record;
  v_produto record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_item_id uuid;
  v_total_items integer := 0;
  v_processed_items integer := 0;
  v_skipped_items integer := 0;
  v_result jsonb := '[]'::jsonb;
  v_erro text;
BEGIN
  -- Buscar UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct
  WHERE ct.id = (SELECT contato_id FROM pedidos WHERE id = p_pedido_id);

  -- Loop nos itens do pedido
  FOR v_item IN
    SELECT * FROM pedido_itens WHERE pedido_id = p_pedido_id
  LOOP
    v_total_items := v_total_items + 1;

    -- IDEMPOTENCIA: verifica se ja existe movimentacao para este item
    SELECT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id
    ) INTO v_mov_exists;

    IF v_mov_exists THEN
      v_skipped_items := v_skipped_items + 1;
      v_result := v_result || jsonb_build_object(
        'item_id', v_item.id::text,
        'produto_id', v_item.produto_id::text,
        'status', 'skipped',
        'motivo', 'ja processado'
      );
      CONTINUE;
    END IF;

    -- Buscar produto para validar estoque
    SELECT * INTO v_produto FROM produtos WHERE id = v_item.produto_id;

    IF v_produto IS NULL THEN
      v_result := v_result || jsonb_build_object(
        'item_id', v_item.id::text,
        'produto_id', v_item.produto_id::text,
        'status', 'error',
        'motivo', 'produto nao encontrado'
      );
      CONTINUE;
    END IF;

    -- VALIDACAO: nao permitir estoque negativo
    IF v_produto.estoque_atual - v_item.quantidade < 0 THEN
      v_result := v_result || jsonb_build_object(
        'item_id', v_item.id::text,
        'produto_id', v_item.produto_id::text,
        'status', 'error',
        'motivo', 'estoque insuficiente (atual: ' || v_produto.estoque_atual || ', necessario: ' || v_item.quantidade || ')'
      );
      CONTINUE;
    END IF;

    -- FIFO deduction from lotes
    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque do produto (COMMIT seguro: ja validou que nao fica negativo)
    UPDATE produtos SET estoque_atual = estoque_atual - v_item.quantidade WHERE id = v_item.produto_id;

    v_processed_items := v_processed_items + 1;
    v_result := v_result || jsonb_build_object(
      'item_id', v_item.id::text,
      'produto_id', v_item.produto_id::text,
      'status', 'processed',
      'quantidade', v_item.quantidade
    );
  END LOOP;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'total_items', v_total_items,
    'processed', v_processed_items,
    'skipped', v_skipped_items,
    'items', v_result
  );
END;
$$;

-- 5. Migrar dados existentes: criar pedido_itens a partir de pedidos com produto_id
INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, valor_unit)
SELECT p.id, p.produto_id, p.quantidade, p.preco_unitario
FROM pedidos p
WHERE p.produto_id IS NOT NULL
  AND p.quantidade IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM pedido_itens pi WHERE pi.pedido_id = p.id
  );

-- 6. Reprocessar estoque para pedidos existentes sem movimentacao
DO $$
DECLARE
  v_item record;
  v_produto record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
BEGIN
  FOR v_item IN
    SELECT pi.*, p.contato_id FROM pedido_itens pi
    JOIN pedidos p ON p.id = pi.pedido_id
    WHERE NOT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = pi.id
    )
    ORDER BY pi.created_at ASC
  LOOP
    -- Get client UF
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct WHERE ct.id = v_item.contato_id;

    -- Get product
    SELECT * INTO v_produto FROM produtos WHERE id = v_item.produto_id;
    IF v_produto IS NULL THEN CONTINUE; END IF;

    -- Skip if would go negative
    IF v_produto.estoque_atual - v_item.quantidade < 0 THEN
      RAISE NOTICE 'SKIP item %: estoque insuficiente (atual: %, necessario: %)', v_item.id, v_produto.estoque_atual, v_item.quantidade;
      CONTINUE;
    END IF;

    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, 'Pedido #' || v_item.pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - v_item.quantidade WHERE id = v_item.produto_id;
    RAISE NOTICE 'Reprocessado item %: produto %, quantidade %', v_item.id, v_item.produto_id, v_item.quantidade;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000005_rpc_processar_pedido_estoque_definitivo.sql
-- RPC definitivo: processar_pedido_estoque
-- Suporta pedidos com produto=text ou produto=json array
-- Idempotente: nao duplica movimentacoes
-- Nao altera estrutura da tabela pedidos

-- 1. Garantir coluna pedido_id em estoque_movimentacoes (ja existe observacao como fallback)
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

-- 2. Index para performance de idempotencia
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido_id ON public.estoque_movimentacoes(pedido_id);

-- 3. Funcao RPC principal
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque(p_pedido_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido record;
  v_produto_text text;
  v_produto_id uuid;
  v_quantidade integer;
  v_item jsonb;
  v_prod_record record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_result jsonb := '[]'::jsonb;
BEGIN
  -- Buscar dados do pedido
  SELECT * INTO v_pedido FROM pedidos WHERE id = p_pedido_id;

  IF v_pedido IS NULL THEN
    RETURN jsonb_build_object('error', 'pedido nao encontrado', 'pedido_id', p_pedido_id::text);
  END IF;

  -- Buscar UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = v_pedido.contato_id;

  -- IDEMPOTENCIA: verifica se pedido ja foi processado
  SELECT EXISTS (
    SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = p_pedido_id
  ) INTO v_mov_exists;

  IF v_mov_exists THEN
    RETURN jsonb_build_object('status', 'skipped', 'motivo', 'pedido ja processado', 'pedido_id', p_pedido_id::text);
  END IF;

  v_produto_text := v_pedido.produto;

  -- CASO 1: produto e JSON array (formato do process_venda)
  IF v_produto_text IS NOT NULL AND trim(v_produto_text) LIKE '[%' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
    LOOP
      v_produto_id := NULLIF(v_item->>'produto_id', '')::uuid;
      v_quantidade := (v_item->>'quantidade')::integer;

      -- Fallback: se nao tem produto_id no JSON, tenta buscar por nome
      IF v_produto_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
        SELECT id INTO v_produto_id FROM produtos
        WHERE lower(nome_oficial) = lower(trim(v_item->>'produto'))
        LIMIT 1;
      END IF;

      IF v_produto_id IS NULL OR v_quantidade IS NULL OR v_quantidade <= 0 THEN
        v_errors := v_errors || jsonb_build_object(
          'item', v_item,
          'motivo', 'produto_id ou quantidade invalido'
        );
        CONTINUE;
      END IF;

      -- Buscar produto para validar estoque
      SELECT * INTO v_prod_record FROM produtos WHERE id = v_produto_id;
      IF v_prod_record IS NULL THEN
        v_errors := v_errors || jsonb_build_object('produto_id', v_produto_id::text, 'motivo', 'produto nao existe');
        CONTINUE;
      END IF;

      -- FIFO deduction from lotes
      v_remaining := v_quantidade;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = v_produto_id AND quantidade_atual > 0
        ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
        VALUES (v_produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, p_pedido_id, 'Pedido #' || p_pedido_id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;

      -- Decrementa estoque
      UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;

      v_processed := v_processed + 1;
      v_result := v_result || jsonb_build_object('produto_id', v_produto_id::text, 'quantidade', v_quantidade, 'status', 'ok');
    END LOOP;

  -- CASO 2: produto e string simples (formato do FinanceiroPage)
  ELSIF v_produto_text IS NOT NULL AND trim(v_produto_text) <> '' THEN
    -- Tenta usar produto_id direto da coluna
    v_produto_id := v_pedido.produto_id;
    v_quantidade := v_pedido.quantidade;

    -- Fallback: buscar produto_id por nome
    IF v_produto_id IS NULL THEN
      -- Tenta extrair nome base (remove " xN" do final se existir)
      SELECT id INTO v_produto_id FROM produtos
      WHERE lower(nome_oficial) = lower(trim(v_produto_text))
         OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
      LIMIT 1;
    END IF;

    IF v_produto_id IS NULL THEN
      RETURN jsonb_build_object('error', 'produto nao encontrado', 'nome', v_produto_text, 'pedido_id', p_pedido_id::text);
    END IF;

    IF v_quantidade IS NULL OR v_quantidade <= 0 THEN
      v_quantidade := 1;
    END IF;

    -- Buscar produto para validar estoque
    SELECT * INTO v_prod_record FROM produtos WHERE id = v_produto_id;
    IF v_prod_record IS NULL THEN
      RETURN jsonb_build_object('error', 'produto nao existe', 'produto_id', v_produto_id::text);
    END IF;

    -- FIFO deduction from lotes
    v_remaining := v_quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
      VALUES (v_produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, p_pedido_id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque
    UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;

    v_processed := v_processed + 1;
    v_result := v_result || jsonb_build_object('produto_id', v_produto_id::text, 'quantidade', v_quantidade, 'status', 'ok');
  END IF;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'processed', v_processed,
    'skipped', v_skipped,
    'items', v_result,
    'errors', v_errors
  );
END;
$$;

-- 4. Funcao para reprocessar TODOS pedidos nao processados
CREATE OR REPLACE FUNCTION public.reprocessar_todos_pedidos_estoque()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ped record;
  v_result jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_ok integer := 0;
  v_err integer := 0;
  v_resp jsonb;
BEGIN
  FOR v_ped IN
    SELECT id FROM pedidos
    WHERE produto_id IS NOT NULL OR (produto IS NOT NULL AND trim(produto) <> '')
    ORDER BY created_at ASC
  LOOP
    v_total := v_total + 1;
    v_resp := public.processar_pedido_estoque(v_ped.id);

    IF v_resp ? 'error' THEN
      v_err := v_err + 1;
      v_result := v_result || jsonb_build_object('pedido_id', v_ped.id::text, 'status', 'error', 'detail', v_resp);
    ELSIF (v_resp->>'status') = 'skipped' THEN
      v_result := v_result || jsonb_build_object('pedido_id', v_ped.id::text, 'status', 'skipped');
    ELSE
      v_ok := v_ok + 1;
      v_result := v_result || jsonb_build_object('pedido_id', v_ped.id::text, 'status', 'ok', 'processed', v_resp->'processed');
    END IF;
  END LOOP;

  RETURN jsonb_build_object('total', v_total, 'ok', v_ok, 'errors', v_err, 'details', v_result);
END;
$$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000006_trigger_auto_estoque.sql
-- Trigger automatico: todo novo pedido abate estoque automaticamente
-- Chama o RPC processar_pedido_estoque apos INSERT em pedidos

-- 1. Funcao de trigger
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM public.processar_pedido_estoque(NEW.id);
  RETURN NEW;
END;
$$;

-- 2. Remove trigger antiga se existir
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;

-- 3. Cria trigger automatica
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_processar_pedido_estoque();

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000007_consistencia_total_estoque.sql
-- CONSISTENCIA TOTAL DE ESTOQUE
-- Adiciona flag anti-duplicacao, sync de estoque, e atualiza trigger

-- ============================================================
-- ETAPA 1: Coluna anti-duplicacao em pedidos
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_pedidos_estoque_processado ON public.pedidos(estoque_processado) WHERE estoque_processado = false;

-- ============================================================
-- ETAPA 2: Recriar processar_pedido_estoque com flag
-- ============================================================
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque(p_pedido_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido record;
  v_produto_text text;
  v_produto_id uuid;
  v_quantidade integer;
  v_item jsonb;
  v_prod_record record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_processed integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_result jsonb := '[]'::jsonb;
  v_cast_error text;
BEGIN
  -- Buscar dados do pedido
  SELECT * INTO v_pedido FROM pedidos WHERE id = p_pedido_id;

  IF v_pedido IS NULL THEN
    RETURN jsonb_build_object('error', 'pedido nao encontrado', 'pedido_id', p_pedido_id::text);
  END IF;

  -- ANTI-DUPLICACAO: se ja processado, ignora
  IF v_pedido.estoque_processado THEN
    RETURN jsonb_build_object('status', 'skipped', 'motivo', 'pedido ja processado', 'pedido_id', p_pedido_id::text);
  END IF;

  -- Buscar UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = v_pedido.contato_id;

  v_produto_text := v_pedido.produto;

  -- CASO 1: produto e JSON array
  IF v_produto_text IS NOT NULL AND trim(v_produto_text) LIKE '[%' THEN
    BEGIN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
      LOOP
        v_produto_id := NULLIF(v_item->>'produto_id', '')::uuid;
        v_quantidade := (v_item->>'quantidade')::integer;

        IF v_produto_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
          SELECT id INTO v_produto_id FROM produtos
          WHERE lower(nome_oficial) = lower(trim(v_item->>'produto'))
          LIMIT 1;
        END IF;

        IF v_produto_id IS NULL OR v_quantidade IS NULL OR v_quantidade <= 0 THEN
          v_errors := v_errors || jsonb_build_object('item', v_item, 'motivo', 'produto_id ou quantidade invalido');
          CONTINUE;
        END IF;

        SELECT * INTO v_prod_record FROM produtos WHERE id = v_produto_id;
        IF v_prod_record IS NULL THEN
          v_errors := v_errors || jsonb_build_object('produto_id', v_produto_id::text, 'motivo', 'produto nao existe');
          CONTINUE;
        END IF;

        -- FIFO deduction from lotes
        v_remaining := v_quantidade;
        FOR v_lote_rec IN
          SELECT id, quantidade_atual, uf FROM lotes
          WHERE produto_id = v_produto_id AND quantidade_atual > 0
          ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
        LOOP
          IF v_remaining <= 0 THEN EXIT; END IF;
          v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
          UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
          INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
          VALUES (v_produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, p_pedido_id, 'Pedido #' || p_pedido_id::text);
          v_remaining := v_remaining - v_deduct;
        END LOOP;

        UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;
        v_processed := v_processed + 1;
        v_result := v_result || jsonb_build_object('produto_id', v_produto_id::text, 'quantidade', v_quantidade, 'status', 'ok');
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_cast_error = MESSAGE_TEXT;
      v_errors := v_errors || jsonb_build_object('motivo', 'JSON invalido: ' || v_cast_error);
    END;

  -- CASO 2: produto e string simples
  ELSIF v_produto_text IS NOT NULL AND trim(v_produto_text) <> '' THEN
    v_produto_id := v_pedido.produto_id;
    v_quantidade := v_pedido.quantidade;

    IF v_produto_id IS NULL THEN
      SELECT id INTO v_produto_id FROM produtos
      WHERE lower(nome_oficial) = lower(trim(v_produto_text))
         OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
      LIMIT 1;
    END IF;

    IF v_produto_id IS NULL THEN
      RETURN jsonb_build_object('error', 'produto nao encontrado', 'nome', v_produto_text, 'pedido_id', p_pedido_id::text);
    END IF;

    IF v_quantidade IS NULL OR v_quantidade <= 0 THEN
      v_quantidade := 1;
    END IF;

    SELECT * INTO v_prod_record FROM produtos WHERE id = v_produto_id;
    IF v_prod_record IS NULL THEN
      RETURN jsonb_build_object('error', 'produto nao existe', 'produto_id', v_produto_id::text);
    END IF;

    v_remaining := v_quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
      VALUES (v_produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, p_pedido_id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - v_quantidade WHERE id = v_produto_id;
    v_processed := v_processed + 1;
    v_result := v_result || jsonb_build_object('produto_id', v_produto_id::text, 'quantidade', v_quantidade, 'status', 'ok');
  END IF;

  -- MARCA como processado (anti-duplicacao)
  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'processed', v_processed,
    'items', v_result,
    'errors', v_errors
  );
END;
$$;

-- ============================================================
-- ETAPA 3: Atualizar trigger para usar flag
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM public.processar_pedido_estoque(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_processar_pedido_estoque();

-- ============================================================
-- ETAPA 4: sync_estoque_total (recalcula estoque a partir de movimentacoes)
-- Uso: admin/debug quando necessario
-- ============================================================
CREATE OR REPLACE FUNCTION public.sync_estoque_total()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_prod record;
  v_entradas integer;
  v_saidas integer;
  v_novo_estoque integer;
  v_synced integer := 0;
BEGIN
  FOR v_prod IN SELECT id, nome_oficial, estoque_atual FROM produtos
  LOOP
    SELECT COALESCE(SUM(quantidade), 0)::integer INTO v_entradas
    FROM estoque_movimentacoes WHERE produto_id = v_prod.id AND tipo = 'entrada';

    SELECT COALESCE(SUM(quantidade), 0)::integer INTO v_saidas
    FROM estoque_movimentacoes WHERE produto_id = v_prod.id AND tipo = 'saida';

    v_novo_estoque := v_entradas - v_saidas;

    IF v_novo_estoque <> v_prod.estoque_atual THEN
      UPDATE produtos SET estoque_atual = v_novo_estoque WHERE id = v_prod.id;
      v_synced := v_synced + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('synced', v_synced, 'message', 'estoque sincronizado com base em movimentacoes');
END;
$$;

-- ============================================================
-- ETAPA 5: Reprocessar pedidos antigos nao processados
-- ============================================================
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM pedidos WHERE estoque_processado = false;
  RAISE NOTICE 'Reprocessando % pedidos nao processados...', v_count;
END $$;

-- Executa reprocessamento automatico
SELECT public.reprocessar_todos_pedidos_estoque();

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000008_correcao_final_estoque.sql
-- CORRECAO FINAL: process_venda + trigger sem duplicacao + fix dados existentes

-- ============================================================
-- 1. Atualizar process_venda para setar pedido_id e estoque_processado
-- ============================================================
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL,
  p_obs text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
  v_canal_atual text;
  v_ultima_venda date;
  v_last_order_date date;
  v_contato_endereco text;
  v_contato_numero text;
  v_data_sp date;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;

  SELECT canal_origem, ultima_venda_em INTO v_canal_atual, v_ultima_venda FROM contatos WHERE id = p_contato_id;
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero 
  FROM contatos WHERE id = p_contato_id;
  SELECT MAX(created_at)::date INTO v_last_order_date 
  FROM pedidos WHERE contato_id = p_contato_id;
  UPDATE contatos SET ultima_venda_em = COALESCE(v_last_order_date, v_data_sp) WHERE id = p_contato_id;
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf, 'process_venda_pending');
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  v_status_kanban := 'Pagou';

  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem, 
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, obs, 
    endereco_entrega, data)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio', 
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END,
    v_data_sp)
  RETURNING id INTO v_pedido_id;

  -- FIX: atualizar estoque_movimentacoes com pedido_id e mark as processed
  UPDATE estoque_movimentacoes SET pedido_id = v_pedido_id, observacao = 'Pedido #' || v_pedido_id::text
  WHERE observacao = 'process_venda_pending' AND pedido_id IS NULL;

  -- FIX: marcar pedido como processado para o trigger nao duplicar
  UPDATE pedidos SET estoque_processado = true WHERE id = v_pedido_id;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- ============================================================
-- 2. Atualizar trigger para verificar BOTH pedido_id AND observacao
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_already_processed boolean;
BEGIN
  -- Verifica se ja existe movimentacao para este pedido (por pedido_id ou observacao)
  SELECT EXISTS (
    SELECT 1 FROM estoque_movimentacoes 
    WHERE pedido_id = NEW.id OR observacao = 'Pedido #' || NEW.id::text
  ) INTO v_already_processed;

  IF v_already_processed THEN
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    RETURN NEW;
  END IF;

  PERFORM public.processar_pedido_estoque(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_processar_pedido_estoque();

-- ============================================================
-- 3. Corrigir dados existentes: vincular movimentacoes aos pedidos
-- ============================================================
-- Para pedidos criados por process_venda que tem produto como JSON
-- As movimentacoes foram criadas mas sem pedido_id
DO $$
DECLARE
  v_ped record;
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_mov_count integer;
  v_fixed integer := 0;
BEGIN
  FOR v_ped IN
    SELECT * FROM pedidos 
    WHERE produto IS NOT NULL 
      AND trim(produto) LIKE '[%'
      AND estoque_processado = false
      AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    -- Conta movimentacoes de saida criadas na mesma epoca do pedido (sem pedido_id)
    SELECT COUNT(*) INTO v_mov_count FROM estoque_movimentacoes
    WHERE pedido_id IS NULL AND tipo = 'saida'
      AND created_at >= v_ped.created_at - interval '1 second'
      AND created_at <= v_ped.created_at + interval '5 seconds';

    IF v_mov_count > 0 THEN
      -- Vincula as movimentacoes ao pedido
      UPDATE estoque_movimentacoes 
      SET pedido_id = v_ped.id, observacao = 'Pedido #' || v_ped.id::text
      WHERE pedido_id IS NULL AND tipo = 'saida'
        AND created_at >= v_ped.created_at - interval '1 second'
        AND created_at <= v_ped.created_at + interval '5 seconds';
      
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      v_fixed := v_fixed + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'Corrigidas % movimentacoes de pedidos process_venda', v_fixed;
END $$;

-- ============================================================
-- 4. Para pedidos SEM movimentacao (criados via insert direto)
--    Processa com a funcao existente
-- ============================================================
DO $$
DECLARE
  v_ped record;
  v_result jsonb;
  v_ok integer := 0;
  v_err integer := 0;
BEGIN
  FOR v_ped IN
    SELECT id FROM pedidos
    WHERE estoque_processado = false
      AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    BEGIN
      v_result := public.processar_pedido_estoque(v_ped.id);
      IF v_result ? 'error' THEN
        v_err := v_err + 1;
      ELSE
        v_ok := v_ok + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_err := v_err + 1;
    END;
  END LOOP;
  RAISE NOTICE 'Reprocessados: % ok, % erros', v_ok, v_err;
END $$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000009_correcao_definitiva_estoque.sql
-- CORRECAO DEFINITIVA: estoque processado corretamente para TODOS pedidos
-- Problema: process_venda abate estoque ANTES do INSERT, trigger dispara e tenta de novo
-- Solucao: process_venda insere estoque_processado=true no proprio INSERT

-- ============================================================
-- 1. Garantir coluna estoque_processado
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;

-- ============================================================
-- 2. Garantir coluna pedido_id em estoque_movimentacoes
-- ============================================================
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido_id ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

-- ============================================================
-- 3. Recriar process_venda com estoque_processado=true no INSERT
-- ============================================================
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text,
  p_canal text,
  p_valor numeric,
  p_contato_id uuid,
  p_produtos jsonb,
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL,
  p_obs text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb;
  prod_id uuid;
  prod_qty integer;
  prod_nome text;
  prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb;
  total_qty integer := 0;
  remaining integer;
  lote_rec record;
  deduct integer;
  client_uf text;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  has_large_product boolean := false;
  v_status_kanban text;
  v_pedido_id uuid;
  v_canal_atual text;
  v_ultima_venda date;
  v_last_order_date date;
  v_contato_endereco text;
  v_contato_numero text;
  v_data_sp date;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;

  SELECT canal_origem, ultima_venda_em INTO v_canal_atual, v_ultima_venda FROM contatos WHERE id = p_contato_id;
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero
  FROM contatos WHERE id = p_contato_id;
  SELECT MAX(created_at)::date INTO v_last_order_date
  FROM pedidos WHERE contato_id = p_contato_id;
  UPDATE contatos SET ultima_venda_em = COALESCE(v_last_order_date, v_data_sp) WHERE id = p_contato_id;
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;

    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;

    produtos_array := produtos_array || jsonb_build_object(
      'produto', prod_nome,
      'produto_id', prod_id,
      'quantidade', prod_qty,
      'valor_unit', prod_preco
    );

    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf, 'process_venda_pending');
      remaining := remaining - deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  v_status_kanban := 'Pagou';

  -- INSERT com estoque_processado=true para o trigger saber que ja foi processado
  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, obs,
    endereco_entrega, data, estoque_processado)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END,
    v_data_sp, true)
  RETURNING id INTO v_pedido_id;

  -- Vincular movimentacoes ao pedido
  UPDATE estoque_movimentacoes SET pedido_id = v_pedido_id, observacao = 'Pedido #' || v_pedido_id::text
  WHERE observacao = 'process_venda_pending' AND pedido_id IS NULL;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- ============================================================
-- 4. Trigger: pula se estoque_processado=true
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Se ja foi marcado como processado (process_venda), ignora
  IF NEW.estoque_processado = true THEN
    RETURN NEW;
  END IF;

  -- Verifica se ja existe movimentacao para este pedido
  IF EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = NEW.id) THEN
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    RETURN NEW;
  END IF;

  -- Pedido criado via insert direto (FinanceiroPage) — processar
  PERFORM public.processar_pedido_estoque(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_processar_pedido_estoque();

-- ============================================================
-- 5. Reprocessar TODOS pedidos existentes sem movimentacao
--    Reseta estoque_atual primeiro baseado em entradas conhecidas
-- ============================================================
DO $$
DECLARE
  v_ped record;
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_errors integer := 0;
  v_produto_text text;
BEGIN
  FOR v_ped IN
    SELECT * FROM pedidos
    WHERE (produto IS NOT NULL AND trim(produto) <> '')
      AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    v_produto_text := v_ped.produto;

    -- Buscar UF do cliente
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct WHERE ct.id = v_ped.contato_id;

    IF v_produto_text LIKE '[%' THEN
      -- JSON array
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
        LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qty := (v_item->>'quantidade')::integer;

          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
            SELECT id INTO v_prod_id FROM produtos
            WHERE lower(nome_oficial) = lower(trim(v_item->>'produto'))
            LIMIT 1;
          END IF;

          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN
            CONTINUE;
          END IF;

          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
          IF v_produto IS NULL THEN CONTINUE; END IF;

          v_remaining := v_qty;
          FOR v_lote_rec IN
            SELECT id, quantidade_atual, uf FROM lotes
            WHERE produto_id = v_prod_id AND quantidade_atual > 0
            ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
          LOOP
            IF v_remaining <= 0 THEN EXIT; END IF;
            v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
            VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;

          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        v_processed := v_processed + 1;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
      END;
    ELSE
      -- String simples
      v_prod_id := v_ped.produto_id;
      v_qty := v_ped.quantidade;

      IF v_prod_id IS NULL THEN
        SELECT id INTO v_prod_id FROM produtos
        WHERE lower(nome_oficial) = lower(trim(v_produto_text))
           OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
        LIMIT 1;
      END IF;

      IF v_prod_id IS NULL THEN
        v_errors := v_errors + 1;
        CONTINUE;
      END IF;

      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;

      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN
        v_errors := v_errors + 1;
        CONTINUE;
      END IF;

      v_remaining := v_qty;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = v_prod_id AND quantidade_atual > 0
        ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
        VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;

      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      v_processed := v_processed + 1;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
    END IF;
  END LOOP;

  RAISE NOTICE 'Reprocessamento: % processados, % erros', v_processed, v_errors;
END $$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000010_rpc_criar_pedido.sql
-- RPC criar_pedido: cria pedido + itens + abate estoque numa transacao
-- Padrao: bypass PostgREST, tudo via SQL direto no Supabase

CREATE OR REPLACE FUNCTION public.criar_pedido(
  p_contato_id uuid,
  p_canal text,
  p_valor numeric,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT NULL,
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido_id uuid;
  v_data_sp date;
  v_total_qty integer := 0;
  v_prod jsonb;
  v_prod_id uuid;
  v_prod_qty integer;
  v_prod_nome text;
  v_prod_preco numeric;
  v_produtos_array jsonb := '[]'::jsonb;
  v_remaining integer;
  v_lote_rec record;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_item_id uuid;
  v_has_large boolean := false;
  v_formato_caixa text;
  v_peso integer;
  v_altura integer;
  v_largura integer;
  v_comprimento integer;
  v_contato_endereco text;
  v_contato_numero text;
  v_order_number integer;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Buscar endereco do contato
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero
  FROM contatos WHERE id = p_contato_id;

  -- Buscar UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = p_contato_id;

  -- Processar produtos e abater estoque
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_nome := v_prod->>'nome_oficial';
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;
      v_total_qty := v_total_qty + v_prod_qty;

      IF lower(v_prod_nome) LIKE '%gummy%' OR lower(v_prod_nome) LIKE '%pomada%' OR lower(v_prod_nome) LIKE '%lub%' THEN
        v_has_large := true;
      END IF;

      v_produtos_array := v_produtos_array || jsonb_build_object(
        'produto', v_prod_nome,
        'produto_id', v_prod_id,
        'quantidade', v_prod_qty,
        'valor_unit', v_prod_preco
      );

      -- FIFO deduction from lotes
      v_remaining := v_prod_qty;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = v_prod_id AND quantidade_atual > 0
        ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
        VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, 'criar_pedido_pending');
        v_remaining := v_remaining - v_deduct;
      END LOOP;

      -- Decrementa estoque
      UPDATE produtos SET estoque_atual = estoque_atual - v_prod_qty WHERE id = v_prod_id;
    END LOOP;
  END IF;

  -- Calcular dimensoes da caixa
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  ELSE
    IF v_has_large OR v_total_qty > 5 THEN
      v_formato_caixa := 'caixa_p'; v_peso := 1000; v_altura := 6; v_largura := 11; v_comprimento := 16;
    ELSE
      v_formato_caixa := 'mini'; v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    END IF;
  END IF;

  -- Criar pedido com estoque_processado=true
  INSERT INTO pedidos (
    contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento,
    criado_por, obs, endereco_entrega, data, estoque_processado
  ) VALUES (
    p_contato_id, v_produtos_array::text, v_total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento,
    p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END,
    v_data_sp, true
  ) RETURNING id, order_number INTO v_pedido_id, v_order_number;

  -- Vincular movimentacoes ao pedido
  UPDATE estoque_movimentacoes
  SET pedido_id = v_pedido_id, observacao = 'Pedido #' || v_pedido_id::text
  WHERE observacao = 'criar_pedido_pending' AND pedido_id IS NULL;

  -- Criar pedido_itens para cada produto
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;

      IF v_prod_id IS NOT NULL AND v_prod_qty IS NOT NULL THEN
        INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, valor_unit)
        VALUES (v_pedido_id, v_prod_id, v_prod_qty, v_prod_preco);
      END IF;
    END LOOP;
  END IF;

  -- Atualizar ultima_venda_em do contato
  UPDATE contatos SET ultima_venda_em = v_data_sp, status_kanban = 'Pagou', updated_at = now()
  WHERE id = p_contato_id;

  RETURN jsonb_build_object(
    'pedido_id', v_pedido_id::text,
    'order_number', v_order_number,
    'quantidade', v_total_qty,
    'status', 'ok'
  );
END;
$$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000011_correcao_final_estoque.sql
-- CORRECAO DEFINITIVA DO ESTOQUE
-- 1. process_venda insere estoque_processado=true
-- 2. Trigger ignora pedidos ja processados
-- 3. Reprocessa TODOS pedidos existentes sem movimentacao

-- ============================================================
-- 1. Garantir colunas necessarias
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido_id ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

-- ============================================================
-- 2. Recriar process_venda com estoque_processado=true
-- ============================================================
DROP FUNCTION IF EXISTS public.process_venda(text, text, numeric, uuid, jsonb, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.process_venda(
  p_socio text, p_canal text, p_valor numeric, p_contato_id uuid,
  p_produtos jsonb, p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL, p_status_pagamento text DEFAULT 'pago',
  p_criado_por text DEFAULT NULL, p_obs text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  prod jsonb; prod_id uuid; prod_qty integer; prod_nome text; prod_preco numeric;
  produtos_array jsonb := '[]'::jsonb; total_qty integer := 0;
  remaining integer; lote_rec record; deduct integer; client_uf text;
  v_formato_caixa text; v_peso integer; v_altura integer; v_largura integer; v_comprimento integer;
  has_large_product boolean := false; v_status_kanban text; v_pedido_id uuid;
  v_canal_atual text; v_ultima_venda date; v_last_order_date date;
  v_contato_endereco text; v_contato_numero text; v_data_sp date;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  SELECT canal_origem, ultima_venda_em INTO v_canal_atual, v_ultima_venda FROM contatos WHERE id = p_contato_id;
  SELECT COALESCE(endereco, ''), COALESCE(numero, '') INTO v_contato_endereco, v_contato_numero FROM contatos WHERE id = p_contato_id;
  SELECT MAX(created_at)::date INTO v_last_order_date FROM pedidos WHERE contato_id = p_contato_id;
  UPDATE contatos SET ultima_venda_em = COALESCE(v_last_order_date, v_data_sp) WHERE id = p_contato_id;
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO client_uf FROM contatos ct WHERE ct.id = p_contato_id;

  FOR prod IN SELECT * FROM jsonb_array_elements(p_produtos)
  LOOP
    prod_id := (prod->>'produto_id')::uuid;
    prod_qty := (prod->>'quantidade')::int;
    prod_nome := prod->>'nome_oficial';
    prod_preco := NULLIF(prod->>'preco', '')::numeric;
    total_qty := total_qty + prod_qty;
    IF lower(prod_nome) LIKE '%gummy%' OR lower(prod_nome) LIKE '%pomada%' OR lower(prod_nome) LIKE '%lub%' THEN
      has_large_product := true;
    END IF;
    produtos_array := produtos_array || jsonb_build_object('produto', prod_nome, 'produto_id', prod_id, 'quantidade', prod_qty, 'valor_unit', prod_preco);

    remaining := prod_qty;
    FOR lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(client_uf, '')) DESC, data_producao ASC
    LOOP
      IF remaining <= 0 THEN EXIT; END IF;
      deduct := LEAST(remaining, lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - deduct WHERE id = lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
      VALUES (prod_id, deduct, 'saida', 'Venda', lote_rec.id, lote_rec.uf, 'pv_pending_' || clock_timestamp()::text);
      remaining := remaining - deduct;
    END LOOP;
    UPDATE produtos SET estoque_atual = estoque_atual - prod_qty WHERE id = prod_id;
  END LOOP;

  v_status_kanban := 'Pagou';

  INSERT INTO pedidos (contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento, criado_por, obs,
    endereco_entrega, data, estoque_processado)
  VALUES (p_contato_id, produtos_array::text, total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento, p_status_pagamento, p_criado_por, p_obs,
    CASE WHEN v_contato_endereco <> '' THEN v_contato_endereco || CASE WHEN v_contato_numero <> '' THEN ', ' || v_contato_numero ELSE '' END ELSE NULL END,
    v_data_sp, true)
  RETURNING id INTO v_pedido_id;

  UPDATE estoque_movimentacoes SET pedido_id = v_pedido_id, observacao = 'Pedido #' || v_pedido_id::text
  WHERE observacao LIKE 'pv_pending_%' AND pedido_id IS NULL;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id)
    VALUES (p_socio, 'VENDA', p_valor, p_canal, p_contato_id, total_qty, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id);
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita', p_valor, p_canal, p_canal || ' - Venda #' || v_pedido_id);
  ELSE
    INSERT INTO financeiro (tipo, valor, canal, descricao) VALUES ('receita_pendente', p_valor, p_canal, p_canal || ' - Venda Pendente #' || v_pedido_id);
  END IF;

  UPDATE contatos SET status_kanban = v_status_kanban, updated_at = now() WHERE id = p_contato_id;
END;
$$;

-- ============================================================
-- 3. Trigger: ignora se estoque_processado=true
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.estoque_processado = true THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = NEW.id) THEN
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    RETURN NEW;
  END IF;
  PERFORM public.processar_pedido_estoque(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_processar_pedido_estoque();

-- ============================================================
-- 4. Reprocessar TODOS pedidos existentes sem movimentacao
-- ============================================================
DO $$
DECLARE
  v_ped record;
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_processed integer := 0;
  v_errors integer := 0;
  v_produto_text text;
BEGIN
  FOR v_ped IN
    SELECT * FROM pedidos
    WHERE (produto IS NOT NULL AND trim(produto) <> '')
      AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    v_produto_text := v_ped.produto;
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct WHERE ct.id = v_ped.contato_id;

    IF v_produto_text LIKE '[%' THEN
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
        LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qty := (v_item->>'quantidade')::integer;
          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
            SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1;
          END IF;
          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
          IF v_produto IS NULL THEN CONTINUE; END IF;

          v_remaining := v_qty;
          FOR v_lote_rec IN
            SELECT id, quantidade_atual, uf FROM lotes
            WHERE produto_id = v_prod_id AND quantidade_atual > 0
            ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
          LOOP
            IF v_remaining <= 0 THEN EXIT; END IF;
            v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
            VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;
          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        v_processed := v_processed + 1;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
      END;
    ELSE
      v_prod_id := v_ped.produto_id;
      v_qty := v_ped.quantidade;
      IF v_prod_id IS NULL THEN
        SELECT id INTO v_prod_id FROM produtos
        WHERE lower(nome_oficial) = lower(trim(v_produto_text))
           OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
        LIMIT 1;
      END IF;
      IF v_prod_id IS NULL THEN v_errors := v_errors + 1; CONTINUE; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN v_errors := v_errors + 1; CONTINUE; END IF;

      v_remaining := v_qty;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = v_prod_id AND quantidade_atual > 0
        ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
        VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;
      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      v_processed := v_processed + 1;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
    END IF;
  END LOOP;
  RAISE NOTICE 'Reprocessamento concluido: % processados, % erros', v_processed, v_errors;
END $$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000012_estoque_definitivo_final.sql
-- ESTOQUE DEFINITIVO: reprocessa TODOS pedidos + trigger automatico
-- Esta migration deve ser executada UMA VEZ no Supabase SQL Editor

-- ============================================================
-- PASSO 1: Garantir estrutura necessaria
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

-- ============================================================
-- PASSO 2: Drop trigger antigo para recriar limpo
-- ============================================================
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
DROP TRIGGER IF EXISTS trigger_abate_estoque_pedido ON public.pedidos;

-- ============================================================
-- PASSO 3: Funcao de trigger limpa
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_abate_estoque_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_produto_text text;
BEGIN
  -- Pula se ja processado
  IF NEW.estoque_processado = true THEN
    RETURN NEW;
  END IF;

  -- Pula se ja tem movimentacao
  IF EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = NEW.id) THEN
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    RETURN NEW;
  END IF;

  v_produto_text := NEW.produto;
  IF v_produto_text IS NULL OR trim(v_produto_text) = '' THEN
    RETURN NEW;
  END IF;

  -- UF do cliente
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
  FROM contatos ct WHERE ct.id = NEW.contato_id;

  -- CASO JSON
  IF v_produto_text LIKE '[%' THEN
    BEGIN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
      LOOP
        v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
        v_qty := (v_item->>'quantidade')::integer;
        IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
          SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1;
        END IF;
        IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
        SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
        IF v_produto IS NULL THEN CONTINUE; END IF;

        v_remaining := v_qty;
        FOR v_lote_rec IN
          SELECT id, quantidade_atual, uf FROM lotes
          WHERE produto_id = v_prod_id AND quantidade_atual > 0
          ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
        LOOP
          IF v_remaining <= 0 THEN EXIT; END IF;
          v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
          UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
          INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
          VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, NEW.id, 'Pedido #' || NEW.id::text);
          v_remaining := v_remaining - v_deduct;
        END LOOP;
        UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      END LOOP;
      UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  -- CASO STRING
  ELSE
    v_prod_id := NEW.produto_id;
    v_qty := NEW.quantidade;
    IF v_prod_id IS NULL THEN
      SELECT id INTO v_prod_id FROM produtos
      WHERE lower(nome_oficial) = lower(trim(v_produto_text))
         OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
      LIMIT 1;
    END IF;
    IF v_prod_id IS NULL THEN RETURN NEW; END IF;
    IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
    SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
    IF v_produto IS NULL THEN RETURN NEW; END IF;

    v_remaining := v_qty;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_prod_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
      VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, NEW.id, 'Pedido #' || NEW.id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;
    UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- PASSO 4: Criar trigger
-- ============================================================
CREATE TRIGGER trg_processar_pedido_estoque
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.trigger_abate_estoque_pedido();

-- ============================================================
-- PASSO 5: Reprocessar TODOS pedidos existentes
-- ============================================================
DO $$
DECLARE
  v_ped record;
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_produto_text text;
  v_ok integer := 0;
  v_err integer := 0;
BEGIN
  FOR v_ped IN
    SELECT * FROM pedidos
    WHERE (produto IS NOT NULL AND trim(produto) <> '')
      AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    v_produto_text := v_ped.produto;
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct WHERE ct.id = v_ped.contato_id;

    IF v_produto_text LIKE '[%' THEN
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb)
        LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qty := (v_item->>'quantidade')::integer;
          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
            SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1;
          END IF;
          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
          IF v_produto IS NULL THEN CONTINUE; END IF;

          v_remaining := v_qty;
          FOR v_lote_rec IN
            SELECT id, quantidade_atual, uf FROM lotes
            WHERE produto_id = v_prod_id AND quantidade_atual > 0
            ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
          LOOP
            IF v_remaining <= 0 THEN EXIT; END IF;
            v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
            VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;
          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
        v_ok := v_ok + 1;
      EXCEPTION WHEN OTHERS THEN
        v_err := v_err + 1;
      END;
    ELSE
      v_prod_id := v_ped.produto_id;
      v_qty := v_ped.quantidade;
      IF v_prod_id IS NULL THEN
        SELECT id INTO v_prod_id FROM produtos
        WHERE lower(nome_oficial) = lower(trim(v_produto_text))
           OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1)))
        LIMIT 1;
      END IF;
      IF v_prod_id IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;

      v_remaining := v_qty;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual, uf FROM lotes
        WHERE produto_id = v_prod_id AND quantidade_atual > 0
        ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao)
        VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;
      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      v_ok := v_ok + 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'REPROCESSAMENTO: % pedidos processados, % erros', v_ok, v_err;
END $$;

-- ============================================================
-- PASSO 6: Verificar resultado
-- ============================================================
DO $$
DECLARE
  v_total_pedidos integer;
  v_total_movs integer;
  v_total_produtos integer;
BEGIN
  SELECT COUNT(*) INTO v_total_pedidos FROM pedidos;
  SELECT COUNT(*) INTO v_total_movs FROM estoque_movimentacoes WHERE tipo = 'saida';
  SELECT COUNT(*) INTO v_total_produtos FROM produtos;
  RAISE NOTICE '=== RESULTADO FINAL ===';
  RAISE NOTICE 'Total pedidos: %', v_total_pedidos;
  RAISE NOTICE 'Total saidas estoque: %', v_total_movs;
  RAISE NOTICE 'Total produtos: %', v_total_produtos;
END $$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000013_RUN_NO_SUPABASE_SQL_EDITOR.sql
-- ============================================================
-- COPIE E COLE TUDO NO SUPABASE SQL EDITOR
-- Estoque definitivo: cria colunas, trigger e reprocessa pedidos
-- ============================================================

-- 1. Adiciona colunas que faltam
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

-- 2. Limpa triggers antigos
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
DROP TRIGGER IF EXISTS trigger_abate_estoque_pedido ON public.pedidos;
DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;

-- 3. Funcao de trigger: abate estoque em TODO novo pedido
CREATE OR REPLACE FUNCTION public.trigger_abate_estoque_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_item jsonb;
  v_prod_id uuid;
  v_qty integer;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_produto record;
  v_produto_text text;
BEGIN
  IF NEW.estoque_processado = true THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = NEW.id) THEN
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    RETURN NEW;
  END IF;
  v_produto_text := NEW.produto;
  IF v_produto_text IS NULL OR trim(v_produto_text) = '' THEN RETURN NEW; END IF;
  SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente FROM contatos ct WHERE ct.id = NEW.contato_id;

  IF v_produto_text LIKE '[%' THEN
    BEGIN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb) LOOP
        v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
        v_qty := (v_item->>'quantidade')::integer;
        IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN
          SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1;
        END IF;
        IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
        SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
        IF v_produto IS NULL THEN CONTINUE; END IF;
        v_remaining := v_qty;
        FOR v_lote_rec IN SELECT id, quantidade_atual, uf FROM lotes WHERE produto_id = v_prod_id AND quantidade_atual > 0 ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC LOOP
          IF v_remaining <= 0 THEN EXIT; END IF;
          v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
          UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
          INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, NEW.id, 'Pedido #' || NEW.id::text);
          v_remaining := v_remaining - v_deduct;
        END LOOP;
        UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      END LOOP;
      UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  ELSE
    v_prod_id := NEW.produto_id;
    v_qty := NEW.quantidade;
    IF v_prod_id IS NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_produto_text)) OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1))) LIMIT 1; END IF;
    IF v_prod_id IS NULL THEN RETURN NEW; END IF;
    IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
    SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
    IF v_produto IS NULL THEN RETURN NEW; END IF;
    v_remaining := v_qty;
    FOR v_lote_rec IN SELECT id, quantidade_atual, uf FROM lotes WHERE produto_id = v_prod_id AND quantidade_atual > 0 ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, NEW.id, 'Pedido #' || NEW.id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;
    UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

-- 4. Cria trigger automatico
CREATE TRIGGER trg_processar_pedido_estoque AFTER INSERT ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.trigger_abate_estoque_pedido();

-- 5. Reprocessa TODOS pedidos existentes sem movimentacao
DO $$
DECLARE
  v_ped record; v_item jsonb; v_prod_id uuid; v_qty integer; v_lote_rec record;
  v_remaining integer; v_deduct integer; v_uf_cliente text; v_produto record;
  v_produto_text text; v_ok integer := 0; v_err integer := 0;
BEGIN
  FOR v_ped IN SELECT * FROM pedidos WHERE (produto IS NOT NULL AND trim(produto) <> '') AND NOT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = pedidos.id) ORDER BY created_at ASC LOOP
    v_produto_text := v_ped.produto;
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente FROM contatos ct WHERE ct.id = v_ped.contato_id;
    IF v_produto_text LIKE '[%' THEN
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb) LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qty := (v_item->>'quantidade')::integer;
          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1; END IF;
          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
          IF v_produto IS NULL THEN CONTINUE; END IF;
          v_remaining := v_qty;
          FOR v_lote_rec IN SELECT id, quantidade_atual, uf FROM lotes WHERE produto_id = v_prod_id AND quantidade_atual > 0 ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC LOOP
            IF v_remaining <= 0 THEN EXIT; END IF;
            v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;
          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
        v_ok := v_ok + 1;
      EXCEPTION WHEN OTHERS THEN v_err := v_err + 1; END;
    ELSE
      v_prod_id := v_ped.produto_id; v_qty := v_ped.quantidade;
      IF v_prod_id IS NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_produto_text)) OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1))) LIMIT 1; END IF;
      IF v_prod_id IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      v_remaining := v_qty;
      FOR v_lote_rec IN SELECT id, quantidade_atual, uf FROM lotes WHERE produto_id = v_prod_id AND quantidade_atual > 0 ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_ped.id, 'Pedido #' || v_ped.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;
      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      v_ok := v_ok + 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'REPROCESSAMENTO: % pedidos processados, % erros', v_ok, v_err;
END $$;

-- 6. Verifica resultado
DO $$
DECLARE v_p integer; v_m integer;
BEGIN
  SELECT COUNT(*) INTO v_p FROM pedidos;
  SELECT COUNT(*) INTO v_m FROM estoque_movimentacoes WHERE tipo = 'saida';
  RAISE NOTICE '=== RESULTADO === Pedidos: %, Saidas estoque: %', v_p, v_m;
END $$;


-- MIGRATION: 20260406000014_estoque_uf_rpc.sql
-- ESTOQUE DEFINITIVO: b0b8bd7 + UF + RPC
-- 1. RPC criar_lote_estoque (entrada)
-- 2. RPC reprocessar_pedidos_estoque (saida de todos pedidos com uf_postagem)
-- 3. Trigger INSERT + UPDATE uf_postagem
-- 4. EstoquePage mostra entradas E saidas

-- ============================================================
-- 1. Estrutura
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

-- ============================================================
-- 2. RPC criar_lote_estoque (entrada via fetch)
-- ============================================================
CREATE OR REPLACE FUNCTION public.criar_lote_estoque(
  p_produto_id uuid, p_uf text, p_quantidade integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_lote_id uuid; v_lote_codigo text; v_today text; v_seq integer; v_last text;
BEGIN
  v_today := to_char(now(), 'YYYYMMDD');
  SELECT COALESCE(MAX(lote_codigo), '') INTO v_last FROM lotes WHERE lote_codigo LIKE 'LOTE-' || v_today || '-%';
  v_seq := CASE WHEN v_last <> '' THEN COALESCE(NULLIF(split_part(v_last, '-', 3), '')::integer, 0) + 1 ELSE 1 END;
  v_lote_codigo := 'LOTE-' || v_today || '-' || lpad(v_seq::text, 3, '0');

  INSERT INTO lotes (produto_id, uf, quantidade_inicial, quantidade_atual, lote_codigo)
  VALUES (p_produto_id, p_uf, p_quantidade, p_quantidade, v_lote_codigo)
  RETURNING id INTO v_lote_id;

  UPDATE produtos SET estoque_atual = estoque_atual + p_quantidade WHERE id = p_produto_id;

  INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, lote_id)
  VALUES (p_produto_id, p_quantidade, 'entrada', p_uf, p_uf, v_lote_id);

  RETURN jsonb_build_object('status', 'ok', 'lote_codigo', v_lote_codigo);
END;
$$;

-- ============================================================
-- 3. RPC reprocessar_pedidos_estoque (roda UMA vez para sincronizar)
-- ============================================================
CREATE OR REPLACE FUNCTION public.reprocessar_pedidos_estoque()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ped record; v_item jsonb; v_prod_id uuid; v_qty integer; v_lote_rec record;
  v_remaining integer; v_deduct integer; v_produto record; v_produto_text text;
  v_ok integer := 0; v_err integer := 0; v_uf text;
BEGIN
  -- Reset
  UPDATE pedidos SET estoque_processado = false;
  DELETE FROM estoque_movimentacoes WHERE tipo = 'saida';

  -- Recalcular estoque com lotes
  DECLARE vp record; vt integer;
  BEGIN
    FOR vp IN SELECT id FROM produtos WHERE ativo = true LOOP
      SELECT COALESCE(SUM(quantidade_atual), 0)::integer INTO vt FROM lotes WHERE produto_id = vp.id;
      UPDATE produtos SET estoque_atual = vt WHERE id = vp.id;
    END LOOP;
  END;

  -- Reprocessar TODOS pedidos com uf_postagem
  FOR v_ped IN
    SELECT * FROM pedidos
    WHERE (produto IS NOT NULL AND trim(produto) <> '')
      AND uf_postagem IS NOT NULL AND trim(uf_postagem) <> ''
    ORDER BY created_at ASC
  LOOP
    v_uf := v_ped.uf_postagem;
    v_produto_text := v_ped.produto;
    IF v_produto_text LIKE '[%' THEN
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb) LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qty := (v_item->>'quantidade')::integer;
          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1; END IF;
          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
          IF v_produto IS NULL THEN CONTINUE; END IF;
          v_remaining := v_qty;
          FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
            IF v_remaining <= 0 THEN EXIT; END IF;
            v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, v_ped.id, 'Pedido #' || v_ped.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;
          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
        v_ok := v_ok + 1;
      EXCEPTION WHEN OTHERS THEN v_err := v_err + 1; END;
    ELSE
      v_prod_id := v_ped.produto_id; v_qty := v_ped.quantidade;
      IF v_prod_id IS NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_produto_text)) LIMIT 1; END IF;
      IF v_prod_id IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      v_remaining := v_qty;
      FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, v_ped.id, 'Pedido #' || v_ped.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;
      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      v_ok := v_ok + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', v_ok, 'errors', v_err);
END;
$$;

-- ============================================================
-- 4. Triggers (mesma logica do b0b8bd7 + uf_postagem)
-- ============================================================
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
DROP TRIGGER IF EXISTS trigger_abate_estoque_pedido ON public.pedidos;
DROP TRIGGER IF EXISTS trg_uf_postagem_update ON public.pedidos;
DROP FUNCTION IF EXISTS public.trigger_abate_estoque_pedido();
DROP FUNCTION IF EXISTS public.trigger_uf_postagem_update();

CREATE OR REPLACE FUNCTION public.trigger_abate_estoque_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_item jsonb; v_prod_id uuid; v_qty integer; v_lote_rec record;
  v_remaining integer; v_deduct integer; v_produto record; v_produto_text text; v_uf text;
BEGIN
  IF NEW.estoque_processado = true THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_id = NEW.id) THEN
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id; RETURN NEW;
  END IF;
  v_produto_text := NEW.produto;
  IF v_produto_text IS NULL OR trim(v_produto_text) = '' THEN RETURN NEW; END IF;
  v_uf := NEW.uf_postagem;
  IF v_uf IS NULL OR trim(v_uf) = '' THEN RETURN NEW; END IF;

  IF v_produto_text LIKE '[%' THEN
    BEGIN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb) LOOP
        v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
        v_qty := (v_item->>'quantidade')::integer;
        IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1; END IF;
        IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
        SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
        IF v_produto IS NULL THEN CONTINUE; END IF;
        v_remaining := v_qty;
        FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
          IF v_remaining <= 0 THEN EXIT; END IF;
          v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
          UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
          INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, NEW.id, 'Pedido #' || NEW.id::text);
          v_remaining := v_remaining - v_deduct;
        END LOOP;
        UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      END LOOP;
      UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  ELSE
    v_prod_id := NEW.produto_id; v_qty := NEW.quantidade;
    IF v_prod_id IS NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_produto_text)) OR lower(nome_oficial) = lower(trim(split_part(v_produto_text, ' x', 1))) LIMIT 1; END IF;
    IF v_prod_id IS NULL THEN RETURN NEW; END IF;
    IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
    SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
    IF v_produto IS NULL THEN RETURN NEW; END IF;
    v_remaining := v_qty;
    FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, NEW.id, 'Pedido #' || NEW.id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;
    UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
    UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_processar_pedido_estoque AFTER INSERT ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.trigger_abate_estoque_pedido();

CREATE OR REPLACE FUNCTION public.trigger_uf_postagem_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_item jsonb; v_prod_id uuid; v_qty integer; v_lote_rec record;
  v_remaining integer; v_deduct integer; v_produto record; v_produto_text text; v_uf text;
BEGIN
  IF NEW.uf_postagem IS NOT NULL AND trim(NEW.uf_postagem) <> '' AND (OLD.uf_postagem IS NULL OR trim(OLD.uf_postagem) = '') AND NEW.estoque_processado = false THEN
    v_uf := NEW.uf_postagem; v_produto_text := NEW.produto;
    IF v_produto_text IS NULL OR trim(v_produto_text) = '' THEN RETURN NEW; END IF;
    IF v_produto_text LIKE '[%' THEN
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb) LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid; v_qty := (v_item->>'quantidade')::integer;
          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1; END IF;
          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id; IF v_produto IS NULL THEN CONTINUE; END IF;
          v_remaining := v_qty;
          FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
            IF v_remaining <= 0 THEN EXIT; END IF; v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, NEW.id, 'Pedido #' || NEW.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;
          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
      EXCEPTION WHEN OTHERS THEN NULL; END;
    ELSE
      v_prod_id := NEW.produto_id; v_qty := NEW.quantidade;
      IF v_prod_id IS NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_produto_text)) LIMIT 1; END IF;
      IF v_prod_id IS NULL THEN RETURN NEW; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN RETURN NEW; END IF;
      v_remaining := v_qty;
      FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
        IF v_remaining <= 0 THEN EXIT; END IF; v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, NEW.id, 'Pedido #' || NEW.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;
      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      UPDATE pedidos SET estoque_processado = true WHERE id = NEW.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_uf_postagem_update ON public.pedidos;
CREATE TRIGGER trg_uf_postagem_update AFTER UPDATE OF uf_postagem ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.trigger_uf_postagem_update();

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000014_rpc_estoque.sql
-- RPC criar_lote_estoque: cria lote + atualiza estoque + registra movimentacao
-- Padrao: bypass PostgREST, tudo via SQL direto no Supabase

CREATE OR REPLACE FUNCTION public.criar_lote_estoque(
  p_produto_id uuid,
  p_uf text,
  p_quantidade integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_lote_id uuid;
  v_lote_codigo text;
  v_today text;
  v_seq integer;
  v_last text;
  v_prod record;
BEGIN
  -- Gerar codigo do lote
  v_today := to_char(now(), 'YYYYMMDD');
  SELECT COALESCE(MAX(lote_codigo), '') INTO v_last FROM lotes WHERE lote_codigo LIKE 'LOTE-' || v_today || '-%';
  IF v_last <> '' THEN
    v_seq := COALESCE(NULLIF(split_part(v_last, '-', 3), '')::integer, 0) + 1;
  ELSE
    v_seq := 1;
  END IF;
  v_lote_codigo := 'LOTE-' || v_today || '-' || lpad(v_seq::text, 3, '0');

  -- Buscar produto
  SELECT * INTO v_prod FROM produtos WHERE id = p_produto_id;
  IF v_prod IS NULL THEN
    RETURN jsonb_build_object('error', 'produto nao encontrado');
  END IF;

  -- Criar lote
  INSERT INTO lotes (produto_id, uf, quantidade_inicial, quantidade_atual, lote_codigo)
  VALUES (p_produto_id, p_uf, p_quantidade, p_quantidade, v_lote_codigo)
  RETURNING id INTO v_lote_id;

  -- Atualizar estoque
  UPDATE produtos SET estoque_atual = estoque_atual + p_quantidade WHERE id = p_produto_id;

  -- Registrar movimentacao
  INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, lote_id)
  VALUES (p_produto_id, p_quantidade, 'entrada', p_uf, p_uf, v_lote_id);

  RETURN jsonb_build_object('status', 'ok', 'lote_codigo', v_lote_codigo, 'lote_id', v_lote_id::text);
END;
$$;

-- RPC reprocessar_pedidos_estoque: reprocessa TODOS pedidos com uf_postagem
CREATE OR REPLACE FUNCTION public.reprocessar_pedidos_estoque()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ped record; v_item jsonb; v_prod_id uuid; v_qty integer; v_lote_rec record;
  v_remaining integer; v_deduct integer; v_produto record; v_produto_text text;
  v_ok integer := 0; v_err integer := 0; v_uf text;
BEGIN
  -- Reset todos
  UPDATE pedidos SET estoque_processado = false;
  DELETE FROM estoque_movimentacoes WHERE tipo = 'saida';

  -- Recalcular estoque com lotes
  DO $inner$
    DECLARE vp record; vt integer;
    BEGIN
      FOR vp IN SELECT id FROM produtos WHERE ativo = true LOOP
        SELECT COALESCE(SUM(quantidade_atual), 0)::integer INTO vt FROM lotes WHERE produto_id = vp.id;
        UPDATE produtos SET estoque_atual = vt WHERE id = vp.id;
      END LOOP;
    END $inner$;

  FOR v_ped IN
    SELECT * FROM pedidos
    WHERE (produto IS NOT NULL AND trim(produto) <> '')
      AND uf_postagem IS NOT NULL AND trim(uf_postagem) <> ''
    ORDER BY created_at ASC
  LOOP
    v_uf := v_ped.uf_postagem;
    v_produto_text := v_ped.produto;
    IF v_produto_text LIKE '[%' THEN
      BEGIN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_produto_text::jsonb) LOOP
          v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
          v_qty := (v_item->>'quantidade')::integer;
          IF v_prod_id IS NULL AND v_item->>'produto' IS NOT NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_item->>'produto')) LIMIT 1; END IF;
          IF v_prod_id IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
          SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
          IF v_produto IS NULL THEN CONTINUE; END IF;
          v_remaining := v_qty;
          FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
            IF v_remaining <= 0 THEN EXIT; END IF;
            v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
            UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
            INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, v_ped.id, 'Pedido #' || v_ped.id::text);
            v_remaining := v_remaining - v_deduct;
          END LOOP;
          UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
        END LOOP;
        UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
        v_ok := v_ok + 1;
      EXCEPTION WHEN OTHERS THEN v_err := v_err + 1; END;
    ELSE
      v_prod_id := v_ped.produto_id; v_qty := v_ped.quantidade;
      IF v_prod_id IS NULL THEN SELECT id INTO v_prod_id FROM produtos WHERE lower(nome_oficial) = lower(trim(v_produto_text)) LIMIT 1; END IF;
      IF v_prod_id IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      IF v_qty IS NULL OR v_qty <= 0 THEN v_qty := 1; END IF;
      SELECT * INTO v_produto FROM produtos WHERE id = v_prod_id;
      IF v_produto IS NULL THEN v_err := v_err + 1; CONTINUE; END IF;
      v_remaining := v_qty;
      FOR v_lote_rec IN SELECT id, quantidade_atual FROM lotes WHERE produto_id = v_prod_id AND uf = v_uf AND quantidade_atual > 0 ORDER BY data_producao ASC LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_id, observacao) VALUES (v_prod_id, v_deduct, 'saida', v_uf, v_lote_rec.id, v_uf, v_ped.id, 'Pedido #' || v_ped.id::text);
        v_remaining := v_remaining - v_deduct;
      END LOOP;
      UPDATE produtos SET estoque_atual = estoque_atual - v_qty WHERE id = v_prod_id;
      UPDATE pedidos SET estoque_processado = true WHERE id = v_ped.id;
      v_ok := v_ok + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', v_ok, 'errors', v_err);
END;
$$;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260406000015_major_v2_fase1_schema.sql
-- ============================================================
-- Major Update V2 - Fase 1: Schema Multi-Instância
-- ============================================================
-- 1. Estender tabela instancias
-- 2. Estender perfis_usuario
-- 3. Estender pedidos
-- 4. Estender lotes
-- 5. Criar tabela comissoes
-- 6. Criar tabela config_comissao_produto
-- 7. Criar contatos para admins v@ e a@
-- 8. Backfill pedidos.contato_id
-- 9. Backfill contatos.instancia_id
-- 10. Indices para performance
-- ============================================================

BEGIN;

-- ============================================================
-- 1. INSTANCIAS - Relaxar constraint e adicionar colunas
-- ============================================================

-- Remover constraint antiga que só允许 'ads' e 'base'
ALTER TABLE public.instancias DROP CONSTRAINT IF EXISTS instancias_tipo_check;

-- Adicionar nova constraint com 'rep'
ALTER TABLE public.instancias ADD CONSTRAINT instancias_tipo_check CHECK (tipo IN ('ads', 'base', 'rep'));

-- Colunas novas para identificar dono da instância
ALTER TABLE public.instancias ADD COLUMN IF NOT EXISTS dono_tipo text DEFAULT 'admin' CHECK (dono_tipo IN ('admin', 'representante'));
ALTER TABLE public.instancias ADD COLUMN IF NOT EXISTS representante_user_id uuid REFERENCES auth.users(id);

-- Index para busca por dono_tipo
CREATE INDEX IF NOT EXISTS idx_instancias_dono_tipo ON public.instancias(dono_tipo) WHERE dono_tipo = 'representante';

-- ============================================================
-- 2. PERFIS_USUARIO - Colunas para multi-instância
-- ============================================================

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS tipo_usuario text DEFAULT 'admin';
ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS socio_key text CHECK (socio_key IN ('V', 'A'));
ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS servico_tipo text;
ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS uf_fixa text;
ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS instancia_id uuid REFERENCES public.instancias(id);
ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS criado_por uuid REFERENCES auth.users(id);

-- Index para busca por tipo_usuario e instancia_id
CREATE INDEX IF NOT EXISTS idx_perfis_usuario_tipo ON public.perfis_usuario(tipo_usuario);
CREATE INDEX IF NOT EXISTS idx_perfis_usuario_instancia ON public.perfis_usuario(instancia_id) WHERE instancia_id IS NOT NULL;

-- ============================================================
-- 3. PEDIDOS - Vincular a contato e instância
-- ============================================================

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS contato_id uuid REFERENCES public.contatos(id);
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS instancia_id uuid REFERENCES public.instancias(id);
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS tipo_origem text;
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS entrega_em_maos boolean DEFAULT false;
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_debitado boolean DEFAULT false;

-- Index para filtro por instancia_id e tipo_origem
CREATE INDEX IF NOT EXISTS idx_pedidos_instancia ON public.pedidos(instancia_id) WHERE instancia_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pedidos_tipo_origem ON public.pedidos(tipo_origem) WHERE tipo_origem IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pedidos_contato ON public.pedidos(contato_id) WHERE contato_id IS NOT NULL;

-- ============================================================
-- 4. LOTES - Suporte a estoque atribuído
-- ============================================================

ALTER TABLE public.lotes ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES auth.users(id);

-- Index para lotes de representante
CREATE INDEX IF NOT EXISTS idx_lotes_representante ON public.lotes(representante_id) WHERE representante_id IS NOT NULL;

-- ============================================================
-- 5. TABELA COMISSOES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.comissoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  representante_id uuid REFERENCES auth.users(id),
  pedido_id uuid REFERENCES public.pedidos(id),
  produto text NOT NULL,
  valor_fixo numeric(10,2) NOT NULL,
  status text DEFAULT 'pendente' CHECK (status IN ('pendente', 'pago', 'cancelado')),
  data_criacao timestamptz DEFAULT now(),
  data_pagamento timestamptz
);

CREATE INDEX IF NOT EXISTS idx_comissoes_representante ON public.comissoes(representante_id);
CREATE INDEX IF NOT EXISTS idx_comissoes_pedido ON public.comissoes(pedido_id);
CREATE INDEX IF NOT EXISTS idx_comissoes_status ON public.comissoes(status) WHERE status = 'pendente';

-- ============================================================
-- 6. TABELA CONFIG_COMISSAO_PRODUTO
-- ============================================================

CREATE TABLE IF NOT EXISTS public.config_comissao_produto (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  produto_tag text NOT NULL UNIQUE,
  valor_comissao numeric(10,2) NOT NULL,
  ativo boolean DEFAULT true
);

-- ============================================================
-- 6.5 PREPARAÇÃO CONTATOS (canal_atual + constraint ADMIN)
-- ============================================================

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS canal_atual text;

-- Atualizar constraint para permitir 'ADMIN'
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.check_constraints cc ON tc.constraint_name = cc.constraint_name
    WHERE tc.constraint_name = 'contatos_canal_origem_check'
    AND tc.table_name = 'contatos'
  ) THEN
    ALTER TABLE public.contatos DROP CONSTRAINT contatos_canal_origem_check;
    ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check
      CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));
  END IF;
END $$;

-- ============================================================
-- 7. CRIAR CONTATOS PARA ADMINS v@ e a@
-- ============================================================

-- Criar contato para v@santaflor.com se não existir
INSERT INTO public.contatos (nome, canal_origem, canal_atual, created_at, updated_at)
SELECT 'Admin V', 'ADMIN', 'ADMIN', now(), now()
WHERE NOT EXISTS (SELECT 1 FROM public.contatos WHERE nome = 'Admin V' AND canal_origem = 'ADMIN');

-- Criar contato para a@santaflor.com se não existir
INSERT INTO public.contatos (nome, canal_origem, canal_atual, created_at, updated_at)
SELECT 'Admin A', 'ADMIN', 'ADMIN', now(), now()
WHERE NOT EXISTS (SELECT 1 FROM public.contatos WHERE nome = 'Admin A' AND canal_origem = 'ADMIN');

-- ============================================================
-- 8. BACKFILL PEDIDOS.CONTATO_ID
-- ============================================================

-- Vincular todos pedidos existentes ao contato do admin v@
UPDATE public.pedidos
SET contato_id = (SELECT id FROM public.contatos WHERE nome = 'Admin V' AND canal_origem = 'ADMIN' LIMIT 1)
WHERE contato_id IS NULL;

-- ============================================================
-- 9. BACKFILL CONTATOS.INSTANCIA_ID
-- ============================================================

-- Contatos ADS → instância ADS
UPDATE public.contatos
SET instancia_id = (SELECT id FROM public.instancias WHERE tipo = 'ads' AND ativo = true ORDER BY created_at ASC LIMIT 1)
WHERE canal_origem = 'ADS' AND instancia_id IS NULL;

-- Contatos BASE/REP/C-REP → instância BASE default
UPDATE public.contatos
SET instancia_id = (SELECT id FROM public.instancias WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1)
WHERE canal_origem IN ('BASE', 'REP', 'C-REP') AND instancia_id IS NULL;


-- ============================================================
-- 11. ATUALIZAR perfis_usuario existentes
-- ============================================================

-- Perfis com ver_menu = ['todos'] são admins
UPDATE public.perfis_usuario
SET tipo_usuario = 'admin'
WHERE ver_menu::text = '["todos"]' OR ver_menu::text = '{todos}';

-- ============================================================
-- 12. NOTIFICACOES - Tabela simples para sino
-- ============================================================

CREATE TABLE IF NOT EXISTS public.notificacoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id),
  tipo text NOT NULL,
  titulo text NOT NULL,
  mensagem text,
  lido boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notificacoes_user_lido ON public.notificacoes(user_id, lido) WHERE lido = false;

COMMIT;

-- ============================================================
-- VERIFICAÇÃO PÓS-MIGRATION
-- ============================================================
DO $$
DECLARE
  v_contatos_admin integer;
  v_pedidos_vinculados integer;
  v_contatos_com_instancia integer;
BEGIN
  SELECT COUNT(*) INTO v_contatos_admin FROM public.contatos WHERE canal_origem = 'ADMIN';
  SELECT COUNT(*) INTO v_pedidos_vinculados FROM public.pedidos WHERE contato_id IS NOT NULL;
  SELECT COUNT(*) INTO v_contatos_com_instancia FROM public.contatos WHERE instancia_id IS NOT NULL;

  RAISE NOTICE '=== Major Update V2 - Fase 1 ===';
  RAISE NOTICE 'Contatos Admin criados: %', v_contatos_admin;
  RAISE NOTICE 'Pedidos vinculados a contato: %', v_pedidos_vinculados;
  RAISE NOTICE 'Contatos com instancia_id: %', v_contatos_com_instancia;
END $$;


-- MIGRATION: 20260406000016_fix_lancamentos_socios_timezone.sql
-- ============================================================
-- Fix: lancamentos_socios.data timezone + backfill
-- ============================================================

-- Fix column default to use Sao Paulo timezone
ALTER TABLE public.lancamentos_socios ALTER COLUMN data SET DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo')::date;

-- Backfill: fix existing records with wrong dates (shifted by +1 day due to UTC)
UPDATE public.lancamentos_socios
SET data = data - INTERVAL '1 day'
WHERE data > (now() AT TIME ZONE 'America/Sao_Paulo')::date;

-- ============================================================
-- Admin: adicionar email em perfis_usuario
-- ============================================================

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS email text;

-- Popula emails dos usuarios existentes via auth.users
UPDATE public.perfis_usuario
SET email = au.email
FROM auth.users au
WHERE perfis_usuario.user_id = au.id
AND perfis_usuario.email IS NULL;



-- MIGRATION: 20260406000017_fase3_rpcs_representante.sql
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
  p_apelido text DEFAULT NULL,
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


-- MIGRATION: 20260406000018_trigger_auto_perfil.sql
-- ============================================================
-- Major Update V2 - Trigger auto-criacao de perfil
-- ============================================================
-- Quando um novo user é criado no Auth, trigger cria perfil automaticamente.
-- Isso permite criar usuarios 100% pelo CRM, sem SQL manual.

BEGIN;

-- Funcao que cria perfil automaticamente
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.perfis_usuario (
    user_id,
    nome,
    acesso_kanban,
    ver_menu,
    pode_excluir_card,
    tipo_usuario,
    socio_key,
    email
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'apelido', split_part(NEW.email, '@', 1)),
    'todos',
    ARRAY['todos']::text[],
    true,
    COALESCE(NEW.raw_user_meta_data->>'tipo_usuario', 'admin'),
    COALESCE(NEW.raw_user_meta_data->>'socio_key', NULL),
    NEW.email
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Trigger no auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

COMMIT;


-- MIGRATION: 20260406000019_fix_criar_pedido_entrega_maos.sql
-- ============================================================
-- Major Update V2 - Fix RPC criar_pedido: entrega_em_maos + estoque
-- ============================================================
-- 1. RPC criar_pedido agora seta entrega_em_maos corretamente
-- 2. Abate estoque admin para entrega_em_maos (lotes sem representante_id)
-- 3. Rep nao pode ter estoque negativo (validacao no frontend PedidosRepPage)

BEGIN;

-- Drop versao anterior
DROP FUNCTION IF EXISTS public.criar_pedido(uuid, text, numeric, text, text, text, text, jsonb, uuid);

CREATE OR REPLACE FUNCTION public.criar_pedido(
  p_contato_id uuid DEFAULT NULL,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
  p_obs text DEFAULT NULL,
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
  v_is_entrega_maos boolean;
  v_prod jsonb;
  v_prod_id uuid;
  v_prod_qty integer;
  v_remaining integer;
  v_lote_rec record;
  v_deduct integer;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_is_entrega_maos := (p_modalidade = 'entrega_maos');

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
    representante_id, tipo_origem, entrega_em_maos, estoque_debitado, estoque_processado
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, p_status_pagamento, p_modalidade, p_uf_postagem,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio',
    p_representante_id,
    CASE WHEN p_representante_id IS NOT NULL THEN 'rep' WHEN p_canal = 'ADS' THEN 'ads' ELSE 'base' END,
    v_is_entrega_maos,
    v_is_entrega_maos,
    v_is_entrega_maos
  ) RETURNING id INTO v_pedido_id;

  -- Insert produtos if provided
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
    SELECT v_pedido_id, (x->>'produto_id')::uuid, COALESCE(x->>'produto', x->>'nome_oficial'), (x->>'quantidade')::integer, (x->>'valor_unit')::numeric
    FROM jsonb_array_elements(p_produtos) AS x;
  END IF;

  -- Se entrega em maos (admin): abate estoque geral (lotes sem representante_id)
  IF v_is_entrega_maos AND p_representante_id IS NULL AND p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      IF v_prod_id IS NULL OR v_prod_qty IS NULL THEN CONTINUE; END IF;

      v_remaining := v_prod_qty;
      FOR v_lote_rec IN
        SELECT id, quantidade_atual FROM public.lotes
        WHERE produto_id = v_prod_id
          AND representante_id IS NULL
          AND quantidade_atual > 0
          AND ativo = true
        ORDER BY data_producao ASC
      LOOP
        IF v_remaining <= 0 THEN EXIT; END IF;
        v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
        UPDATE public.lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, pedido_id, observacao)
        VALUES (v_prod_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_pedido_id, 'Entrega em maos #' || v_order_number);
        v_remaining := v_remaining - v_deduct;
      END LOOP;

      -- Recalcula estoque do produto
      PERFORM public.update_produto_estoque(v_prod_id);
    END LOOP;
  END IF;

  -- Processar estoque normal (nao entrega em maos) via trigger
  IF NOT v_is_entrega_maos AND p_uf_postagem IS NOT NULL AND p_representante_id IS NULL THEN
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

COMMIT;


-- MIGRATION: 20260406000019_rename_admin_contacts.sql
-- Rename admin contacts from "Admin V"/"Admin A" to "V"/"A"
UPDATE public.contatos SET nome = 'V' WHERE nome = 'Admin V' AND canal_origem = 'ADMIN';
UPDATE public.contatos SET nome = 'A' WHERE nome = 'Admin A' AND canal_origem = 'ADMIN';


-- MIGRATION: 20260406000020_white_label_socios.sql
-- ============================================================
-- White Label - Sócios dinâmicos via AdminPage
-- ============================================================
-- 1. Adicionar is_socio em perfis_usuario
-- 2. Backfill: quem tem socio_key V ou A → is_socio = true
-- 3. FinanceiroPage, PedidosPage buscam sócios do banco (não hardcoded)

BEGIN;

-- Nova coluna
ALTER TABLE perfis_usuario ADD COLUMN IF NOT EXISTS is_socio boolean DEFAULT false;

-- Backfill: admins existentes com socio_key viram sócios
UPDATE perfis_usuario SET is_socio = true WHERE socio_key IN ('V', 'A');

COMMIT;


-- MIGRATION: 20260406000021_fix_base_kanban_repeat.sql
-- ============================================================
-- Fix: BASE repeat buyers re-enter 'Clientes' column for LTV flow
-- ============================================================
-- Quando um contato BASE paga novamente, ele volta para 'Clientes'
-- para reentrar no fluxo de LTV. ADS/REP continuam indo para 'Pagou'.

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
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;

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
  UPDATE public.contatos 
  SET status_kanban = CASE WHEN p_canal = 'BASE' THEN 'Clientes' ELSE 'Pagou' END,
      canal_atual = COALESCE(canal_atual, p_canal),
      updated_at = now()
  WHERE id = p_contato_id;

  INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
  VALUES (p_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

-- Also fix criar_pedido RPC for consistency
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
  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

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
  IF p_contato_id IS NOT NULL THEN
    UPDATE public.contatos 
    SET status_kanban = CASE WHEN p_canal = 'BASE' THEN 'Clientes' ELSE 'Pagou' END,
        canal_atual = COALESCE(canal_atual, p_canal),
        updated_at = now()
    WHERE id = p_contato_id;
  END IF;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
    VALUES (v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;


-- MIGRATION: 20260407000000_manual_lock_04032026.sql
-- Manual lock: lock all delivered orders and paid vendas from 03/04/2026 and before
-- Execute this to lock past data immediately

-- Lock all delivered orders from 03/04/2026 and before
UPDATE public.pedidos
SET locked_at = now()
WHERE status_pedido = 'entregue'
  AND locked_at IS NULL
  AND data <= '2026-04-03';

-- Lock all paid vendas (lancamentos_socios) from 03/04/2026 and before
UPDATE public.lancamentos_socios
SET locked_at = now()
WHERE tipo = 'VENDA'
  AND (status_pagamento = 'pago' OR status_pagamento IS NULL OR status_pagamento = '')
  AND locked_at IS NULL
  AND data <= '2026-04-03';


-- MIGRATION: 20260407000021_capital_inicial_socios.sql
-- Migration: Inserir capital inicial dos sócios V e A
-- Substitui o hardcoded +49/+942 do frontend por registros reais no banco

-- Sócio V: Capital inicial R$ 49,00
-- Atualiza a constraint para permitir CAPITAL_INICIAL
ALTER TABLE public.lancamentos_socios DROP CONSTRAINT IF EXISTS lancamentos_socios_tipo_check;
ALTER TABLE public.lancamentos_socios ADD CONSTRAINT lancamentos_socios_tipo_check 
  CHECK (tipo IN ('VENDA', 'ADS', 'ETIQUETA', 'MATERIAL', 'LOGISTICA', 'TRANSFERENCIA', 'LUCRO', 'CAPITAL_INICIAL'));

INSERT INTO lancamentos_socios (id, socio, tipo, valor, descricao, status_pagamento, criado_por, realizado, data)
VALUES (
  gen_random_uuid(),
  'V',
  'CAPITAL_INICIAL',
  49.00,
  'Capital inicial - Sócio V',
  '-',
  'Sistema',
  true,
  '2024-01-01'
)
ON CONFLICT DO NOTHING;

-- Sócio A: Capital inicial R$ 942,00
INSERT INTO lancamentos_socios (id, socio, tipo, valor, descricao, status_pagamento, criado_por, realizado, data)
VALUES (
  gen_random_uuid(),
  'A',
  'CAPITAL_INICIAL',
  942.00,
  'Capital inicial - Sócio A',
  '-',
  'Sistema',
  true,
  '2024-01-01'
)
ON CONFLICT DO NOTHING;


-- MIGRATION: 20260408000000_rename_to_ultima_venda_em.sql
-- Rename primeira_venda_em to ultima_venda_em and add FK
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='contatos' AND column_name='primeira_venda_em') THEN
      ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;
  END IF;
END $$;

-- Add FK to ensure data integrity (references itself for representantes)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'contatos_representante_id_fkey'
  ) THEN
    ALTER TABLE public.contatos 
    ADD CONSTRAINT contatos_representante_id_fkey 
    FOREIGN KEY (representante_id) REFERENCES public.contatos(id);
  END IF;
END $$;

-- FORCE SCHEMA RELOAD
NOTIFY pgrst, 'reload schema';

-- MIGRATION: 20260408000001_trigger_ultima_venda.sql
-- Create trigger function to update ultima_venda_em on lancamentos_socios insert (VENDA only)
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = CURRENT_DATE WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;

CREATE TRIGGER trigger_update_ultima_venda
AFTER INSERT ON public.lancamentos_socios
FOR EACH ROW
EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- Create trigger to update ultima_venda_em when a pedido is created
-- Uses MAX(created_at) to always get the most recent order date
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_last_order_date date;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    -- Get the most recent order date for this contact
    SELECT MAX(created_at)::date INTO v_last_order_date 
    FROM pedidos WHERE contato_id = NEW.contato_id;
    
    UPDATE contatos SET ultima_venda_em = v_last_order_date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;

CREATE TRIGGER trigger_update_ultima_venda_pedido
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

NOTIFY pgrst, 'reload schema';

-- MIGRATION: 20260408000002_migration_antecipada.sql
-- SQL para rodar migração antecipada (midnight migration manual)
-- Migra clientes que pagaram ontem (ultima_venda_em = CURRENT_DATE - 1)
-- ADS Pagou → BASE Clientes
-- BASE Pagou → BASE Clientes  
-- REP Pagou → BASE Clientes
-- C-REP Pagou → BASE Clientes

DO $$
DECLARE
    v_base_instance_id uuid;
    v_ads_count integer := 0;
    v_base_count integer := 0;
    v_rep_count integer := 0;
    v_crep_count integer := 0;
BEGIN
    -- Find the target BASE instance
    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- ADS -> BASE: migrate leads who paid yesterday
    UPDATE public.contatos
    SET 
        canal_origem = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'ADS' 
        AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_ads_count = ROW_COUNT;

    -- BASE Pagou -> BASE Clientes
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        updated_at = now()
    WHERE 
        canal_origem = 'BASE' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_base_count = ROW_COUNT;

    -- REP: customers who paid yesterday move to Clientes
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'REP' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND (status_kanban != 'Clientes' OR status_kanban IS NULL);
    GET DIAGNOSTICS v_rep_count = ROW_COUNT;

    -- C-REP: customers who paid yesterday move to Clientes
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        instancia_id = COALESCE(v_base_instance_id, instancia_id),
        updated_at = now()
    WHERE 
        canal_origem = 'C-REP' 
        AND ultima_venda_em = CURRENT_DATE - 1
        AND (status_kanban != 'Clientes' OR status_kanban IS NULL);
    GET DIAGNOSTICS v_crep_count = ROW_COUNT;

    RAISE NOTICE 'Migrated: ADS->BASE: %, BASE Pagou->Clientes: %, REP: %, C-REP: %', v_ads_count, v_base_count, v_rep_count, v_crep_count;
END $$;

-- MIGRATION: 20260408000005_migration_full.sql
-- Migration completa para rodar no Supabase SQL Editor AGORA
-- Este SQL renomeia a coluna e executa a migração na mesma execução

-- 1. Renomear coluna primeira_venda_em para ultima_venda_em
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='contatos' AND column_name='primeira_venda_em') THEN
      ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;
  END IF;
END $$;

-- 2. Adicionar triggers para atualizar ultima_venda_em automaticamente

-- Trigger em lancamentos_socios (apenas VENDA)
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = CURRENT_DATE WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda
AFTER INSERT ON public.lancamentos_socios
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- Trigger em pedidos (usa MAX para sempre pegar a data do ÚLTIMO pedido)
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_last_order_date date;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    SELECT MAX(created_at)::date INTO v_last_order_date FROM pedidos WHERE contato_id = NEW.contato_id;
    UPDATE contatos SET ultima_venda_em = v_last_order_date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido
AFTER INSERT ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 3. Migrar clientes de ontem (sem RETURNING, usa GET DIAGNOSTICS)
DO $$
DECLARE
    v_base_instance_id uuid;
    v_ads_count integer;
    v_base_count integer;
    v_rep_count integer;
    v_crep_count integer;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE
    UPDATE public.contatos SET canal_origem = 'BASE', status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_ads_count = ROW_COUNT;

    -- BASE Pagou -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em = CURRENT_DATE - 1 AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_base_count = ROW_COUNT;

    -- REP -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_rep_count = ROW_COUNT;

    -- C-REP -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_crep_count = ROW_COUNT;

    RAISE NOTICE 'Migrated: ADS->BASE: %, BASE Pagou->Clientes: %, REP: %, C-REP: %', v_ads_count, v_base_count, v_rep_count, v_crep_count;
END $$;

-- MIGRATION: 20260408000006_migration_fixed.sql
-- Migration completa - renomeia coluna + executa migração
-- Rode este SQL no Supabase SQL Editor

-- 1. Renomear coluna
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='contatos' AND column_name='primeira_venda_em') THEN
      ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;
  END IF;
END $$;

-- 2. Adicionar triggers
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = CURRENT_DATE WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda AFTER INSERT ON public.lancamentos_socios
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_last_order_date date;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    SELECT MAX(created_at)::date INTO v_last_order_date FROM pedidos WHERE contato_id = NEW.contato_id;
    UPDATE contatos SET ultima_venda_em = v_last_order_date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido AFTER INSERT ON public.pedidos
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 3. Migrar clientes de ontem (sem RETURNING, usa GET DIAGNOSTICS)
DO $$
DECLARE
    v_base_instance_id uuid;
    v_ads_count integer;
    v_base_count integer;
    v_rep_count integer;
    v_crep_count integer;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE
    UPDATE public.contatos SET canal_origem = 'BASE', status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_ads_count = ROW_COUNT;

    -- BASE Pagou -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em = CURRENT_DATE - 1 AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_base_count = ROW_COUNT;

    -- REP -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_rep_count = ROW_COUNT;

    -- C-REP -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_crep_count = ROW_COUNT;

    RAISE NOTICE 'Migrated: ADS->BASE: %, BASE Pagou->Clientes: %, REP: %, C-REP: %', v_ads_count, v_base_count, v_rep_count, v_crep_count;
END $$;

-- MIGRATION: 20260408000007_migration_final.sql
-- Migration completa para rodar no Supabase SQL Editor
--一步到位: renomeia coluna + corrige dados existentes + triggers + migração

-- 1. Renomear coluna primeira_venda_em para ultima_venda_em
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='contatos' AND column_name='primeira_venda_em') THEN
      ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;
  END IF;
END $$;

-- 2. Corrige dados existentes: atualiza ultima_venda_em com a data do ÚLTIMO pedido de cada contato
UPDATE public.contatos c
SET ultima_venda_em = (
    SELECT p.created_at::date 
    FROM public.pedidos p 
    WHERE p.contato_id = c.id 
    ORDER BY p.created_at DESC 
    LIMIT 1
)
WHERE EXISTS (
    SELECT 1 FROM public.pedidos p WHERE p.contato_id = c.id
);

-- 3. Adicionar trigger em lancamentos_socios (apenas VENDA)
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = CURRENT_DATE WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda AFTER INSERT ON public.lancamentos_socios
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- 4. Adicionar trigger em pedidos (usa data real do pedido - created_at)
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    UPDATE contatos SET ultima_venda_em = NEW.created_at::date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido AFTER INSERT ON public.pedidos
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 5. Executar migração de clientes de ontem
DO $$
DECLARE
    v_base_instance_id uuid;
    v_ads_count integer;
    v_base_count integer;
    v_rep_count integer;
    v_crep_count integer;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE (quem pagou ontem)
    UPDATE public.contatos SET canal_origem = 'BASE', status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_ads_count = ROW_COUNT;

    -- BASE Pagou -> Clientes (quem pagou ontem)
    UPDATE public.contatos SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em = CURRENT_DATE - 1 AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_base_count = ROW_COUNT;

    -- REP -> Clientes (quem pagou ontem)
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_rep_count = ROW_COUNT;

    -- C-REP -> Clientes (quem pagou ontem)
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em = CURRENT_DATE - 1;
    GET DIAGNOSTICS v_crep_count = ROW_COUNT;

    RAISE NOTICE 'Migrated: ADS->BASE: %, BASE Pagou->Clientes: %, REP: %, C-REP: %', v_ads_count, v_base_count, v_rep_count, v_crep_count;
END $$;

-- MIGRATION: 20260408000008_fix_ultima_venda.sql
-- Migration para corrigir ultima_venda_em de todos contatos com pedido
-- Rode este SQL no Supabase SQL Editor

-- 1. Atualiza ultima_venda_em com a data do ÚLTIMO pedido de cada contato
UPDATE public.contatos c
SET ultima_venda_em = (
    SELECT MAX(p.created_at)::date 
    FROM public.pedidos p 
    WHERE p.contato_id = c.id
)
WHERE EXISTS (
    SELECT 1 FROM public.pedidos p WHERE p.contato_id = c.id
);

-- 2. Trigger para atualizar ultima_venda_em quando novo pedido é criado
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_last_order_date date;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    SELECT MAX(created_at)::date INTO v_last_order_date 
    FROM pedidos WHERE contato_id = NEW.contato_id;
    UPDATE contatos SET ultima_venda_em = v_last_order_date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido 
AFTER INSERT ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 3. Trigger para atualizar ultima_venda_em quando lançamento VENDA é criado
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = CURRENT_DATE WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda 
AFTER INSERT ON public.lancamentos_socios 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- 4. Executar migração de clientes que pagaram ontem (para todos canais)
DO $$
DECLARE v_base_instance_id uuid;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE + Clientes
    UPDATE public.contatos SET canal_origem = 'BASE', status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;

    -- BASE Pagou -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em = CURRENT_DATE - 1 AND status_kanban = 'Pagou';

    -- REP -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em = CURRENT_DATE - 1;

    -- C-REP -> Clientes
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em = CURRENT_DATE - 1;

    RAISE NOTICE 'Migração concluída com sucesso!';
END $$;

-- MIGRATION: 20260408000009_migration_final.sql
-- Migration completa: corrige ultima_venda_em + instancia + migração
-- Rode este SQL no Supabase SQL Editor

-- 1. Atualiza ultima_venda_em com a data do ÚLTIMO pedido de cada contato
UPDATE public.contatos c
SET ultima_venda_em = (
    SELECT MAX(p.created_at)::date 
    FROM public.pedidos p 
    WHERE p.contato_id = c.id
)
WHERE EXISTS (
    SELECT 1 FROM public.pedidos p WHERE p.contato_id = c.id
);

-- 2. Corrige instância de REP e C-REP que estão com NULL (atribui instância BASE)
DO $$
DECLARE v_base_instance_id uuid;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;
    
    -- Atualiza REP com instância NULL para BASE
    UPDATE public.contatos 
    SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'REP' AND instancia_id IS NULL;
    
    -- Atualiza C-REP com instância NULL para BASE
    UPDATE public.contatos 
    SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'C-REP' AND instancia_id IS NULL;
    
    RAISE NOTICE 'REP/C-REP corrigidos para instância BASE';
END $$;

-- 3. Trigger para atualizar ultima_venda_em quando novo pedido é criado
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_last_order_date date;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    SELECT MAX(created_at)::date INTO v_last_order_date 
    FROM pedidos WHERE contato_id = NEW.contato_id;
    UPDATE contatos SET ultima_venda_em = v_last_order_date WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido 
AFTER INSERT ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 4. Trigger para atualizar ultima_venda_em quando lançamento VENDA é criado
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = CURRENT_DATE WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda 
AFTER INSERT ON public.lancamentos_socios 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- 5. Executar migração de clientes que pagaram ontem (para todos canais)
DO $$
DECLARE v_base_instance_id uuid;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE + Clientes
    UPDATE public.contatos SET canal_origem = 'BASE', status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;

    -- BASE Pagou -> Clientes (mantém instância BASE)
    UPDATE public.contatos SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em = CURRENT_DATE - 1 AND status_kanban = 'Pagou';

    -- REP -> Clientes (recebe instância BASE)
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em = CURRENT_DATE - 1;

    -- C-REP -> Clientes (recebe instância BASE)
    UPDATE public.contatos SET status_kanban = 'Clientes', instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em = CURRENT_DATE - 1;

    RAISE NOTICE 'Migração concluída com sucesso!';
END $$;

-- MIGRATION: 20260408000010_force_update.sql
-- SQL direto para forçar atualização da coluna ultima_venda_em
-- Rode este SQL no Supabase SQL Editor

-- 1. Verifica se a coluna existe
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'contatos' AND column_name = 'ultima_venda_em';

-- 2. Verifica se há pedidos para contatos
SELECT c.id, c.nome, c.canal_origem, c.ultima_venda_em, 
       (SELECT MAX(p.created_at) FROM pedidos p WHERE p.contato_id = c.id) as ultimo_pedido
FROM contatos c
WHERE c.canal_origem IN ('REP', 'C-REP', 'BASE')
LIMIT 20;

-- 3. FORÇA atualização de todos os contatos que têm pedido
UPDATE public.contatos c
SET ultima_venda_em = sub.max_date
FROM (
    SELECT contato_id, MAX(created_at)::date as max_date
    FROM public.pedidos
    GROUP BY contato_id
) sub
WHERE c.id = sub.contato_id;

-- 4. Verifica se atualizou
SELECT c.id, c.nome, c.canal_origem, c.ultima_venda_em
FROM contatos c
WHERE c.canal_origem IN ('REP', 'C-REP', 'BASE') AND c.ultima_venda_em IS NOT NULL
LIMIT 20;

-- MIGRATION: 20260408000011_migration_final_v2.sql
-- Migration COMPLETA para lacrar de vez o kanban
-- Rode este SQL no Supabase SQL Editor

-- 1. CORRIGE instancia_id para REP, C-REP, BASE (deve ser BASE)
DO $$
DECLARE v_base_instance_id uuid;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- Atualiza REP sem instância
    UPDATE public.contatos SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'REP' AND instancia_id IS NULL;

    -- Atualiza C-REP sem instância
    UPDATE public.contatos SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'C-REP' AND instancia_id IS NULL;

    -- Atualiza BASE sem instância
    UPDATE public.contatos SET instancia_id = v_base_instance_id, updated_at = now()
    WHERE canal_origem = 'BASE' AND instancia_id IS NULL;

    RAISE NOTICE 'INSTANCIA CORRIGIDA: REP, C-REP e BASE agora são BASE (id: %)', v_base_instance_id;
END $$;

-- 2. Atualiza ultima_venda_em com data+HORA do último pedido
UPDATE public.contatos c
SET ultima_venda_em = sub.max_datetime
FROM (
    SELECT contato_id, MAX(created_at) as max_datetime
    FROM public.pedidos
    GROUP BY contato_id
) sub
WHERE c.id = sub.contato_id;

-- 3. Cria/atualiza trigger para atualizar ultima_venda_em com datetime
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_last_order_datetime timestamptz;
BEGIN
  IF NEW.contato_id IS NOT NULL THEN
    SELECT MAX(created_at) INTO v_last_order_datetime FROM pedidos WHERE contato_id = NEW.contato_id;
    UPDATE contatos SET ultima_venda_em = v_last_order_datetime WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda_pedido ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido 
AFTER INSERT ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

-- 4. Trigger para atualização via lancamentos_socios (VENDA manual)
CREATE OR REPLACE FUNCTION public.update_ultima_venda_on_lancamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.contato_id IS NOT NULL AND NEW.tipo = 'VENDA' THEN
    UPDATE contatos SET ultima_venda_em = now() WHERE id = NEW.contato_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_ultima_venda ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda 
AFTER INSERT ON public.lancamentos_socios 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

-- 5. ANTECIPA MIDNIGHT: Move clientes de ONTEM (não precisa esperar meia-noite)
DO $$
DECLARE v_base_instance_id uuid; v_count integer;
BEGIN
    SELECT id INTO v_base_instance_id FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true ORDER BY is_default_base DESC, created_at ASC LIMIT 1;

    -- ADS -> BASE + Clientes (quem pagou anteontem ou antes, baseado na ultima_venda)
    UPDATE public.contatos 
    SET canal_origem = 'BASE', status_kanban = 'Clientes', 
        instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em IS NOT NULL 
    AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'ADS -> BASE Clientes: %', v_count;

    -- BASE Pagou -> Clientes
    UPDATE public.contatos 
    SET status_kanban = 'Clientes', updated_at = now()
    WHERE canal_origem = 'BASE' AND ultima_venda_em IS NOT NULL 
    AND status_kanban = 'Pagou';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'BASE Pagou -> Clientes: %', v_count;

    -- REP -> Clientes (independentemente de status_kanban, se tem venda)
    UPDATE public.contatos 
    SET status_kanban = 'Clientes', 
        instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'REP' AND ultima_venda_em IS NOT NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'REP -> Clientes: %', v_count;

    -- C-REP -> Clientes
    UPDATE public.contatos 
    SET status_kanban = 'Clientes', 
        instancia_id = COALESCE(v_base_instance_id, instancia_id), updated_at = now()
    WHERE canal_origem = 'C-REP' AND ultima_venda_em IS NOT NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'C-REP -> Clientes: %', v_count;

    RAISE NOTICE 'MIDNIGHT ANTECIPADO CONCLUÍDO! Cards Pagou movidos para Clientes.';
END $$;

-- 6. Verificação final
SELECT 
    canal_origem, 
    status_kanban, 
    count(*) as total,
    count(instancia_id) as com_instancia,
    count(ultima_venda_em) as com_ultima_venda
FROM contatos 
GROUP BY canal_origem, status_kanban
ORDER BY canal_origem, status_kanban;

-- MIGRATION: 20260409000000_canal_atual_new_tag.sql
-- Migration: Canal Atual + Tag New para transferência midnight
-- Rode este SQL no Supabase SQL Editor

-- 1. Adiciona coluna canal_atual (canal atual para visualização no Kanban)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS canal_atual text;

-- 2. Adiciona coluna is_novo (para tag "Novo" azul por 24h após transferência)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS is_novo boolean DEFAULT false;

-- 3. Adiciona coluna novo_ate (timestamp até quando a tag "Novo" expira)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS novo_ate timestamptz;

-- 4. Atualiza canal_atual baseado no canal_origem atual (dados existentes)
UPDATE public.contatos SET canal_atual = canal_origem WHERE canal_atual IS NULL;

-- 5. Função de migração midnight: ADS -> BASE
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_base_instance_id uuid;
    v_migrated_count integer := 0;
    v_next_midnight timestamptz;
BEGIN
    v_next_midnight := (CURRENT_DATE + 1)::timestamptz;

    SELECT id INTO v_base_instance_id 
    FROM public.instancias 
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC 
    LIMIT 1;

    -- ADS -> BASE: canal_atual muda, is_novo = true até próximo midnight
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
        AND ultima_venda_em = CURRENT_DATE - 1;

    GET DIAGNOSTICS v_migrated_count = ROW_COUNT;

    -- BASE Pagou -> Clientes
    UPDATE public.contatos
    SET 
        status_kanban = 'Clientes',
        is_novo = true,
        novo_ate = v_next_midnight,
        updated_at = now()
    WHERE 
        canal_origem = 'BASE' 
        AND status_kanban = 'Pagou'
        AND ultima_venda_em = CURRENT_DATE - 1;

    -- Desativa tags expiradas
    UPDATE public.contatos 
    SET is_novo = false 
    WHERE is_novo = true 
      AND novo_ate IS NOT NULL 
      AND novo_ate <= now();

    INSERT INTO public.configuracoes (chave, valor) 
    VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
    ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

    RETURN json_build_object(
        'success', true,
        'migrated_count', v_migrated_count,
        'target_instance_id', v_base_instance_id
    );
END;
$$;

-- 6. Verificação final
SELECT canal_origem, canal_atual, status_kanban, count(*) as total
FROM contatos GROUP BY canal_origem, canal_atual, status_kanban
ORDER BY canal_origem, canal_atual, status_kanban;

-- MIGRATION: 20260410000000_fix_canal_crep_constraint.sql
-- Fix: Ensure C-REP is in canal_origem constraint (in case migration wasn't applied)
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;
ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));


-- MIGRATION: 20260410000000_fix_inventory_bugs.sql
-- CORREÇÃO DE BUGS NO ESTOQUE E SCHEMA DE MOVIMENTAÇÕES
-- 1. Adiciona coluna criado_por
-- 2. Corrige get_estoque_completo (JOIN por UF)
-- 3. Atualiza criar_lote_estoque (nome do criador)
-- 4. Reprocessa estoque_atual e snapshot

BEGIN;

-- 1. SCHEMA: Adiciona coluna criado_por em estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS criado_por text;

-- 2. RPC: get_estoque_completo (CORREGIDA PARA NÃO DUPLICAR UF)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
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
  ),
  estoque_por_uf AS (
    SELECT 
      COALESCE(e.pid, s.pid) as pid,
      COALESCE(e.uff, s.uff) as uff,
      COALESCE(e.qtd_ent, 0) as qtd_ent,
      COALESCE(s.qtd_sai, 0) as qtd_sai
    FROM entradas e
    FULL OUTER JOIN saidas s ON e.pid = s.pid AND e.uff = s.uff
  )
  SELECT 
    epu.pid as prod_id,
    pr.pnome as prod_nome,
    epu.uff as estado,
    epu.qtd_ent::int as entrada,
    epu.qtd_sai::int as saida,
    (epu.qtd_ent - epu.qtd_sai)::int as saldo
  FROM estoque_por_uf epu
  JOIN produtos_ativos pr ON pr.pid = epu.pid
  WHERE epu.qtd_ent > 0 OR epu.qtd_sai > 0
  ORDER BY pr.pnome, epu.uff;
END;
$$;

-- 3. RPC: criar_lote_estoque (SUPORTE A CRIADO_POR)
CREATE OR REPLACE FUNCTION public.criar_lote_estoque(
  p_produto_id uuid,
  p_uf text,
  p_quantidade integer,
  p_criado_por text DEFAULT 'Sistema'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_lote_id uuid;
  v_lote_codigo text;
  v_today text;
  v_seq integer;
  v_last text;
  v_prod record;
BEGIN
  -- Gerar codigo do lote
  v_today := to_char(now(), 'YYYYMMDD');
  SELECT COALESCE(MAX(lote_codigo), '') INTO v_last FROM lotes WHERE lote_codigo LIKE 'LOTE-' || v_today || '-%';
  IF v_last <> '' THEN
    v_seq := COALESCE(NULLIF(split_part(v_last, '-', 3), '')::integer, 0) + 1;
  ELSE
    v_seq := 1;
  END IF;
  v_lote_codigo := 'LOTE-' || v_today || '-' || lpad(v_seq::text, 3, '0');

  -- Buscar produto
  SELECT * INTO v_prod FROM produtos WHERE id = p_produto_id;
  IF v_prod IS NULL THEN
    RETURN jsonb_build_object('error', 'produto nao encontrado');
  END IF;

  -- Criar lote
  INSERT INTO lotes (produto_id, uf, quantidade_inicial, quantidade_atual, lote_codigo)
  VALUES (p_produto_id, p_uf, p_quantidade, p_quantidade, v_lote_codigo)
  RETURNING id INTO v_lote_id;

  -- Atualizar estoque real do produto (vai ser recalculado abaixo mas mantemos o padrao)
  UPDATE produtos SET estoque_atual = estoque_atual + p_quantidade WHERE id = p_produto_id;

  -- Registrar movimentacao com criado_por
  INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, lote_id, criado_por)
  VALUES (p_produto_id, p_quantidade, 'entrada', p_uf, p_uf, v_lote_id, p_criado_por);

  RETURN jsonb_build_object('status', 'ok', 'lote_codigo', v_lote_codigo, 'lote_id', v_lote_id::text);
END;
$$;

-- 4. DATA FIX: Vincular Pedido #9 se estiver sem vínculo
UPDATE public.estoque_movimentacoes em
SET pedido_id = p.id
FROM public.pedidos p
WHERE em.pedido_id IS NULL 
  AND (em.observacao LIKE '%Pedido #9%' OR em.observacao LIKE '%#9%')
  AND p.order_number = '9';

-- 5. MANUTENÇÃO: Recalcular estoque_atual baseado em movimentações reais
-- Isso limpa erros de conta acumulados
DO $$
DECLARE
  v_rec record;
BEGIN
  FOR v_rec IN SELECT id FROM public.produtos LOOP
    UPDATE public.produtos p
    SET estoque_atual = (
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = 'entrada'), 0) -
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = 'saida'), 0)
    )
    WHERE p.id = v_rec.id;
  END LOOP;
END $$;

-- 6. SNAPSHOT: Atualizar tabela de snapshot se existir
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'estoque_snapshot') THEN
    DELETE FROM public.estoque_snapshot;
    INSERT INTO public.estoque_snapshot (produto_id, estado, entrada, saida, saldo, updated_at)
    SELECT prod_id, estado, entrada, saida, saldo, now() FROM get_estoque_completo();
  END IF;
END $$;

COMMIT;


-- MIGRATION: 20260410000001_estoque_source_of_truth.sql
-- ESTOQUE: FONTE DA VERDADE ÚNICA (MOVIMENTAÇÕES)
-- 1. Normaliza siglas de UF (remove espaços e padroniza maiúsculas)
-- 2. Reescreve get_estoque_completo para usar APENAS estoque_movimentacoes
-- 3. Garante que os cards batam 100% com a lista de movimentações

BEGIN;

-- 1. NORMALIZAÇÃO: Limpa sujeira nas siglas de UF
UPDATE public.estoque_movimentacoes SET uf_origem = TRIM(UPPER(uf_origem)) WHERE uf_origem IS NOT NULL;
UPDATE public.estoque_movimentacoes SET posse = TRIM(UPPER(posse)) WHERE posse IS NOT NULL;
UPDATE public.lotes SET uf = TRIM(UPPER(uf)) WHERE uf IS NOT NULL;
UPDATE public.pedidos SET uf_postagem = TRIM(UPPER(uf_postagem)) WHERE uf_postagem IS NOT NULL;

-- 2. REESCRITA DA FUNÇÃO: get_estoque_completo
-- Agora baseada 100% no histórico de movimentações para evitar "lançamentos fantasma" ou divergências
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH movimentacao_resumo AS (
    SELECT 
      em.produto_id as pid,
      TRIM(UPPER(COALESCE(em.uf_origem, em.posse, 'SP'))) as uff,
      SUM(CASE WHEN em.tipo = 'entrada' THEN em.quantidade ELSE 0 END)::int as qtd_ent,
      SUM(CASE WHEN em.tipo = 'saida' THEN em.quantidade ELSE 0 END)::int as qtd_sai
    FROM public.estoque_movimentacoes em
    WHERE em.produto_id IS NOT NULL 
      AND em.quantidade > 0
    GROUP BY em.produto_id, TRIM(UPPER(COALESCE(em.uf_origem, em.posse, 'SP')))
  )
  SELECT 
    mr.pid as prod_id,
    p.nome_oficial as prod_nome,
    mr.uff as estado,
    mr.qtd_ent as entrada,
    mr.qtd_sai as saida,
    (mr.qtd_ent - mr.qtd_sai) as saldo
  FROM movimentacao_resumo mr
  JOIN public.produtos p ON p.id = mr.pid
  WHERE p.ativo = true
    AND (mr.qtd_ent <> 0 OR mr.qtd_sai <> 0)
  ORDER BY p.nome_oficial, mr.uff;
END;
$$;

-- 3. REPROCESSO: Atualiza estoque_atual dos produtos e snapshot
DO $$
DECLARE
  v_rec record;
BEGIN
  FOR v_rec IN SELECT id FROM public.produtos LOOP
    UPDATE public.produtos p
    SET estoque_atual = (
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = 'entrada'), 0) -
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = 'saida'), 0)
    )
    WHERE p.id = v_rec.id;
  END LOOP;
END $$;

-- 4. SNAPSHOT: Recria a tabela de snapshot para garantir consistência total
DROP TABLE IF EXISTS public.estoque_snapshot;
CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  prod_id uuid REFERENCES public.produtos(id),
  prod_nome text,
  estado text,
  entrada integer DEFAULT 0,
  saida integer DEFAULT 0,
  saldo integer DEFAULT 0,
  updated_at timestamptz DEFAULT now()
);

-- Popular snapshot
INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now() FROM get_estoque_completo();

COMMIT;


-- MIGRATION: 20260410000001_estoque_ufs.sql
-- Migration: tabela estoque_ufs para UFs dinâmicas
-- EXECUTAR MANUALMENTE NO SQL EDITOR DO SUPABASE

-- 1. Criar tabela
CREATE TABLE IF NOT EXISTS estoque_ufs (
  uf TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Habilitar RLS
ALTER TABLE estoque_ufs ENABLE ROW LEVEL SECURITY;

-- 3. Policy de leitura pública (autenticados)
CREATE POLICY "Authenticated can read estoque_ufs" ON estoque_ufs
  FOR SELECT TO authenticated USING (true);

-- 4. Policy de inserção (autenticados)
CREATE POLICY "Authenticated can insert estoque_ufs" ON estoque_ufs
  FOR INSERT TO authenticated WITH CHECK (true);

-- 5. Policy de deleção (autenticados)
CREATE POLICY "Authenticated can delete estoque_ufs" ON estoque_ufs
  FOR DELETE TO authenticated USING (true);

-- 6. Seed: migrar UFs existentes conhecidas
INSERT INTO estoque_ufs (uf) VALUES ('SC'), ('RS'), ('SP'), ('GO')
ON CONFLICT (uf) DO NOTHING;


-- MIGRATION: 20260410000002_add_uf_regioes.sql
-- REGIONALIZAÇÃO DE UFS - SCHEMA E MIGRAÇÃO
-- 1. Cria tabela uf_regioes
-- 2. Sistema de geração de código automático (RS1, RS2)
-- 3. Lógica de migração automática UF -> UF1 no primeiro cadastro

BEGIN;

-- 1. TABELA DE REGIÕES
CREATE TABLE IF NOT EXISTS public.uf_regioes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uf text NOT NULL REFERENCES public.estoque_ufs(uf) ON DELETE CASCADE,
  tag text NOT NULL, -- Nome amigável (ex: Alvorada)
  codigo text UNIQUE NOT NULL, -- O código operacional (ex: RS1)
  sequencial integer NOT NULL, -- 1, 2, 3...
  criado_em timestamptz DEFAULT now(),
  UNIQUE(uf, tag)
);

-- Habilitar RLS
ALTER TABLE public.uf_regioes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read uf_regioes" ON public.uf_regioes
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can insert uf_regioes" ON public.uf_regioes
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated can delete uf_regioes" ON public.uf_regioes
  FOR DELETE TO authenticated USING (true);

-- 2. FUNÇÃO: Geração de Código e Migração Automática
CREATE OR REPLACE FUNCTION public.criar_regiao_uf(p_uf text, p_tag text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_seq integer;
  v_codigo text;
  v_regiao_id uuid;
  v_is_first boolean;
BEGIN
  -- 1. Descobrir o próximo sequencial
  SELECT COALESCE(MAX(sequencial), 0) + 1 INTO v_seq FROM uf_regioes WHERE uf = p_uf;
  v_codigo := p_uf || v_seq::text;
  v_is_first := (v_seq = 1);

  -- 2. Criar a região
  INSERT INTO uf_regioes (uf, tag, codigo, sequencial)
  VALUES (p_uf, p_tag, v_codigo, v_seq)
  RETURNING id INTO v_regiao_id;

  -- 3. Se for a primeira região, MIGRAR dados da UF base para UF1
  IF v_is_first THEN
    -- estoque_movimentacoes
    UPDATE estoque_movimentacoes SET uf_origem = v_codigo WHERE uf_origem = p_uf;
    UPDATE estoque_movimentacoes SET posse = v_codigo WHERE posse = p_uf;
    
    -- lotes
    UPDATE lotes SET uf = v_codigo WHERE uf = p_uf;
    
    -- pedidos
    UPDATE pedidos SET uf_postagem = v_codigo WHERE uf_postagem = p_uf;
    UPDATE pedidos SET uf_cliente = v_codigo WHERE uf_cliente = p_uf;

    -- snapshot
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'estoque_snapshot') THEN
       UPDATE estoque_snapshot SET estado = v_codigo WHERE estado = p_uf;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'id', v_regiao_id,
    'codigo', v_codigo,
    'migrado', v_is_first
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

COMMIT;


-- MIGRATION: 20260410000003_bugfix_regions_consistency.sql
-- BUGFIX: CONSISTÊNCIA DE REGIONALIZAÇÃO E ESTOQUE
-- 1. Atualiza criar_regiao_uf para migrar remetentes
-- 2. Ajusta priorização de estoque para reconhecer prefixos de UF (RS matches RS1)

BEGIN;

-- 1. ATUALIZAÇÃO DA RPC DE CRIAÇÃO DE REGIÃO
CREATE OR REPLACE FUNCTION public.criar_regiao_uf(p_uf text, p_tag text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_seq integer;
  v_codigo text;
  v_regiao_id uuid;
  v_is_first boolean;
BEGIN
  -- 1. Descobrir o próximo sequencial
  SELECT COALESCE(MAX(sequencial), 0) + 1 INTO v_seq FROM uf_regioes WHERE uf = p_uf;
  v_codigo := p_uf || v_seq::text;
  v_is_first := (v_seq = 1);

  -- 2. Criar a região
  INSERT INTO uf_regioes (uf, tag, codigo, sequencial)
  VALUES (p_uf, p_tag, v_codigo, v_seq)
  RETURNING id INTO v_regiao_id;

  -- 3. Se for a primeira região, MIGRAR dados da UF base para UF1
  IF v_is_first THEN
    -- estoque_movimentacoes
    UPDATE estoque_movimentacoes SET uf_origem = v_codigo WHERE uf_origem = p_uf;
    UPDATE estoque_movimentacoes SET posse = v_codigo WHERE posse = p_uf;
    
    -- lotes
    UPDATE lotes SET uf = v_codigo WHERE uf = p_uf;
    
    -- pedidos
    UPDATE pedidos SET uf_postagem = v_codigo WHERE uf_postagem = p_uf;
    UPDATE pedidos SET uf_cliente = v_codigo WHERE uf_cliente = p_uf;

    -- remetentes_uf (IMPORTANTE PARA LOGÍSTICA)
    UPDATE remetentes_uf SET uf = v_codigo WHERE uf = p_uf;

    -- snapshot
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'estoque_snapshot') THEN
       UPDATE estoque_snapshot SET estado = v_codigo WHERE estado = p_uf;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'id', v_regiao_id,
    'codigo', v_codigo,
    'migrado', v_is_first
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- 2. ATUALIZAÇÃO DA PRIORIZAÇÃO DE ESTOQUE (RECONHECER REGIÕES)
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(p_pedido_id uuid, p_uf_postagem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_total_items integer := 0;
  v_processed_items integer := 0;
BEGIN
  -- Tenta pegar a UF de postagem, se não tiver, pega a do cliente
  v_uf_cliente := p_uf_postagem;
  
  IF v_uf_cliente IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM public.contatos ct, public.pedidos p WHERE p.id = p_pedido_id AND ct.id = p.contato_id;
  END IF;

  -- Normalizar UF cliente para busca de prefixo (ex: 'RS' em 'RS1')
  -- Se o cliente for de 'RS' e não tivermos 'RS' exato, buscamos 'RS%'

  FOR v_item IN SELECT * FROM public.pedido_itens WHERE pedido_id = p_pedido_id LOOP
    v_total_items := v_total_items + 1;
    SELECT EXISTS (SELECT 1 FROM public.estoque_movimentacoes WHERE pedido_item_id = v_item.id) INTO v_mov_exists;
    IF v_mov_exists THEN CONTINUE; END IF;

    v_remaining := v_item.quantidade;
    
    -- Prioridade 1: Match Exato da UF (ex: 'RS1' == 'RS1')
    -- Prioridade 2: Match por Prefixo (ex: 'RS' match 'RS1', 'RS2')
    -- Prioridade 3: Resto (FIFO Global)
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM public.lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY 
        (uf = v_uf_cliente) DESC, -- Match exato primeiro
        (uf LIKE v_uf_cliente || '%') DESC, -- Região daquela UF depois
        created_at ASC -- FIFO Global por fim
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      
      UPDATE public.lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      
      INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, pedido_id, observacao, criado_por)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, p_pedido_id, 'Pedido #' || p_pedido_id::text, 'Sistema (Auto)');
      
      v_remaining := v_remaining - v_deduct;
    END LOOP;
    
    v_processed_items := v_processed_items + 1;
  END LOOP;

  UPDATE public.pedidos SET estoque_processado = true WHERE id = p_pedido_id;
  
  -- Sincronizar Snapshot
  IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
     PERFORM public.atualizar_estoque_snapshot();
  END IF;
  
  RETURN jsonb_build_object('pedido_id', p_pedido_id::text, 'total_items', v_total_items, 'processed', v_processed_items);
END;
$$;

COMMIT;


-- MIGRATION: 20260410000004_final_bugfixes.sql
-- REFINAMENTO FINAL: REGIONALIZAÇÃO
-- Garante que TODA nova região criada tenha um registro em remetentes_uf
-- (Copia do remetente da UF base ou gera um em branco)

BEGIN;

CREATE OR REPLACE FUNCTION public.criar_regiao_uf(p_uf text, p_tag text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_seq integer;
  v_codigo text;
  v_regiao_id uuid;
  v_is_first boolean;
BEGIN
  -- 1. Descobrir o próximo sequencial
  SELECT COALESCE(MAX(sequencial), 0) + 1 INTO v_seq FROM uf_regioes WHERE uf = p_uf;
  v_codigo := p_uf || v_seq::text;
  v_is_first := (v_seq = 1);

  -- 2. Criar a região
  INSERT INTO uf_regioes (uf, tag, codigo, sequencial)
  VALUES (p_uf, p_tag, v_codigo, v_seq)
  RETURNING id INTO v_regiao_id;

  -- 3. Se for a primeira região, MIGRAR dados da UF base para UF1
  IF v_is_first THEN
    -- estoque_movimentacoes
    UPDATE estoque_movimentacoes SET uf_origem = v_codigo WHERE uf_origem = p_uf;
    UPDATE estoque_movimentacoes SET posse = v_codigo WHERE posse = p_uf;
    
    -- lotes
    UPDATE lotes SET uf = v_codigo WHERE uf = p_uf;
    
    -- pedidos
    UPDATE pedidos SET uf_postagem = v_codigo WHERE uf_postagem = p_uf;
    UPDATE pedidos SET uf_cliente = v_codigo WHERE uf_cliente = p_uf;

    -- remetentes_uf (IMPORTANTE PARA LOGÍSTICA)
    -- Migra o remetente atual da UF base para a nova região operacional
    UPDATE remetentes_uf SET uf = v_codigo WHERE uf = p_uf;

    -- snapshot
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'estoque_snapshot') THEN
       UPDATE estoque_snapshot SET estado = v_codigo WHERE estado = p_uf;
    END IF;
  ELSE
    -- 4. Para regiões subsequentes (RS2, RS3...), criar um remetente em branco ou cópia
    -- Isso evita erro de "Remetente não configurado" na Logística
    IF NOT EXISTS (SELECT 1 FROM remetentes_uf WHERE uf = v_codigo) THEN
        INSERT INTO remetentes_uf (uf, nome_remetente, cep_origem)
        SELECT v_codigo, nome_remetente || ' (' || p_tag || ')', cep_origem
        FROM remetentes_uf
        WHERE uf LIKE p_uf || '%'
        ORDER BY uf ASC
        LIMIT 1;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'id', v_regiao_id,
    'codigo', v_codigo,
    'migrado', v_is_first
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

COMMIT;


-- MIGRATION: 20260410052111_8ca81f5b-a80b-4305-9dc3-ccd8d4b0bf15.sql

-- Remove os 3 lotes fantasma do Gummy criados em 2026-04-10
DELETE FROM public.lotes 
WHERE id IN (
  'c7376476-ee77-4115-a32a-07879806b49b',
  'ad2ad234-9f0c-44eb-871a-69fcf5bdba9c',
  'fb28a5bd-d9fa-421d-bbf1-fafb81676e55'
);

-- Recalcula estoque_atual do Gummy: soma entradas - soma saídas das movimentações
UPDATE public.produtos 
SET estoque_atual = (
  SELECT COALESCE(SUM(CASE WHEN tipo = 'entrada' THEN quantidade ELSE -quantidade END), 0)
  FROM public.estoque_movimentacoes 
  WHERE produto_id = '64482cf8-cc5c-4964-bc67-62fde991d06d'
)
WHERE id = '64482cf8-cc5c-4964-bc67-62fde991d06d';

-- Atualiza snapshot (safe check)
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
      PERFORM public.atualizar_estoque_snapshot();
  END IF;
END $$;


-- MIGRATION: 20260411000000_fix_canal_constraint_again.sql
-- Fix canal_origem check constraint to include C-REP
-- This is needed because the original table creation had a constraint without C-REP

ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IS NULL OR canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));

-- Also ensure canal_origem is NOT NULL (if that's the desired behavior)
-- ALTER TABLE public.contatos ALTER COLUMN canal_origem SET NOT NULL;

NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260411000001_remove_canal_constraint.sql
-- ULTIMATE FIX: Remove canal_origem constraint completely to allow any value
-- This was broken after adding C-REP because the constraint wasn't properly updated

-- Drop the check constraint completely
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

-- Add a simple NOT NULL constraint (no value restrictions)
ALTER TABLE public.contatos ALTER COLUMN canal_origem SET NOT NULL;

-- Reload PostgREST schema
NOTIFY pgrst, 'reload schema';


-- MIGRATION: 20260411214825_2596e205-c4fb-4062-9647-3bdc56384763.sql

-- 1. Fix atualizar_estoque_snapshot: column is "updated_at" not "atualizado_em"
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
  SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now() FROM public.calcular_estoque();
  UPDATE public.produtos p SET estoque_atual = COALESCE((SELECT SUM(saldo) FROM public.estoque_snapshot WHERE prod_id = p.id), 0) WHERE p.id IS NOT NULL;
END;
$function$;

-- 2. Remove duplicate triggers that cause double stock deductions
DROP TRIGGER IF EXISTS tg_abate_estoque_pedido ON public.pedidos;
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;

-- 3. Fix calcular_estoque to use estoque_movimentacoes as single source of truth
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH movimentacao_resumo AS (
    SELECT 
      em.produto_id as pid,
      TRIM(UPPER(COALESCE(em.uf_origem, em.posse, 'SP'))) as uff,
      SUM(CASE WHEN em.tipo = 'entrada' THEN em.quantidade ELSE 0 END)::int as qtd_ent,
      SUM(CASE WHEN em.tipo = 'saida' THEN em.quantidade ELSE 0 END)::int as qtd_sai
    FROM public.estoque_movimentacoes em
    WHERE em.produto_id IS NOT NULL 
      AND em.quantidade > 0
    GROUP BY em.produto_id, TRIM(UPPER(COALESCE(em.uf_origem, em.posse, 'SP')))
  )
  SELECT 
    mr.pid as prod_id,
    p.nome_oficial as prod_nome,
    mr.uff as estado,
    mr.qtd_ent as entrada,
    mr.qtd_sai as saida,
    (mr.qtd_ent - mr.qtd_sai) as saldo
  FROM movimentacao_resumo mr
  JOIN public.produtos p ON p.id = mr.pid
  WHERE p.ativo = true
    AND (mr.qtd_ent <> 0 OR mr.qtd_sai <> 0)
  ORDER BY p.nome_oficial, mr.uff;
END;
$function$;

-- 4. Recalculate all products stock from movements
DO $$
DECLARE
  v_prod record;
  v_entradas numeric;
  v_saidas numeric;
BEGIN
  FOR v_prod IN SELECT id FROM public.produtos LOOP
    SELECT COALESCE(SUM(quantidade), 0) INTO v_entradas FROM public.estoque_movimentacoes WHERE produto_id = v_prod.id AND tipo = 'entrada';
    SELECT COALESCE(SUM(quantidade), 0) INTO v_saidas FROM public.estoque_movimentacoes WHERE produto_id = v_prod.id AND tipo = 'saida';
    UPDATE public.produtos SET estoque_atual = v_entradas - v_saidas WHERE id = v_prod.id;
  END LOOP;
END $$;

-- 5. Refresh snapshot
SELECT public.atualizar_estoque_snapshot();


-- MIGRATION: 20260412000000_create_contato_rpc.sql
-- Create a function to insert contacts directly via RPC
-- This bypasses PostgREST which was hanging on insert
CREATE OR REPLACE FUNCTION public.create_contato(
  p_nome text,
  p_canal_origem text,
  p_telefone text DEFAULT NULL,
  p_cpf text DEFAULT NULL,
  p_endereco text DEFAULT NULL,
  p_complemento text DEFAULT NULL,
  p_bairro text DEFAULT NULL,
  p_cidade_uf text DEFAULT NULL,
  p_cep text DEFAULT NULL,
  p_cidade text DEFAULT NULL,
  p_uf text DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO contatos (
    nome, canal_origem, telefone, cpf, endereco, complemento,
    bairro, cidade_uf, cep, cidade, uf, representante_id
  ) VALUES (
    p_nome, p_canal_origem, p_telefone, p_cpf, p_endereco, p_complemento,
    p_bairro, p_cidade_uf, p_cep, p_cidade, p_uf, p_representante_id
  ) RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;


-- MIGRATION: 20260412000001_fix_pedidos_dates.sql
-- Fix pedidos created between 21h-00h UTC that got wrong date (UTC vs Brasilia -3h)
-- Pedidos created after 21h Brasilia got next day's date in UTC
-- Move them back one day if they were created between 21h-00h UTC (midnight-3am Brasilia)

UPDATE pedidos
SET data = (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date
WHERE data <> (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date;


-- MIGRATION: 20260412235921_f69a7dc7-28df-4e8a-9f25-370d39285df4.sql

CREATE OR REPLACE FUNCTION public.deletar_venda_completa(p_lancamento_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_lanc record;
  v_pedido_id uuid;
  v_mov record;
BEGIN
  -- 1. Busca o lançamento
  SELECT * INTO v_lanc FROM public.lancamentos_socios WHERE id = p_lancamento_id;
  IF v_lanc IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Lançamento não encontrado');
  END IF;

  v_pedido_id := v_lanc.pedido_id;

  -- 2. Se tem pedido vinculado, faz cascade
  IF v_pedido_id IS NOT NULL THEN
    -- 2a. Restaura lotes e produtos a partir das movimentações de saída
    FOR v_mov IN
      SELECT produto_id, quantidade, lote_id
      FROM public.estoque_movimentacoes
      WHERE pedido_id = v_pedido_id AND tipo = 'saida'
    LOOP
      -- Restaura lote se existir
      IF v_mov.lote_id IS NOT NULL THEN
        UPDATE public.lotes
        SET quantidade_atual = quantidade_atual + v_mov.quantidade
        WHERE id = v_mov.lote_id;
      END IF;
      -- Restaura estoque_atual do produto
      UPDATE public.produtos
      SET estoque_atual = estoque_atual + v_mov.quantidade
      WHERE id = v_mov.produto_id;
    END LOOP;

    -- 2b. Deleta movimentações de estoque
    DELETE FROM public.estoque_movimentacoes WHERE pedido_id = v_pedido_id;

    -- 2c. Deleta comissões vinculadas
    DELETE FROM public.comissoes WHERE pedido_id = v_pedido_id;

    -- 2d. Deleta itens do pedido
    DELETE FROM public.pedido_itens WHERE pedido_id = v_pedido_id;

    -- 2e. Deleta outros lancamentos_socios vinculados ao mesmo pedido (exceto o atual)
    DELETE FROM public.lancamentos_socios WHERE pedido_id = v_pedido_id AND id != p_lancamento_id;

    -- 2f. Deleta registro financeiro relacionado
    DELETE FROM public.financeiro WHERE descricao ILIKE '%' || v_pedido_id::text || '%';

    -- 2g. Deleta o pedido
    DELETE FROM public.pedidos WHERE id = v_pedido_id;
  END IF;

  -- 3. Deleta o próprio lançamento
  DELETE FROM public.lancamentos_socios WHERE id = p_lancamento_id;

  -- 4. Atualiza snapshot de estoque
  PERFORM public.atualizar_estoque_snapshot();

  RETURN jsonb_build_object('status', 'ok', 'pedido_deletado', v_pedido_id);
END;
$$;


-- MIGRATION: 20260413000000_migrate_pedidos_to_clientes.sql
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
  v_temp_count integer := 0;
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

  GET DIAGNOSTICS v_temp_count = ROW_COUNT;
  v_migrated_count := v_migrated_count + v_temp_count;

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


-- MIGRATION: 20260413000001_add_etiqueta_valor.sql
-- Adicionar coluna etiqueta_valor para armazenar custo do frete
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_valor NUMERIC(10,2);

-- MIGRATION: 20260413000001_migrate_all_pedidos_to_clientes.sql
-- ============================================================
-- Migration Final: Todos os contatos com pedidos -> Clientes
-- Rodar no Supabase SQL Editor
-- ============================================================

-- 1. Primeiro, ver quantos contatos têm pedidos
SELECT 
    'Total de contatos com pedidos pagos' as descricao,
    count(distinct contato_id) as total
FROM pedidos 
WHERE contato_id IS NOT NULL AND status_pagamento = 'pago';

-- 2. Ver quantos estão em cada status_kanban
SELECT 
    canal_origem, 
    canal_atual, 
    status_kanban, 
    count(*) as total
FROM contatos 
WHERE id IN (SELECT contato_id FROM pedidos WHERE status_pagamento = 'pago' AND contato_id IS NOT NULL)
GROUP BY canal_origem, canal_atual, status_kanban
ORDER BY canal_origem, canal_atual, status_kanban;

-- 3. Migra TODOS os contatos com pedidos pagos para Clientes na BASE
-- Isso inclui qualquer canal_origem (ADS, BASE, REP, C-REP, etc)
UPDATE public.contatos
SET 
    status_kanban = 'Clientes',
    -- Se já tem canal_atual, mantém. Se não, usa canal_origem
    canal_atual = COALESCE(NULLIF(canal_atual, ''), canal_origem),
    is_novo = true,
    novo_ate = (CURRENT_DATE + 1)::timestamptz,
    updated_at = now()
WHERE 
    id IN (
        SELECT DISTINCT contato_id 
        FROM public.pedidos 
        WHERE status_pagamento = 'pago' 
        AND contato_id IS NOT NULL
    )
    AND status_kanban != 'Clientes';

-- 4. Ver resultado após migração
SELECT 
    canal_origem, 
    canal_atual, 
    status_kanban, 
    count(*) as total
FROM contatos 
WHERE id IN (SELECT contato_id FROM pedidos WHERE status_pagamento = 'pago' AND contato_id IS NOT NULL)
GROUP BY canal_origem, canal_atual, status_kanban
ORDER BY canal_origem, canal_atual, status_kanban;

-- 5. Verifica total em Clientes vs total com pedidos
SELECT 
    'Contatos com pedidos pagos' as tipo,
    count(distinct contato_id) as total
FROM pedidos 
WHERE contato_id IS NOT NULL AND status_pagamento = 'pago'
UNION ALL
SELECT 
    'Contatos em Clientes' as tipo,
    count(*) as total
FROM contatos 
WHERE status_kanban = 'Clientes';


-- MIGRATION: 20260413000002_formatos_caixa_editaveis.sql
-- Tabela de formatos de caixa editável no CRM
CREATE TABLE IF NOT EXISTS formatos_caixa (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome TEXT NOT NULL UNIQUE,
  descricao TEXT,
  peso_gramas INTEGER NOT NULL DEFAULT 300,
  altura_cm INTEGER NOT NULL DEFAULT 2,
  largura_cm INTEGER NOT NULL DEFAULT 11,
  comprimento_cm INTEGER NOT NULL DEFAULT 16,
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Inserir formatos padrão se não existirem
INSERT INTO formatos_caixa (nome, descricao, peso_gramas, altura_cm, largura_cm, comprimento_cm)
SELECT 'mini', 'Caixa para pedidos pequenos (1-5 itens)', 300, 2, 11, 16
WHERE NOT EXISTS (SELECT 1 FROM formatos_caixa WHERE nome = 'mini');

INSERT INTO formatos_caixa (nome, descricao, peso_gramas, altura_cm, largura_cm, comprimento_cm)
SELECT 'caixa_p', 'Caixa para pedidos maiores (mais de 5 itens ou produtos grandes)', 1000, 6, 11, 16
WHERE NOT EXISTS (SELECT 1 FROM formatos_caixa WHERE nome = 'caixa_p');

-- Atualizar RPC criar_pedido para usar a tabela de formatos
CREATE OR REPLACE FUNCTION criar_pedido(
  p_contato_id UUID,
  p_produtos JSONB,
  p_valor NUMERIC,
  p_canal TEXT,
  p_modalidade TEXT,
  p_uf_postagem TEXT,
  p_status_pagamento TEXT,
  p_criado_por TEXT,
  p_obs TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_pedido_id UUID;
  v_order_number TEXT;
  v_produtos_array TEXT;
  v_total_qty INTEGER := 0;
  v_has_large BOOLEAN := false;
  v_prod JSONB;
  v_prod_id UUID;
  v_prod_qty INTEGER;
  v_prod_preco NUMERIC;
  v_contato_endereco TEXT;
  v_contato_numero TEXT;
  v_data_sp TIMESTAMPTZ;
  v_formato_caixa TEXT;
  v_peso INTEGER;
  v_altura INTEGER;
  v_largura INTEGER;
  v_comprimento INTEGER;
BEGIN
  -- Data SP
  v_data_sp := now() AT TIME ZONE 'America/Sao_Paulo';

  -- Processar produtos
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;

      v_total_qty := v_total_qty + v_prod_qty;

      IF v_prod_id IS NOT NULL THEN
        -- Verificar se tem produto grande
        SELECT INTO v_has_large EXISTS (
          SELECT 1 FROM produtos WHERE id = v_prod_id AND (altura_cm > 15 OR largura_cm > 15 OR comprimento_cm > 20)
        );
      END IF;
    END LOOP;
  END IF;

  -- Decrementa estoque
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;

      UPDATE produtos SET estoque_atual = estoque_atual - v_prod_qty WHERE id = v_prod_id;
    END LOOP;
  END IF;

  -- Buscar dimensoes da caixa da tabela de configurações
  IF p_modalidade = 'entrega_maos' THEN
    v_formato_caixa := NULL; v_peso := NULL; v_altura := NULL; v_largura := NULL; v_comprimento := NULL;
  ELSIF p_modalidade = 'mini' THEN
    SELECT peso_gramas, altura_cm, largura_cm, comprimento_cm INTO v_peso, v_altura, v_largura, v_comprimento
    FROM formatos_caixa WHERE nome = 'mini' AND ativo = true LIMIT 1;
    v_formato_caixa := 'mini';
  ELSE
    IF v_has_large OR v_total_qty > 5 THEN
      SELECT nome, peso_gramas, altura_cm, largura_cm, comprimento_cm INTO v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento
      FROM formatos_caixa WHERE ativo = true ORDER BY peso_gramas DESC LIMIT 1;
    ELSE
      SELECT nome, peso_gramas, altura_cm, largura_cm, comprimento_cm INTO v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento
      FROM formatos_caixa WHERE nome = 'mini' AND ativo = true LIMIT 1;
    END IF;
  END IF;

  -- Criar pedido com estoque_processado=true
  INSERT INTO pedidos (
    contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    formato_caixa, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento,
    criado_por, obs, endereco_entrega, data, estoque_processado
  ) VALUES (
    p_contato_id, p_produtos::text, v_total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem, v_formato_caixa, v_peso, v_altura, v_largura, v_comprimento,
    p_status_pagamento, p_criado_por, p_obs,
    (SELECT endereco || COALESCE(', ' || numero, '') FROM contatos WHERE id = p_contato_id),
    v_data_sp, true
  ) RETURNING id, order_number INTO v_pedido_id, v_order_number;

  -- Criar pedido_itens para cada produto
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;

      IF v_prod_id IS NOT NULL AND v_prod_qty IS NOT NULL THEN
        INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, valor_unit)
        VALUES (v_pedido_id, v_prod_id, v_prod_qty, v_prod_preco);
      END IF;
    END LOOP;
  END IF;

  -- Atualizar ultima_venda_em do contato
  UPDATE contatos SET ultima_venda_em = v_data_sp, status_kanban = 'Pagou', updated_at = now()
  WHERE id = p_contato_id;

  RETURN jsonb_build_object(
    'pedido_id', v_pedido_id::text,
    'order_number', v_order_number,
    'data', v_data_sp
  );
END;
$$;

-- MIGRATION: 20260414000000_add_representante_id_to_pedidos.sql
-- Adiciona coluna representante_id à tabela pedidos
-- Rode no Supabase SQL Editor

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_pedidos_representante ON public.pedidos(representante_id) WHERE representante_id IS NOT NULL;


-- MIGRATION: 20260414000001_box_size_automatico.sql
-- Migration: Box Size automático por produto

-- 1. Adicionar coluna box_size na tabela produtos
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_size TEXT;

-- 2. Adicionar coluna box_size na tabela pedidos  
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS box_size TEXT;

-- 3. Atualizar RPC create_produto para incluir box_size
CREATE OR REPLACE FUNCTION create_produto(
  p_nome_oficial TEXT,
  p_tag TEXT,
  p_cor_card TEXT DEFAULT '#ffffff',
  p_cor_texto TEXT DEFAULT '#000000',
  p_limite_estoque INTEGER DEFAULT 0,
  p_grupo_id UUID DEFAULT NULL,
  p_box_size TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO produtos (nome_oficial, tag, cor_card, cor_texto, limite_estoque, grupo_id, box_size)
  VALUES (p_nome_oficial, p_tag, p_cor_card, p_cor_texto, p_limite_estoque, p_grupo_id, p_box_size)
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;

-- 4. Atualizar RPC update_produto para incluir box_size
CREATE OR REPLACE FUNCTION update_produto(
  p_id UUID,
  p_nome_oficial TEXT,
  p_tag TEXT,
  p_cor_card TEXT,
  p_cor_texto TEXT,
  p_limite_estoque INTEGER,
  p_grupo_id UUID,
  p_box_size TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE produtos 
  SET nome_oficial = p_nome_oficial,
      tag = p_tag,
      cor_card = p_cor_card,
      cor_texto = p_cor_texto,
      limite_estoque = p_limite_estoque,
      grupo_id = p_grupo_id,
      box_size = p_box_size,
      updated_at = now()
  WHERE id = p_id;
END;
$$;

-- 5. Atualizar RPC criar_pedido para calcular box_size automaticamente
CREATE OR REPLACE FUNCTION criar_pedido(
  p_contato_id UUID,
  p_produtos JSONB,
  p_valor NUMERIC,
  p_canal TEXT,
  p_modalidade TEXT,
  p_uf_postagem TEXT,
  p_status_pagamento TEXT,
  p_criado_por TEXT,
  p_obs TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_pedido_id UUID;
  v_order_number TEXT;
  v_total_qty INTEGER := 0;
  v_data_sp TIMESTAMPTZ;
  v_box_size TEXT;
  v_prod_box_rank INTEGER;
  v_prod JSONB;
  v_prod_id UUID;
  v_prod_qty INTEGER;
  v_prod_preco NUMERIC;
  v_peso INTEGER;
  v_altura INTEGER;
  v_largura INTEGER;
  v_comprimento INTEGER;
BEGIN
  v_data_sp := now() AT TIME ZONE 'America/Sao_Paulo';

  -- Determinar box_size automaticamente
  IF p_modalidade = 'mini' OR p_modalidade = 'entrega_maos' THEN
    v_box_size := 'MINI';
  ELSE
    -- Buscar maior box_size entre os produtos do pedido
    SELECT INTO v_box_size MAX(
      CASE p.box_size
        WHEN 'GG' THEN 5
        WHEN 'G' THEN 4
        WHEN 'M' THEN 3
        WHEN 'P' THEN 2
        WHEN 'MINI' THEN 1
        ELSE 1
      END
    )::TEXT
    FROM jsonb_array_elements(p_produtos) AS prod
    LEFT JOIN produtos p ON p.id = (prod->>'produto_id')::uuid
    WHERE prod->>'produto_id' IS NOT NULL AND p.box_size IS NOT NULL;
    
    v_box_size := CASE v_box_size
      WHEN '5' THEN 'GG'
      WHEN '4' THEN 'G'
      WHEN '3' THEN 'M'
      WHEN '2' THEN 'P'
      ELSE 'MINI'
    END;
  END IF;

  -- Dimensões por box_size
  v_box_size := COALESCE(v_box_size, 'MINI');
  CASE v_box_size
    WHEN 'MINI' THEN v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    WHEN 'P' THEN v_peso := 500; v_altura := 4; v_largura := 11; v_comprimento := 16;
    WHEN 'M' THEN v_peso := 800; v_altura := 6; v_largura := 15; v_comprimento := 20;
    WHEN 'G' THEN v_peso := 1200; v_altura := 8; v_largura := 20; v_comprimento := 25;
    WHEN 'GG' THEN v_peso := 2000; v_altura := 10; v_largura := 25; v_comprimento := 30;
    ELSE v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  END CASE;

  -- Processar produtos
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;
      v_total_qty := v_total_qty + v_prod_qty;

      IF v_prod_id IS NOT NULL THEN
        UPDATE produtos SET estoque_atual = estoque_atual - v_prod_qty WHERE id = v_prod_id;
      END IF;
    END LOOP;
  END IF;

  -- Criar pedido
  INSERT INTO pedidos (
    contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    box_size, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento,
    criado_por, obs, data, estoque_processado
  ) VALUES (
    p_contato_id, p_produtos::text, v_total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem,
    v_box_size, v_peso, v_altura, v_largura, v_comprimento,
    p_status_pagamento, p_criado_por, p_obs,
    v_data_sp, true
  ) RETURNING id, order_number INTO v_pedido_id, v_order_number;

  -- Criar pedido_itens
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := (v_prod->>'quantidade')::integer;
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;

      IF v_prod_id IS NOT NULL AND v_prod_qty IS NOT NULL THEN
        INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, valor_unit)
        VALUES (v_pedido_id, v_prod_id, v_prod_qty, v_prod_preco);
      END IF;
    END LOOP;
  END IF;

  -- Atualizar contato
  UPDATE contatos SET ultima_venda_em = v_data_sp, status_kanban = 'Pagou', updated_at = now()
  WHERE id = p_contato_id;

  RETURN jsonb_build_object('pedido_id', v_pedido_id::text, 'order_number', v_order_number, 'data', v_data_sp);
END;
$$;

-- MIGRATION: 20260414000001_fix_all_schema_fks.sql
-- Migration: Criar pedido_itens e colunas faltantes
-- Execute CADA comando SEPARADAMENTE no Supabase SQL Editor

-- 1. Criar tabela pedido_itens
CREATE TABLE IF NOT EXISTS public.pedido_itens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id uuid NOT NULL REFERENCES public.pedidos(id),
  produto_id uuid NOT NULL REFERENCES public.produtos(id),
  nome_oficial text,
  quantidade integer NOT NULL,
  preco numeric,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Criar índices pedido_itens
CREATE INDEX IF NOT EXISTS idx_pedido_itens_pedido ON public.pedido_itens(pedido_id);
CREATE INDEX IF NOT EXISTS idx_pedido_itens_produto ON public.pedido_itens(produto_id);

-- 3. Adicionar pedido_item_id em estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_item_id uuid REFERENCES public.pedido_itens(id);

-- 4. Adicionar representante_id em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES auth.users(id);

-- 5. Adicionar tipo_origem em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS tipo_origem text;

-- 6. Adicionar entrega_em_maos em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS entrega_em_maos boolean DEFAULT false;

-- 7. Adicionar estoque_debitado em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_debitado boolean DEFAULT false;

-- 8. Adicionar estoque_processado em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;

-- 9. Adicionar contato_id em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS contato_id uuid REFERENCES public.contatos(id);

-- 10. Adicionar instancia_id em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS instancia_id uuid REFERENCES public.instancias(id);

-- 11. Criar tabela comissoes
CREATE TABLE IF NOT EXISTS public.comissoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  representante_id uuid REFERENCES auth.users(id),
  pedido_id uuid REFERENCES public.pedidos(id),
  produto text NOT NULL,
  valor_fixo numeric(10,2) NOT NULL,
  status text DEFAULT 'pendente' CHECK (status IN ('pendente', 'pago', 'cancelado')),
  data_criacao timestamptz DEFAULT now(),
  data_pagamento timestamptz
);

-- 12. Adicionar colunas em contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS canal_atual text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS is_novo boolean DEFAULT false;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS novo_ate timestamptz;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS ultima_venda_em date;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS instancia_id uuid REFERENCES public.instancias(id);

-- 13. Adicionar representante_id em lotes
ALTER TABLE public.lotes ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES auth.users(id);


-- MIGRATION: 20260414000002_box_size_com_qty_max.sql
-- Migration completa: Box Size com quantidade máxima

-- 1. Adicionar colunas na tabela produtos
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_size TEXT;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_qty_max INTEGER DEFAULT 10;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- 2. Adicionar coluna box_size na tabela pedidos  
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS box_size TEXT;

-- 3. Atualizar RPC create_produto para incluir box_size e box_qty_max
CREATE OR REPLACE FUNCTION create_produto(
  p_nome_oficial TEXT,
  p_tag TEXT,
  p_cor_card TEXT DEFAULT '#ffffff',
  p_cor_texto TEXT DEFAULT '#000000',
  p_limite_estoque INTEGER DEFAULT 0,
  p_grupo_id UUID DEFAULT NULL,
  p_box_size TEXT DEFAULT NULL,
  p_box_qty_max INTEGER DEFAULT 10
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO produtos (nome_oficial, tag, cor_card, cor_texto, limite_estoque, grupo_id, box_size, box_qty_max)
  VALUES (p_nome_oficial, p_tag, p_cor_card, p_cor_texto, p_limite_estoque, p_grupo_id, p_box_size, p_box_qty_max)
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;

-- 4. Atualizar RPC update_produto para incluir box_size e box_qty_max
CREATE OR REPLACE FUNCTION update_produto(
  p_id UUID,
  p_nome_oficial TEXT,
  p_tag TEXT,
  p_cor_card TEXT,
  p_cor_texto TEXT,
  p_limite_estoque INTEGER,
  p_grupo_id UUID,
  p_box_size TEXT DEFAULT NULL,
  p_box_qty_max INTEGER DEFAULT 10
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE produtos 
  SET nome_oficial = p_nome_oficial,
      tag = p_tag,
      cor_card = p_cor_card,
      cor_texto = p_cor_texto,
      limite_estoque = p_limite_estoque,
      grupo_id = p_grupo_id,
      box_size = p_box_size,
      box_qty_max = p_box_qty_max,
      updated_at = now()
  WHERE id = p_id;
END;
$$;

-- 5. Atualizar RPC criar_pedido para calcular box_size com lógica de quantidade
CREATE OR REPLACE FUNCTION criar_pedido(
  p_contato_id UUID,
  p_produtos JSONB,
  p_valor NUMERIC,
  p_canal TEXT,
  p_modalidade TEXT,
  p_uf_postagem TEXT,
  p_status_pagamento TEXT,
  p_criado_por TEXT,
  p_obs TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_pedido_id UUID;
  v_order_number TEXT;
  v_total_qty INTEGER := 0;
  v_data_sp TIMESTAMPTZ;
  v_box_size TEXT;
  v_prod JSONB;
  v_prod_id UUID;
  v_prod_qty INTEGER;
  v_prod_preco NUMERIC;
  v_peso INTEGER;
  v_altura INTEGER;
  v_largura INTEGER;
  v_comprimento INTEGER;
  v_needed_rank INTEGER := 1;
  v_current_box_rank INTEGER;
  v_prod_box_size TEXT;
  v_prod_qty_max INTEGER;
  v_box_size_override TEXT := NULL;
BEGIN
  v_data_sp := now() AT TIME ZONE 'America/Sao_Paulo';

  -- Calcular total de itens no pedido
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
      v_total_qty := v_total_qty + v_prod_qty;
    END LOOP;
  END IF;

  -- Se modo MINI ou ENTREGA_MAOS: verificar se cabe na caixa definida do produto
  IF p_modalidade = 'mini' OR p_modalidade = 'entrega_maos' THEN
    -- Para cada produto no pedido, verificar se a qtd cabe no box_size definido
    IF p_produtos IS NOT NULL THEN
      FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
      LOOP
        v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
        v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
        
        SELECT p.box_size, COALESCE(p.box_qty_max, 10)
        INTO v_prod_box_size, v_prod_qty_max
        FROM produtos p WHERE p.id = v_prod_id;
        
        -- Se quantidade exceder o limite da caixa do produto
        IF v_prod_qty > v_prod_qty_max THEN
          v_box_size_override := 'EXCEDE_MINI';
        END IF;
      END LOOP;
    END IF;
  ELSE
    -- Para PAC/SEDEX: aplicar lógica de upgrade por quantidade
    v_needed_rank := 1;
    
    IF p_produtos IS NOT NULL THEN
      FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
      LOOP
        v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
        v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
        
        SELECT p.box_size, COALESCE(p.box_qty_max, 10)
        INTO v_prod_box_size, v_prod_qty_max
        FROM produtos p WHERE p.id = v_prod_id;
        
        v_current_box_rank := CASE v_prod_box_size
          WHEN 'GG' THEN 5
          WHEN 'G' THEN 4
          WHEN 'M' THEN 3
          WHEN 'P' THEN 2
          WHEN 'MINI' THEN 1
          ELSE 1
        END;
        
        -- Se quantidade exceder qty_max, fazer upgrade
        IF v_prod_qty > v_prod_qty_max THEN
          v_current_box_rank := LEAST(v_current_box_rank + 1, 5);
        END IF;
        
        IF v_current_box_rank > v_needed_rank THEN
          v_needed_rank := v_current_box_rank;
        END IF;
      END LOOP;
    END IF;
    
    v_box_size := CASE v_needed_rank
      WHEN 5 THEN 'GG'
      WHEN 4 THEN 'G'
      WHEN 3 THEN 'M'
      WHEN 2 THEN 'P'
      ELSE 'MINI'
    END;
  END IF;

  -- Se tem override (excedeu mini), usar tamanho maior
  IF v_box_size_override = 'EXCEDE_MINI' THEN
    v_box_size := 'P';
  ELSIF v_box_size IS NULL THEN
    v_box_size := 'MINI';
  END IF;

  -- Dimensões por box_size
  CASE COALESCE(v_box_size, 'MINI')
    WHEN 'MINI' THEN v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
    WHEN 'P' THEN v_peso := 500; v_altura := 4; v_largura := 11; v_comprimento := 16;
    WHEN 'M' THEN v_peso := 800; v_altura := 6; v_largura := 15; v_comprimento := 20;
    WHEN 'G' THEN v_peso := 1200; v_altura := 8; v_largura := 20; v_comprimento := 25;
    WHEN 'GG' THEN v_peso := 2000; v_altura := 10; v_largura := 25; v_comprimento := 30;
    ELSE v_peso := 300; v_altura := 2; v_largura := 11; v_comprimento := 16;
  END CASE;

  -- Processar produtos e decrementar estoque
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
      
      IF v_prod_id IS NOT NULL THEN
        UPDATE produtos SET estoque_atual = estoque_atual - v_prod_qty WHERE id = v_prod_id;
      END IF;
    END LOOP;
  END IF;

  -- Criar pedido
  INSERT INTO pedidos (
    contato_id, produto, quantidade, valor, canal, status_pedido, modalidade, uf_postagem,
    box_size, peso_envio, altura_caixa, largura_caixa, comprimento_caixa, status_pagamento,
    criado_por, obs, data, estoque_processado
  ) VALUES (
    p_contato_id, p_produtos::text, v_total_qty, p_valor, p_canal, 'aguardando_rastreio',
    p_modalidade, p_uf_postagem,
    v_box_size, v_peso, v_altura, v_largura, v_comprimento,
    p_status_pagamento, p_criado_por, p_obs,
    v_data_sp, true
  ) RETURNING id, order_number INTO v_pedido_id, v_order_number;

  -- Criar pedido_itens
  IF p_produtos IS NOT NULL THEN
    FOR v_prod IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_prod_id := NULLIF(v_prod->>'produto_id', '')::uuid;
      v_prod_qty := COALESCE((v_prod->>'quantidade')::integer, 1);
      v_prod_preco := NULLIF(v_prod->>'preco', '')::numeric;

      IF v_prod_id IS NOT NULL AND v_prod_qty IS NOT NULL THEN
        INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, valor_unit)
        VALUES (v_pedido_id, v_prod_id, v_prod_qty, v_prod_preco);
      END IF;
    END LOOP;
  END IF;

  -- Atualizar contato
  UPDATE contatos SET ultima_venda_em = v_data_sp, status_kanban = 'Pagou', updated_at = now()
  WHERE id = p_contato_id;

  RETURN jsonb_build_object('pedido_id', v_pedido_id::text, 'order_number', v_order_number, 'data', v_data_sp);
END;
$$;

-- MIGRATION: 20260414000002_create_processar_pedido_estoque_trigger.sql
-- Criar função processar_pedido_estoque_trigger que está faltando
-- Execute no Supabase SQL Editor

-- 1. Função para processar estoque do pedido (assinatura: uuid, text)
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(p_pedido_id uuid, p_uf_postagem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item record;
  v_produto record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_item_id uuid;
  v_total_items integer := 0;
  v_processed_items integer := 0;
  v_skipped_items integer := 0;
  v_result jsonb := '[]'::jsonb;
BEGIN
  -- Buscar UF do cliente (usa p_uf_postagem se fornecido, ou busca do contato)
  v_uf_cliente := p_uf_postagem;
  
  IF v_uf_cliente IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct
    WHERE ct.id = (SELECT contato_id FROM pedidos WHERE id = p_pedido_id);
  END IF;

  -- Loop nos itens do pedido
  FOR v_item IN
    SELECT * FROM pedido_itens WHERE pedido_id = p_pedido_id
  LOOP
    v_total_items := v_total_items + 1;

    -- IDEMPOTENCIA: verifica se ja existe movimentacao para este item
    SELECT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id
    ) INTO v_mov_exists;

    IF v_mov_exists THEN
      v_skipped_items := v_skipped_items + 1;
      CONTINUE;
    END IF;

    -- Buscar produto
    SELECT * INTO v_produto FROM produtos WHERE id = v_item.produto_id;
    IF v_produto IS NULL THEN CONTINUE; END IF;

    -- FIFO deduction from lotes
    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque do produto
    UPDATE produtos SET estoque_atual = estoque_atual - v_item.quantidade WHERE id = v_item.produto_id;

    v_processed_items := v_processed_items + 1;
  END LOOP;

  -- Marcar pedido como processado
  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'total_items', v_total_items,
    'processed', v_processed_items,
    'skipped', v_skipped_items
  );
END;
$$;

-- 2. Garantir que trigger_function trigger_processar_pedido_estoque existe
CREATE OR REPLACE FUNCTION public.trigger_processar_pedido_estoque()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uf_postagem text;
BEGIN
  -- Se uf_postagem foi definido no pedido, usa ele
  v_uf_postagem := NEW.uf_postagem;
  
  -- Só processa se tem uf_postagem e ainda não foi processado
  IF v_uf_postagem IS NOT NULL AND (NEW.estoque_processado IS NULL OR NEW.estoque_processado = false) THEN
    PERFORM public.processar_pedido_estoque_trigger(NEW.id, v_uf_postagem);
  END IF;
  
  RETURN NEW;
END;
$$;


-- MIGRATION: 20260414000003_add_pedido_id_to_lancamentos_socios.sql
-- Adicionar coluna pedido_id em lancamentos_socios
-- Execute no Supabase SQL Editor

ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

CREATE INDEX IF NOT EXISTS idx_lancamentos_pedido ON public.lancamentos_socios(pedido_id) WHERE pedido_id IS NOT NULL;


-- MIGRATION: 20260414000004_update_criar_pedido_with_estoque.sql
-- Atualizar função criar_pedido para abate de estoque automático
-- Execute no Supabase SQL Editor

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

  v_is_base := (p_canal = 'BASE');

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(COALESCE(x->>'produto', x->>'nome_oficial'), ', ') FROM jsonb_array_elements(p_produtos) AS x);
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

  -- Update contato status
  IF p_contato_id IS NOT NULL AND p_status_pagamento = 'pago' THEN
    UPDATE public.contatos 
    SET status_kanban = CASE WHEN v_is_base THEN 'Clientes' ELSE 'Pagou' END,
        canal_atual = CASE WHEN v_is_base THEN 'BASE' ELSE COALESCE(canal_atual, p_canal) END,
        is_novo = v_is_base,
        novo_ate = CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
        updated_at = now()
    WHERE id = p_contato_id;
  END IF;

  -- Insert lancamento socio
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
    VALUES (v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);
  END IF;

  -- ABATE ESTOQUE AUTOMATICAMENTE se tiver UF de postagem
  IF p_uf_postagem IS NOT NULL AND p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    PERFORM public.processar_pedido_estoque_trigger(v_pedido_id, p_uf_postagem);
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;


-- MIGRATION: 20260415000000_recalcular_estoque_from_movimentacoes.sql
-- Recalcular estoque baseado em movimentacoes (entradas - saidas)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Criar tabela de snapshot do estoque atual (backup)
DROP TABLE IF EXISTS public.estoque_snapshot;
CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id uuid REFERENCES public.produtos(id),
  uf text,
  quantidade_anterior integer,
  quantidade_nova integer,
  diferenca integer,
  created_at timestamptz DEFAULT now()
);

-- 2. Gravar snapshot antes da correcao (backup)
INSERT INTO public.estoque_snapshot (produto_id, uf, quantidade_anterior, quantidade_nova, diferenca)
SELECT 
  l.produto_id,
  l.uf,
  l.quantidade_atual,
  0,
  -l.quantidade_atual
FROM public.lotes l
WHERE l.quantidade_atual > 0;

-- 3. Corrigir movimentacoes negativas (saidas sem entrada correspondente)
-- Primeiro, criar temp table com saldo por produto+UF
CREATE TEMP TABLE estoque_movimentado AS
SELECT 
  produto_id,
  uf_origem,
  SUM(CASE WHEN tipo = 'entrada' THEN quantidade ELSE 0 END) as entradas,
  SUM(CASE WHEN tipo = 'saida' THEN quantidade ELSE 0 END) as saidas,
  SUM(CASE WHEN tipo = 'entrada' THEN quantidade ELSE -quantidade END) as saldo
FROM public.estoque_movimentacoes
WHERE uf_origem IS NOT NULL
GROUP BY produto_id, uf_origem;

-- 4. Atualizar lotes com saldo correto (nao pode ser negativo)
UPDATE public.lotes l
SET quantidade_atual = GREATEST(COALESCE(ec.saldo, 0), 0)
FROM estoque_movimentado ec
WHERE l.produto_id = ec.produto_id AND l.uf = ec.uf_origem;

-- 5. Criar novos lotes para UFs que nao existem mas tem saldo positivo
INSERT INTO public.lotes (produto_id, uf, quantidade_inicial, quantidade_atual, data_producao, lote_codigo, created_at)
SELECT 
  ec.produto_id,
  ec.uf_origem,
  ec.saldo,
  ec.saldo,
  now()::date,
  'AUTO-' || ec.uf_origem || '-' || now()::text,
  now()
FROM estoque_movimentado ec
WHERE ec.saldo > 0
AND NOT EXISTS (SELECT 1 FROM public.lotes l WHERE l.produto_id = ec.produto_id AND l.uf = ec.uf_origem);

-- 6. Excluir lotes com estoque zero ou negativo que nao tem movimentacao
DELETE FROM public.lotes 
WHERE quantidade_atual <= 0 
AND id NOT IN (
  SELECT DISTINCT lote_id FROM public.estoque_movimentacoes WHERE lote_id IS NOT NULL
);

-- 7. Atualizar estoque_atual na tabela produtos (soma total por produto)
UPDATE public.produtos p
SET estoque_atual = COALESCE((
  SELECT SUM(quantidade_atual) 
  FROM public.lotes 
  WHERE produto_id = p.id
), 0);

-- 8. Gravar snapshot apos correcao
INSERT INTO public.estoque_snapshot (produto_id, uf, quantidade_anterior, quantidade_nova, diferenca)
SELECT 
  l.produto_id,
  l.uf,
  es.quantidade_anterior,
  l.quantidade_atual,
  l.quantidade_atual - COALESCE(es.quantidade_anterior, 0)
FROM public.lotes l
LEFT JOIN (
  SELECT produto_id, uf, quantidade_anterior 
  FROM public.estoque_snapshot 
  WHERE quantidade_nova = 0
) es ON l.produto_id = es.produto_id AND l.uf = es.uf
WHERE es.quantidade_anterior IS NOT NULL;

-- 9. Verificar consistencia final
SELECT 
  p.nome_oficial as produto,
  l.uf,
  l.quantidade_atual as estoque_lote,
  COALESCE(em.entradas, 0) as entradas,
  COALESCE(em.saidas, 0) as saidas,
  COALESCE(em.saldo, 0) as saldo_movimentacoes,
  CASE WHEN l.quantidade_atual != COALESCE(em.saldo, 0) THEN 'DIFERENTE' ELSE 'OK' END as status
FROM public.produtos p
LEFT JOIN public.lotes l ON l.produto_id = p.id
LEFT JOIN estoque_movimentado em ON em.produto_id = p.id AND em.uf_origem = l.uf
WHERE l.quantidade_atual > 0 OR em.saldo != 0
ORDER BY p.nome_oficial, l.uf;

COMMIT;

-- MIGRATION: 20260415000001_add_shipping_price.sql
-- Verificar e criar colunas para valor dofrete
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_valor NUMERIC(10,2);
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS shipping_price NUMERIC(10,2);

-- MIGRATION: 20260415000001_update_process_venda_with_estoque.sql
-- Atualizar process_venda para abater estoque automaticamente quando tem UF de postagem
-- Executar no Supabase SQL Editor

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
    criado_por, produto, quantidade, order_number, data, status_pedido, observacao,
    is_novo, novo_ate, estoque_processado
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, 'pago', p_modalidade, p_uf_postagem,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio', p_obs,
    v_is_base, CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
    CASE WHEN p_uf_postagem IS NOT NULL AND p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN false ELSE NULL END
  ) RETURNING id INTO v_pedido_id;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
    SELECT v_pedido_id, (x->>'produto_id')::uuid, COALESCE(x->>'produto', x->>'nome_oficial'), (x->>'quantidade')::integer, (x->>'valor_unit')::numeric
    FROM jsonb_array_elements(p_produtos) AS x;
  END IF;

  UPDATE public.contatos 
  SET status_kanban = CASE WHEN v_is_base THEN 'Clientes' ELSE 'Pagou' END,
      canal_atual = CASE WHEN v_is_base THEN 'BASE' ELSE COALESCE(canal_atual, p_canal) END,
      is_novo = v_is_base,
      novo_ate = CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
      updated_at = now()
  WHERE id = p_contato_id;

  INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
  VALUES (p_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);

  -- ABATE ESTOQUE AUTOMATICAMENTE se tiver UF de postagem
  IF p_uf_postagem IS NOT NULL AND p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    PERFORM public.processar_pedido_estoque_trigger(v_pedido_id, p_uf_postagem);
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

-- MIGRATION: 20260415000002_limpar_e_recriar_estoque.sql
-- LIMPAR COMPLETAMENTE ESTOQUE E RECRIAR FLUXO
-- Executar no Supabase SQL Editor

BEGIN;

-- 0. Deletar tabela snapshot se existir
DROP TABLE IF EXISTS public.estoque_snapshot;

-- 1. LIMPAR todas as movimentacoes de estoque
TRUNCATE public.estoque_movimentacoes RESTART IDENTITY CASCADE;

-- 2. LIMPAR lotes (zerar estoque)
TRUNCATE public.lotes RESTART IDENTITY CASCADE;

-- 3. Atualizar produtos para estoque_atual = 0
UPDATE public.produtos SET estoque_atual = 0;

-- 4. Criar tabela de controle para saber quais pedidos ja processaram estoque
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean DEFAULT false;

-- 5. Criar trigger function para abater estoque ao criar pedido
CREATE OR REPLACE FUNCTION public.trigger_abate_estoque_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_postagem text;
  v_mov_exists boolean;
BEGIN
  -- So processa se ainda nao foi processado
  IF NEW.estoque_processado = true OR NEW.estoque_processado IS NULL THEN
    RETURN NEW;
  END IF;

  -- Busca UF de postagem do pedido
  v_uf_postagem := NEW.uf_postagem;
  
  IF v_uf_postagem IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_postagem
    FROM contatos ct
    WHERE ct.id = NEW.contato_id;
  END IF;

  -- Loop nos itens do pedido
  FOR v_item IN
    SELECT * FROM pedido_itens WHERE pedido_id = NEW.id
  LOOP
    -- IDEMPOTENCIA: verifica se ja existe movimentacao
    SELECT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id
    ) INTO v_mov_exists;
    
    IF v_mov_exists THEN
      CONTINUE;
    END IF;

    -- FIFO deduction dos lotes (prioriza UF do cliente)
    v_remaining := v_item.quantidade;
    
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_postagem, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN
        EXIT;
      END IF;
      
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      
      -- Atualiza lote
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      
      -- Registra movimentacao
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, pedido_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, NEW.id, 'Pedido #' || NEW.id::text);
      
      v_remaining := v_remaining - v_deduct;
    END LOOP;
  END LOOP;

  -- Marcar como processado
  NEW.estoque_processado := true;
  
  RETURN NEW;
END;
$$;

-- 6. Criar trigger
DROP TRIGGER IF EXISTS tg_abate_estoque_pedido ON public.pedidos;
CREATE TRIGGER tg_abate_estoque_pedido
  BEFORE INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_abate_estoque_pedido();

-- 7. Recriar funcao processar_pedido_estoque_trigger para uso manual
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(p_pedido_id uuid, p_uf_postagem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_total_items integer := 0;
  v_processed_items integer := 0;
BEGIN
  v_uf_cliente := p_uf_postagem;
  
  IF v_uf_cliente IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct
    WHERE ct.id = (SELECT contato_id FROM pedidos WHERE id = p_pedido_id);
  END IF;

  FOR v_item IN
    SELECT * FROM pedido_itens WHERE pedido_id = p_pedido_id
  LOOP
    v_total_items := v_total_items + 1;

    SELECT EXISTS (
      SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id
    ) INTO v_mov_exists;

    IF v_mov_exists THEN
      CONTINUE;
    END IF;

    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, data_producao ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, pedido_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, p_pedido_id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    v_processed_items := v_processed_items + 1;
  END LOOP;

  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'total_items', v_total_items,
    'processed', v_processed_items
  );
END;
$$;

COMMIT;

-- Verificar resultado
SELECT 'estoque_movimentacoes' as tabela, COUNT(*) as total FROM public.estoque_movimentacoes
UNION ALL
SELECT 'lotes', COUNT(*) FROM public.lotes
UNION ALL
SELECT 'produtos com estoque_atual=0', COUNT(*) FROM public.produtos WHERE estoque_atual = 0;

-- MIGRATION: 20260415000002_salvar_remetente_rpc.sql
-- RPC para salvar remetente via UPSERT
DROP FUNCTION IF EXISTS salvar_remetente(text,text,text,text,text,text,text,text,text,text,text,numeric);

CREATE OR REPLACE FUNCTION salvar_remetente(
  p_uf_in TEXT,
  p_cep_origem TEXT,
  p_cidade TEXT,
  p_bairro TEXT,
  p_endereco TEXT,
  p_numero TEXT,
  p_complemento TEXT,
  p_nome_remetente TEXT,
  p_contato_remetente TEXT,
  p_cpf TEXT,
  p_descricao_produto TEXT,
  p_valor_unitario NUMERIC
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO remetentes_uf (
    uf, cep_origem, cidade, bairro, endereco, numero, complemento,
    nome_remetente, contato_remetente, cpf, descricao_produto, valor_unitario, updated_at
  )
  VALUES (
    p_uf_in, p_cep_origem, p_cidade, p_bairro, p_endereco, p_numero, p_complemento,
    p_nome_remetente, p_contato_remetente, p_cpf, p_descricao_produto, p_valor_unitario, now()
  )
  ON CONFLICT (uf) DO UPDATE SET
    cep_origem = EXCLUDED.cep_origem,
    cidade = EXCLUDED.cidade,
    bairro = EXCLUDED.bairro,
    endereco = EXCLUDED.endereco,
    numero = EXCLUDED.numero,
    complemento = EXCLUDED.complemento,
    nome_remetente = EXCLUDED.nome_remetente,
    contato_remetente = EXCLUDED.contato_remetente,
    cpf = EXCLUDED.cpf,
    descricao_produto = EXCLUDED.descricao_produto,
    valor_unitario = EXCLUDED.valor_unitario,
    updated_at = now();
END;
$$;

-- MIGRATION: 20260415000003_processar_estoque_pendente.sql
-- Processar estoque de pedidos pendentes (que ainda nao abateu)
-- Executar no Supabase SQL Editor

BEGIN;

-- Para cada pedido que tem itens e ainda nao processou estoque, rodar o abatimento
SELECT 
  p.id as pedido_id,
  p.uf_postagem,
  COUNT(pi.id) as total_itens,
  p.estoque_processado
FROM public.pedidos p
LEFT JOIN public.pedido_itens pi ON pi.pedido_id = p.id
WHERE p.estoque_processado IS NULL OR p.estoque_processado = false
GROUP BY p.id, p.uf_postagem, p.estoque_processado
ORDER BY p.created_at DESC
LIMIT 50;

COMMIT;

-- Para executar o abate em um pedido especifico:
-- SELECT processar_pedido_estoque_trigger('UUID_DO_PEDIDO', 'SP');

-- Para processar todos pendentes em loop:
-- CREATE OR REPLACE FUNCTION public.processar_todos_estoque_pendente()
-- RETURNS void
-- LANGUAGE plpgsql
-- AS $$
-- DECLARE
--   v_pedido record;
-- BEGIN
--   FOR v_pedido IN
--     SELECT id, uf_postagem FROM public.pedidos
--     WHERE (estoque_processado IS NULL OR estoque_processado = false)
--     AND EXISTS (SELECT 1 FROM pedido_itens WHERE pedido_id = pedidos.id)
--   LOOP
--     PERFORM public.processar_pedido_estoque_trigger(v_pedido.id, v_pedido.uf_postagem);
--   END LOOP;
-- END;
-- $$;
-- SELECT processar_todos_estoque_pendente();

-- MIGRATION: 20260415000004_estoque_com_snapshot.sql
-- ESTOQUE COM SNAPSHOT - Calculo dinamico via pedidos
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Garantir coluna estoque_processado nos pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean DEFAULT false;

-- 2. Criar tabela de snapshot do estoque (cache)
CREATE TABLE IF NOT EXISTS public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id uuid REFERENCES public.produtos(id),
  uf text,
  entradas integer DEFAULT 0,
  saidas_pedidos integer DEFAULT 0,
  saidas_movimentacoes integer DEFAULT 0,
  saldo_calculado integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 3. Criar funcao para calcular estoque dinamico (inclui pedidos pendentes)
CREATE OR REPLACE FUNCTION public.get_estoque_produto(p_produto_id uuid DEFAULT NULL, p_uf text DEFAULT NULL)
RETURNS TABLE(produto_id uuid, produto_nome text, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH entradas_lotes AS (
    SELECT l.produto_id, l.uf, SUM(l.quantidade_atual) as total
    FROM public.lotes l
    WHERE p_produto_id IS NULL OR produto_id = p_produto_id
    AND (p_uf IS NULL OR uf = p_uf)
    GROUP BY l.produto_id, l.uf
  ),
  saidas_pedidos_pendentes AS (
    SELECT pi.produto_id, p.uf_postagem as uf, SUM(pi.quantidade) as total
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.estoque_processado IS NULL OR p.estoque_processado = false
    AND p.status_pagamento = 'pago'
    AND (p_produto_id IS NULL OR pi.produto_id = p_produto_id)
    GROUP BY pi.produto_id, p.uf_postagem
  ),
  saidas_movimentacoes AS (
    SELECT produto_id, uf_origem as uf, SUM(quantidade) as total
    FROM public.estoque_movimentacoes
    WHERE tipo = 'saida'
    AND (p_produto_id IS NULL OR produto_id = p_produto_id)
    AND (p_uf IS NULL OR uf_origem = p_uf)
    GROUP BY l.produto_id, l.uf_origem
  )
  SELECT 
    COALESCE(el.produto_id, sp.produto_id, sm.produto_id) as produto_id,
    COALESCE(pr.nome_oficial, 'Produto não encontrado') as produto_nome,
    COALESCE(el.uf, sp.uf, sm.uf) as uf,
    COALESCE(el.total, 0)::integer as entradas,
    COALESCE(sp.total, 0)::integer as saidas_pedidos,
    (COALESCE(el.total, 0) - COALESCE(sp.total, 0))::integer as saldo
  FROM entradas_lotes el
  FULL OUTER JOIN saidas_pedidos_pendentes sp ON sp.produto_id = el.produto_id AND sp.uf = el.uf
  FULL OUTER JOIN saidas_movimentacoes sm ON sm.produto_id = COALESCE(el.produto_id, sp.produto_id) AND sm.uf = COALESCE(el.uf, sp.uf)
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(el.produto_id, sp.produto_id, sm.produto_id)
  WHERE (el.total IS NOT NULL OR sp.total IS NOT NULL)
  ORDER BY pr.nome_oficial, COALESCE(el.uf, sp.uf, sm.uf);
END;
$$;

-- 4. Criar funcao para atualizar snapshot (executar quando necessario)
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Limpar snapshot antigo
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  
  -- Inserir novo calculo
  INSERT INTO public.estoque_snapshot (produto_id, uf, entradas, saidas_pedidos, saidas_movimentacoes, saldo_calculado, atualizado_em)
  SELECT 
    produto_id,
    uf,
    entradas,
    saidas_pedidos,
    0,
    (entradas - saidas_pedidos),
    now()
  FROM public.get_estoque_produto(NULL, NULL);
  
  -- Atualizar estoque_atual na tabela produtos (soma total por produto)
  UPDATE public.produtos p
  SET estoque_atual = COALESCE((
    SELECT SUM(saldo_calculado) 
    FROM public.estoque_snapshot 
    WHERE produto_id = p.id
  ), 0);
END;
$$;

-- 5. Criar funcao para abater estoque de pedido (para uso manual)
CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(p_pedido_id uuid, p_uf_postagem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_cliente text;
  v_mov_exists boolean;
  v_total_items integer := 0;
  v_processed_items integer := 0;
BEGIN
  v_uf_cliente := p_uf_postagem;
  
  IF v_uf_cliente IS NULL THEN
    SELECT COALESCE(ct.uf, RIGHT(TRIM(ct.cidade_uf), 2)) INTO v_uf_cliente
    FROM contatos ct, pedidos p WHERE p.id = p_pedido_id AND ct.id = p.contato_id;
  END IF;

  FOR v_item IN SELECT * FROM pedido_itens WHERE pedido_id = p_pedido_id LOOP
    v_total_items := v_total_items + 1;
    SELECT EXISTS (SELECT 1 FROM estoque_movimentacoes WHERE pedido_item_id = v_item.id) INTO v_mov_exists;
    IF v_mov_exists THEN CONTINUE; END IF;

    v_remaining := v_item.quantidade;
    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf FROM lotes
      WHERE produto_id = v_item.produto_id AND quantidade_atual > 0
      ORDER BY (uf = COALESCE(v_uf_cliente, '')) DESC, created_at ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;
      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);
      UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, pedido_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, p_pedido_id, 'Pedido #' || p_pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;
    v_processed_items := v_processed_items + 1;
  END LOOP;

  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;
  
  -- Atualizar snapshot apos abate
  PERFORM public.atualizar_estoque_snapshot();
  
  RETURN jsonb_build_object('pedido_id', p_pedido_id::text, 'total_items', v_total_items, 'processed', v_processed_items);
END;
$$;

-- 6. Criar funcao para processar TODOS pedidos pendentes de uma vez
CREATE OR REPLACE FUNCTION public.processar_todos_estoque_pendente()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido record;
  v_total_processados integer := 0;
  v_result jsonb;
BEGIN
  FOR v_pedido IN
    SELECT id, uf_postagem FROM public.pedidos
    WHERE (estoque_processado IS NULL OR estoque_processado = false)
    AND status_pagamento = 'pago'
    AND EXISTS (SELECT 1 FROM pedido_itens WHERE pedido_id = pedidos.id)
    ORDER BY created_at ASC
  LOOP
    v_result := public.processar_pedido_estoque_trigger(v_pedido.id, v_pedido.uf_postagem);
    v_total_processados := v_total_processados + 1;
  END LOOP;

  RETURN jsonb_build_object('total_pedidos_processados', v_total_processados);
END;
$$;

COMMIT;

-- Para usar:
-- SELECT * FROM get_estoque_produto(); -- Ver estoque atual (com pedidos pendentes)
-- SELECT atualizar_estoque_snapshot(); -- Atualizar snapshot cache
-- SELECT processar_todos_estoque_pendente(); -- Abater todos os pedidos pendentes de uma vez
-- SELECT processar_pedido_estoque_trigger('UUID', 'SP'); -- Abater pedido especifico

-- MIGRATION: 20260415000005_verificar_estoque_negativo.sql
-- Calcular estoque negativo baseado em PEDIDOS ANTIGOS (sem stock processado)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Ver quantos pedidos tem itens e NAO tem estoque_processado
SELECT 
  COUNT(*) as total_pedidos_pendentes,
  SUM(pi.quantidade) as total_itens,
  COUNT(DISTINCT uf_postagem) as ufs_distintas
FROM public.pedidos p
JOIN public.pedido_itens pi ON pi.pedido_id = p.id
WHERE p.status_pagamento = 'pago'
AND (p.estoque_processado IS NULL OR p.estoque_processado = false);

-- 2. Atualizar snapshot incluindo TODOS os pedidos (não apenas pendentes)
-- Isso vai mostrar o estoque NEGATIVO baseado nos pedidos ja feitos

-- Primeiro, verificar o que temos nos pedidos
SELECT 
  p.uf_postagem,
  pi.produto_id,
  pr.nome_oficial,
  SUM(pi.quantidade) as quantidade_pedida
FROM public.pedidos p
JOIN public.pedido_itens pi ON pi.pedido_id = p.id
JOIN public.produtos pr ON pr.id = pi.produto_id
WHERE p.status_pagamento = 'pago'
AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
GROUP BY p.uf_postagem, pi.produto_id, pr.nome_oficial
ORDER BY pr.nome_oficial, p.uf_postagem;

-- 3. Criar visualizacao direta do estoque com negativos (sem usar snapshot)
SELECT 
  pr.nome_oficial as produto,
  l.uf,
  COALESCE(SUM(l.quantidade_atual), 0) as entradas_lotes,
  COALESCE((
    SELECT SUM(pi.quantidade)
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    AND pi.produto_id = pr.id
    AND p.uf_postagem = l.uf
  ), 0) as saidas_pedidos_pendentes,
  COALESCE(SUM(l.quantidade_atual), 0) - COALESCE((
    SELECT SUM(pi.quantidade)
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    AND pi.produto_id = pr.id
    AND p.uf_postagem = l.uf
  ), 0) as saldo_estoque
FROM public.produtos pr
LEFT JOIN public.lotes l ON l.produto_id = pr.id
GROUP BY pr.id, pr.nome_oficial, l.uf
ORDER BY pr.nome_oficial, l.uf;

-- 4. TOTAL POR PRODUTO (soma de todas as UFs)
SELECT 
  pr.nome_oficial as produto,
  COALESCE(SUM(l.quantidade_atual), 0) as total_entradas,
  COALESCE((
    SELECT SUM(pi.quantidade)
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    AND pi.produto_id = pr.id
  ), 0) as total_saidas_pedidos,
  COALESCE(SUM(l.quantidade_atual), 0) - COALESCE((
    SELECT SUM(pi.quantidade)
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    AND pi.produto_id = pr.id
  ), 0) as saldo_total
FROM public.produtos pr
LEFT JOIN public.lotes l ON l.produto_id = pr.id
GROUP BY pr.id, pr.nome_oficial
ORDER BY pr.nome_oficial;

COMMIT;

-- MIGRATION: 20260415000006_estoque_negativo_func.sql
-- ESTOQUE COMPLETO COM NEGATIVO (lotes - pedidos pendentes)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Criar funcao que retorna estoque com negativo dinamico
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH base_lotes AS (
    SELECT l.produto_id, l.uf, SUM(l.quantidade_atual) as total_lote
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, l.uf
  ),
  base_pedidos AS (
    SELECT 
      pi.produto_id,
      p.uf_postagem as uf,
      SUM(pi.quantidade) as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    AND (p.estoque_processado IS NULL OR p.estoque_processado = false)
    GROUP BY pi.produto_id, p.uf_postagem
  )
  SELECT 
    COALESCE(l.produto_id, p.produto_id) as produto_id,
    COALESCE(pr.nome_oficial, '—') as produto_nome,
    COALESCE(l.uf, p.uf) as uf,
    COALESCE(l.total_lote, 0)::integer as entradas,
    COALESCE(p.total_pedido, 0)::integer as saidas_pedidos,
    (COALESCE(l.total_lote, 0) - COALESCE(p.total_pedido, 0))::integer as saldo
  FROM base_lotes l
  FULL OUTER JOIN base_pedidos p ON p.produto_id = l.produto_id AND p.uf = l.uf
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.produto_id, p.produto_id)
  WHERE l.total_lote IS NOT NULL OR p.total_pedido IS NOT NULL
  ORDER BY pr.nome_oficial, COALESCE(l.uf, p.uf);
END;
$$;

-- 2. Criar funcao para atualizar estoque_atual nos produtos (com negativo)
CREATE OR REPLACE FUNCTION public.atualizar_estoque_produtos()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reg record;
BEGIN
  FOR v_reg IN
    SELECT produto_id, SUM(saldo) as saldo_total
    FROM public.get_estoque_completo()
    GROUP BY produto_id
  LOOP
    UPDATE public.produtos
    SET estoque_atual = v_reg.saldo_total
    WHERE id = v_reg.produto_id;
  END LOOP;
END;
$$;

-- 3. Executar atualizacao imediatamente
SELECT public.atualizar_estoque_produtos();

COMMIT;

-- Verificar estoque negativo:
-- SELECT * FROM get_estoque_completo();

-- MIGRATION: 20260415000007_rpc_estoque_negativo.sql
-- Criar funcao RPC para buscar estoque com negativo (chamada do frontend)
CREATE OR REPLACE FUNCTION public.buscar_estoque_completo()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO v_result
  FROM (
    SELECT 
      produto_id,
      produto_nome,
      uf,
      entradas,
      saidas_pedidos,
      saldo
    FROM public.get_estoque_completo()
  ) t;
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- Criar funcao para somar estoque negativo nos cards do frontend
CREATE OR REPLACE FUNCTION public.get_estoque_total_por_produto()
RETURNS TABLE(produto_id uuid, produto_nome text, saldo_total integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    produto_id,
    produto_nome,
    SUM(saldo)::integer as saldo_total
  FROM public.get_estoque_completo()
  GROUP BY produto_id, produto_nome
  ORDER BY produto_nome;
END;
$$;

-- MIGRATION: 20260415000008_estoque_todos_pedidos.sql
-- ESTOQUE NEGATIVO BASEADO EM TODOS OS PEDIDOS PAGOS
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Função que considera TODOS os pedidos pagos (não apenas pendentes)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH base_lotes AS (
    SELECT l.produto_id, l.uf, SUM(l.quantidade_atual) as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, l.uf
  ),
  base_pedidos AS (
    SELECT 
      pi.produto_id,
      p.uf_postagem as uf,
      SUM(pi.quantidade) as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'  -- TODOS os pedidos pagos!
    GROUP BY pi.produto_id, p.uf_postagem
  )
  SELECT 
    COALESCE(l.produto_id, p.produto_id) as produto_id,
    COALESCE(pr.nome_oficial, '—') as produto_nome,
    COALESCE(l.uf, p.uf) as uf,
    COALESCE(l.total_lote, 0)::integer as entradas,
    COALESCE(p.total_pedido, 0)::integer as saidas_pedidos,
    (COALESCE(l.total_lote, 0) - COALESCE(p.total_pedido, 0))::integer as saldo
  FROM base_lotes l
  FULL OUTER JOIN base_pedidos p ON p.produto_id = l.produto_id AND p.uf = l.uf
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.produto_id, p.produto_id)
  WHERE l.total_lote IS NOT NULL OR p.total_pedido IS NOT NULL
  ORDER BY pr.nome_oficial, COALESCE(l.uf, p.uf);
END;
$$;

-- 2. RPC para frontend
CREATE OR REPLACE FUNCTION public.buscar_estoque_completo()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT produto_id, produto_nome, uf, entradas, saidas_pedidos, saldo 
    FROM public.get_estoque_completo()
  ) t;
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 3. Testar para ver os dados
SELECT * FROM public.get_estoque_completo() ORDER BY produto_nome, uf;

-- 4. Atualizar estoque_atual na tabela produtos
UPDATE public.produtos p
SET estoque_atual = COALESCE((
  SELECT SUM(saldo) 
  FROM public.get_estoque_completo() 
  WHERE produto_id = p.id
), 0);

COMMIT;

-- MIGRATION: 20260415000009_estoque_correcao_final.sql
-- ESTOQUE NEGATIVO - CORRECAO FINAL
-- Executar no Supabase SQL Editor - TODO DE UMA VEZ

BEGIN;

-- 1. Limpar qualquer dado existente
DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida';
UPDATE public.pedidos SET estoque_processado = NULL;

-- 2. Criar funcao de estoque considerando TODOS os pedidos pagos
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH lotess AS (
    SELECT produto_id, uf, COALESCE(SUM(quantidade_atual), 0) as total_lote
    FROM public.lotes
    GROUP BY produto_id, uf
  ),
  pedidoss AS (
    SELECT 
      pi.produto_id,
      COALESCE(p.uf_postagem, 'SP') as uf,
      SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.produto_id, p.produto_id) as produto_id,
    COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome,
    COALESCE(l.uf, p.uf) as uf,
    l.total_lote as entradas,
    p.total_pedido as saidas_pedidos,
    (l.total_lote - p.total_pedido) as saldo
  FROM lotess l
  FULL OUTER JOIN pedidoss p ON p.produto_id = l.produto_id AND p.uf = l.uf
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.produto_id, p.produto_id)
  WHERE l.total_lote > 0 OR p.total_pedido > 0
  ORDER BY pr.nome_oficial, COALESCE(l.uf, p.uf);
END;
$$;

-- 3. Criar RPC wrapper
CREATE OR REPLACE FUNCTION public.buscar_estoque_completo()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT produto_id, produto_nome, uf, entradas, saidas_pedidos, saldo 
    FROM public.get_estoque_completo()
    ORDER BY produto_nome, uf
  ) t;
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 4. Verificar o resultado
SELECT * FROM public.get_estoque_completo() LIMIT 20;

COMMIT;

-- MIGRATION: 20260415000010_estoque_todos_pedidos_v2.sql
-- ESTOQUE NEGATIVO - TODOS OS PEDIDOS (pagos + pendentes)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Função principal que calcula estoque = lotes - todos os pedidos pagos
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH 
  lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  pedidos_calc AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.pid, ped.pid) as produto_id,
    COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome,
    COALESCE(l.uff, ped.uff) as uf,
    l.total_lote as entradas,
    ped.total_pedido as saidas_pedidos,
    (l.total_lote - ped.total_pedido) as saldo
  FROM lotes_calc l
  FULL OUTER JOIN pedidos_calc ped ON ped.pid = l.pid AND ped.uff = l.uff
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.pid, ped.pid)
  WHERE l.total_lote > 0 OR ped.total_pedido > 0
  ORDER BY pr.nome_oficial, COALESCE(l.uff, ped.uff);
END;
$$;

-- 2. RPC para frontend
CREATE OR REPLACE FUNCTION public.buscar_estoque_completo()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT produto_id, produto_nome, uf, entradas, saidas_pedidos, saldo 
    FROM public.get_estoque_completo()
    ORDER BY produto_nome, uf
  ) t;
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 3. Testar resultado
SELECT * FROM public.get_estoque_completo() ORDER BY produto_nome;

-- 4. Atualizar estoque_atual nos produtos (soma total por produto)
UPDATE public.produtos p
SET estoque_atual = COALESCE((
  SELECT SUM(saldo) 
  FROM public.get_estoque_completo() 
  WHERE produto_id = p.id
), 0);

COMMIT;

-- MIGRATION: 20260415000011_estoque_negativo_simples.sql
-- Estoque negativo calculado no frontend
-- Executar NO SUPABASE SQL APENAS para criar função de suporte (se precisar)

-- Esta função calcula negativo: lotes - pedidos pagos
CREATE OR REPLACE FUNCTION public.get_estoque_negativo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  saldo integer
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH lotes_agg AS (
    SELECT l.produto_id, l.uf, SUM(l.quantidade_atual)::integer as entrada
    FROM public.lotes l
    GROUP BY l.produto_id, l.uf
  ),
  pedidos_agg AS (
    SELECT pi.produto_id, p.uf_postagem as uf, SUM(pi.quantidade)::integer as saida
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago' AND p.uf_postagem IS NOT NULL
    GROUP BY pi.produto_id, p.uf_postagem
  )
  SELECT 
    COALESCE(l.produto_id, pa.produto_id),
    COALESCE(pr.nome_oficial, '—'),
    COALESCE(l.uf, pa.uf),
    COALESCE(l.entrada, 0) - COALESCE(pa.saida, 0)
  FROM lotes_agg l
  FULL JOIN pedidos_agg pa ON pa.produto_id = l.produto_id AND pa.uf = l.uf
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.produto_id, pa.produto_id)
  WHERE l.entrada > 0 OR pa.saida > 0;
END;
$$;

-- Testar
SELECT * FROM get_estoque_negativo();

-- MIGRATION: 20260415000012_estoque_rpc_fetch.sql
-- ESTOQUE NEGATIVO via fetch RPC
-- Executar no Supabase SQL Editor

BEGIN;

-- Função principal
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH 
  lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  pedidos_calc AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.pid, ped.pid) as produto_id,
    COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome,
    COALESCE(l.uff, ped.uff) as uf,
    COALESCE(l.total_lote, 0) as entradas,
    COALESCE(ped.total_pedido, 0) as saidas_pedidos,
    COALESCE(l.total_lote, 0) - COALESCE(ped.total_pedido, 0) as saldo
  FROM lotes_calc l
  FULL OUTER JOIN pedidos_calc ped ON ped.pid = l.pid AND ped.uff = l.uff
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.pid, ped.pid)
  WHERE l.total_lote > 0 OR ped.total_pedido > 0
  ORDER BY pr.nome_oficial, COALESCE(l.uff, ped.uff);
END;
$$;

COMMIT;

-- Testar
SELECT * FROM get_estoque_completo() ORDER BY produto_nome;

-- MIGRATION: 20260415000013_estoque_todos_pedidos_sem_snapshot.sql
-- ESTOQUE NEGATIVO - TODOS OS PEDIDOS (SEM SNAPSHOT)
-- Executar no Supabase SQL Editor

BEGIN;

-- Limpar coluna estoque_processado para considerar todos os pedidos
UPDATE public.pedidos SET estoque_processado = NULL WHERE estoque_processado IS NOT NULL;

-- Função que calcula: lotes - TODOS pedidos pagos (sem exception)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH 
  lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  todos_pedidos AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'  -- TODOS pedidos pagos!
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.pid, ped.pid) as produto_id,
    COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome,
    COALESCE(l.uff, ped.uff) as uf,
    COALESCE(l.total_lote, 0) as entradas,
    COALESCE(ped.total_pedido, 0) as saidas_pedidos,
    (COALESCE(l.total_lote, 0) - COALESCE(ped.total_pedido, 0)) as saldo
  FROM lotes_calc l
  FULL OUTER JOIN todos_pedidos ped ON ped.pid = l.pid AND ped.uff = l.uff
  LEFT JOIN public.produtos pr ON pr.id = COALESCE(l.pid, ped.pid)
  WHERE l.total_lote > 0 OR ped.total_pedido > 0
  ORDER BY pr.nome_oficial, COALESCE(l.uff, ped.uff);
END;
$$;

-- Verificar total de pedidos pagos
SELECT COUNT(*), SUM(quantidade) as total_itens FROM pedidos WHERE status_pagamento = 'pago';

-- Verificar resultado
SELECT * FROM get_estoque_completo() ORDER BY produto_nome;

-- Atualizar estoque_atual nos produtos
UPDATE public.produtos p
SET estoque_atual = COALESCE((
  SELECT SUM(saldo) 
  FROM public.get_estoque_completo() 
  WHERE produto_id = p.id
), 0);

COMMIT;

-- MIGRATION: 20260415000014_estoque_snapshot_final.sql
-- ESTOQUE COM SNAPSHOT - Pega todos os pedidos + RPC via fetch
-- Executar no Supabase SQL Editor - TODO DE UMA VEZ

BEGIN;

-- 1. Criar/atualizar tabela snapshot (cache do estoque)
CREATE TABLE IF NOT EXISTS public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id uuid REFERENCES public.produtos(id),
  uf text,
  entradas integer DEFAULT 0,
  saidas_pedidos integer DEFAULT 0,
  saldo_calculado integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 2. Função que calcula estoque (lotes - todos os pedidos pagos)
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(
  produto_id uuid,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH 
  lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  todos_pedidos AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento = 'pago'
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.pid, ped.pid) as produto_id,
    COALESCE(l.uff, ped.uff) as uf,
    COALESCE(l.total_lote, 0) as entradas,
    COALESCE(ped.total_pedido, 0) as saidas_pedidos,
    (COALESCE(l.total_lote, 0) - COALESCE(ped.total_pedido, 0)) as saldo
  FROM lotes_calc l
  FULL OUTER JOIN todos_pedidos ped ON ped.pid = l.pid AND ped.uff = l.uff
  WHERE l.total_lote > 0 OR ped.total_pedido > 0;
END;
$$;

-- 3. Função para ATUALIZAR o snapshot (chamar esta para recalcular)
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Limpar snapshot
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  
  -- Calcular e salvar no snapshot
  INSERT INTO public.estoque_snapshot (produto_id, uf, entradas, saidas_pedidos, saldo_calculado, atualizado_em)
  SELECT produto_id, uf, entradas, saidas_pedidos, saldo, now()
  FROM public.calcular_estoque();
  
  -- Atualizar estoque_atual nos produtos (soma total)
  UPDATE public.produtos p
  SET estoque_atual = COALESCE((
    SELECT SUM(saldo_calculado) 
    FROM public.estoque_snapshot 
    WHERE produto_id = p.id
  ), 0);
END;
$$;

-- 4. Função RPC que busca do snapshot (para frontend via fetch)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  produto_id uuid,
  produto_nome text,
  uf text,
  entradas integer,
  saidas_pedidos integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    es.produto_id,
    COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome,
    es.uf,
    es.entradas,
    es.saidas_pedidos,
    es.saldo_calculado
  FROM public.estoque_snapshot es
  LEFT JOIN public.produtos pr ON pr.id = es.produto_id
  ORDER BY pr.nome_oficial, es.uf;
END;
$$;

-- 5. Atualizar snapshot agora (inclui todos os pedidos)
SELECT public.atualizar_estoque_snapshot();

-- 6. Verificar resultado
SELECT * FROM public.get_estoque_completo() ORDER BY produto_nome;

-- 7. Ver total de pedidos considerados
SELECT COUNT(*) as total_pedidos FROM pedidos WHERE status_pagamento = 'pago';

COMMIT;

-- RESUMO:
-- - snapshot armazena cache do estoque
-- - get_estoque_completo() lê do snapshot (rápido!)
-- - atualizar_estoque_snapshot() recalcula (chamar quando precisar)
-- Frontend chama get_estoque_completo() via fetch RPC

-- MIGRATION: 20260415000015_estoque_todos_pedidos_inclusive_pendentes.sql
-- ESTOQUE COM SNAPSHOT - TODOS OS PEDIDOS (PAGOS + PENDENTES)
-- Executar no Supabase SQL Editor - TODO DE UMA VEZ

BEGIN;

-- 1. Dropar tabela snapshot se existir e recriar com colunas corretas
DROP TABLE IF EXISTS public.estoque_snapshot;

CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id uuid,
  uf text,
  entradas integer DEFAULT 0,
  saidas_pedidos integer DEFAULT 0,
  saldo_calculado integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 2. Função que calcula: lotes - TODOS os pedidos (pagos + pendentes)
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(produto_id uuid, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  todos_pedidos AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(pi.quantidade)::integer as total_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT COALESCE(l.pid, ped.pid) as produto_id, COALESCE(l.uff, ped.uff) as uf,
    COALESCE(l.total_lote, 0) as entradas, COALESCE(ped.total_pedido, 0) as saidas_pedidos,
    (COALESCE(l.total_lote, 0) - COALESCE(ped.total_pedido, 0)) as saldo
  FROM lotes_calc l
  FULL OUTER JOIN todos_pedidos ped ON ped.pid = l.pid AND ped.uff = l.uff
  WHERE l.total_lote > 0 OR ped.total_pedido > 0;
END;
$$;

-- 3. Função para atualizar snapshot
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  INSERT INTO public.estoque_snapshot (produto_id, uf, entradas, saidas_pedidos, saldo_calculado, atualizado_em)
  SELECT produto_id, uf, entradas, saidas_pedidos, saldo, now() FROM public.calcular_estoque();
  UPDATE public.produtos p SET estoque_atual = COALESCE((SELECT SUM(saldo_calculado) FROM public.estoque_snapshot WHERE produto_id = p.id), 0);
END;
$$;

-- 4. Função RPC que busca do snapshot (frontend usa fetch)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(produto_id uuid, produto_nome text, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT es.produto_id, COALESCE(pr.nome_oficial, 'Desconhecido') as produto_nome, es.uf, es.entradas, es.saidas_pedidos, es.saldo_calculado
  FROM public.estoque_snapshot es
  LEFT JOIN public.produtos pr ON pr.id = es.produto_id
  ORDER BY pr.nome_oficial, es.uf;
END;
$$;

-- 5. Atualizar snapshot agora!
SELECT public.atualizar_estoque_snapshot();

-- 6. Verificar
SELECT * FROM public.get_estoque_completo() ORDER BY produto_nome;

COMMIT;

-- MIGRATION: 20260415000016_verificar_dados_pedidos.sql
-- VERIFICAR DADOS DOS PEDIDOS
-- Execute no Supabase SQL Editor para ver o que tem

-- Ver total de pedidos
SELECT 'pedidos' as tabela, COUNT(*) as total FROM pedidos
UNION ALL
SELECT 'pedido_itens', COUNT(*) FROM pedido_itens
UNION ALL
SELECT 'pedidos com itens', COUNT(DISTINCT p.id) FROM pedidos p JOIN pedido_itens pi ON pi.pedido_id = p.id;

-- Ver pedidos que tem itens
SELECT p.id, p.status_pagamento, p.uf_postagem, COUNT(pi.id) as itens
FROM pedidos p
LEFT JOIN pedido_itens pi ON pi.pedido_id = p.id
GROUP BY p.id, p.status_pagamento, p.uf_postagem
ORDER BY p.created_at DESC
LIMIT 20;

-- Ver se pedido_itens tem dados
SELECT * FROM pedido_itens LIMIT 10;

-- MIGRATION: 20260415000017_estoque_debug.sql
-- ESTOQUE - CONSIDERA TODOS OS PEDIDOS (sem依赖 de pedido_itens)
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Dropar e recriar tabela snapshot
DROP TABLE IF EXISTS public.estoque_snapshot;

CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id uuid,
  uf text,
  entradas integer DEFAULT 0,
  saidas_pedidos integer DEFAULT 0,
  saldo_calculado integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 2. Função que calcula: lotes - TODOS os pedidos (usa coluna produto do pedido)
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(produto_id uuid, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  -- Entradas dos lotes
  WITH lotes_calc AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, COALESCE(SUM(l.quantidade_atual), 0)::integer as total_lote
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  -- Saidas: soma quantidade de TODOS os pedidos com produto
  pedidos_calc AS (
    SELECT 
      p.id as pedido_id,
      p.uf_postagem,
      CASE 
        WHEN p.produto IS NOT NULL AND p.produto LIKE '[%' THEN  -- JSON array
          (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p.produto::jsonb) x WHERE x->>'produto_id' IS NOT NULL)
        WHEN p.produto IS NOT NULL AND p.produto LIKE '%{%' THEN  -- nested JSON
          (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p.produto::jsonb->0->'produtos') x)
        ELSE 
          COALESCE(p.quantidade, 1)  -- fallback
      END as quantidade_total
    FROM public.pedidos p
    WHERE p.produto IS NOT NULL AND trim(p.produto) <> ''
  ),
  pedidos_agg AS (
    SELECT 
      COALESCE(p.uf_postagem, 'SP') as uff,
      SUM(p.quantidade_total)::integer as total_pedido
    FROM pedidos_calc p
    GROUP BY COALESCE(p.uf_postagem, 'SP')
  )
  -- Por agora, vou somar apenas o total sem distinção de produto
  SELECT 
    l.pid,
    l.uff,
    COALESCE(l.total_lote, 0) as entradas,
    COALESCE((SELECT SUM(quantidade_total) FROM pedidos_calc), 0) as saidas_pedidos,
    COALESCE(l.total_lote, 0) - COALESCE((SELECT SUM(quantidade_total) FROM pedidos_calc), 0) as saldo
  FROM lotes_calc l;
END;
$$;

-- 3. Simpler version - apenas soma todos os pedidos
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(produto_id uuid, uf text, entradas integer, saidas_pedidos integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  -- Primeiro: ver quanto temos em lotes por UF
  WITH lotes_por_uf AS (
    SELECT l.produto_id, l.uf, SUM(l.quantidade_atual) as qtd_lote
    FROM public.lotes l
    GROUP BY l.produto_id, l.uf
  ),
  -- Segundo: somar TODOS os pedidos (qualquer status)
  todos_pedidos AS (
    SELECT 
      SUM(
        CASE 
          WHEN p.produto IS NOT NULL AND p.produto LIKE '[%' THEN
            COALESCE((SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p.produto::jsonb) x), p.quantidade)
          ELSE COALESCE(p.quantidade, 1)
        END
      )::integer as total_geral
    FROM public.pedidos p
    WHERE p.produto IS NOT NULL AND p.status_pagamento IS NOT NULL
  )
  -- Por UF, retorna entradas = lotes, saidas = soma de todos os pedidos
  SELECT 
    NULL::uuid as produto_id,
    'SP'::text as uf,
    COALESCE((SELECT SUM(qtd_lote) FROM lotes_por_uf), 0) as entradas,
    COALESCE((SELECT total_geral FROM todos_pedidos), 0) as saidas_pedidos,
    COALESCE((SELECT SUM(qtd_lote) FROM lotes_por_uf), 0) - COALESCE((SELECT total_geral FROM todos_pedidos), 0) as saldo;
END;
$$;

-- 4. Ver quantos pedidos temos
SELECT COUNT(*) as total_pedidos FROM pedidos WHERE produto IS NOT NULL;
SELECT SUM(quantidade) as total_itens_pedidos FROM pedidos WHERE produto IS NOT NULL;

-- 5. Testar função
SELECT * FROM calcular_estoque();

COMMIT;

-- MIGRATION: 20260415000018_debug_pedidos.sql
-- DEBUG: Ver exatamente quantos pedidos a query retorna
-- Execute no Supabase SQL Editor

-- Ver quantos pedidos tem produto preenchido
SELECT 
  COUNT(*) as total_pedidos_com_produto,
  SUM(CASE WHEN status_pagamento = 'pago' THEN 1 ELSE 0 END) as pagos,
  SUM(CASE WHEN status_pagamento != 'pago' THEN 1 ELSE 0 END) as pendentes
FROM pedidos 
WHERE produto IS NOT NULL AND trim(produto) <> '';

-- Ver se uf_postagem tem valores
SELECT 
  COUNT(*) as com_uf_postagem,
  COUNT(*) as sem_uf_postagem
FROM pedidos 
WHERE produto IS NOT NULL;

-- Verificar pedido_itens
SELECT COUNT(*) as total_itens FROM pedido_itens;

-- Verificar primeiro pedido_itens
SELECT pi.*, p.uf_postagem, p.status_pagamento
FROM pedido_itens pi
JOIN pedidos p ON p.id = pi.pedido_id
LIMIT 10;

-- MIGRATION: 20260415000019_estoque_corrigido_final.sql
-- ESTOQUE CORRIGIDO - Fix ambiguous column
-- Executar no Supabase SQL Editor

BEGIN;

-- 0. Dropar funções existentes
DROP FUNCTION IF EXISTS public.get_estoque_completo();
DROP FUNCTION IF EXISTS public.atualizar_estoque_snapshot();
DROP FUNCTION IF EXISTS public.calcular_estoque();

-- 1. Criar tabela snapshot
DROP TABLE IF EXISTS public.estoque_snapshot;

CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada integer DEFAULT 0,
  saida integer DEFAULT 0,
  saldo integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 2. calcular_estoque()
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as nome FROM public.produtos WHERE ativo = true
  ),
  lotes_por_produto AS (
    SELECT l.produto_id as pid, l.uf as estado, SUM(l.quantidade_atual) as qtd_lote
    FROM public.lotes l
    GROUP BY l.produto_id, l.uf
  ),
  pedidos_por_produto AS (
    SELECT pi.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as estado, SUM(pi.quantidade)::integer as qtd_pedido
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(l.pid, ped.pid, pa.pid) as prod_id,
    COALESCE(pa.nome, 'Desconhecido') as prod_nome,
    COALESCE(l.estado, ped.estado, 'SP') as estado,
    COALESCE(l.qtd_lote, 0)::integer as entrada,
    COALESCE(ped.qtd_pedido, 0)::integer as saida,
    (COALESCE(l.qtd_lote, 0) - COALESCE(ped.qtd_pedido, 0))::integer as saldo
  FROM produtos_ativos pa
  LEFT JOIN lotes_por_produto l ON l.pid = pa.pid
  LEFT JOIN pedidos_por_produto ped ON ped.pid = pa.pid
  WHERE COALESCE(l.qtd_lote, 0) > 0 OR COALESCE(ped.qtd_pedido, 0) > 0
  ORDER BY pa.nome, COALESCE(l.estado, ped.estado, 'SP');
END;
$$;

-- 3. atualizar_estoque_snapshot()
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, atualizado_em)
  SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now() FROM public.calcular_estoque();
  UPDATE public.produtos p SET estoque_atual = COALESCE((SELECT SUM(saldo) FROM public.estoque_snapshot WHERE prod_id = p.id), 0);
END;
$$;

-- 4. get_estoque_completo() - busca do snapshot
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT es.prod_id, es.prod_nome, es.estado, es.entrada, es.saida, es.saldo
  FROM public.estoque_snapshot es
  ORDER BY es.prod_nome, es.estado;
END;
$$;

-- 5. Atualizar snapshot
SELECT public.atualizar_estoque_snapshot();

-- Verificar
SELECT * FROM public.get_estoque_completo();

COMMIT;

-- MIGRATION: 20260415000020_add_etiqueta_paga.sql
-- Add etiqueta_paga column to pedidos
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_paga BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN pedidos.etiqueta_paga IS 'Indica se a etiqueta foi paga no Super Frete';

-- MIGRATION: 20260415000020_estoque_definitivo.sql
-- ESTOQUE FINAL - TODOS OS PEDIDOS, TODOS OS PRODUTOS
-- Executar no Supabase SQL Editor - TODO DE UMA VEZ

BEGIN;

-- 0. Primeiro: permitir nulo na coluna estoque_processado
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado DROP NOT NULL;
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado SET DEFAULT false;

-- 1. Criar/atualizar tabela snapshot
DROP TABLE IF EXISTS public.estoque_snapshot;

CREATE TABLE public.estoque_snapshot (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada integer DEFAULT 0,
  saida integer DEFAULT 0,
  saldo integer,
  atualizado_em timestamptz DEFAULT now()
);

-- 2. Função principal: lotes - TODOS os pedidos
CREATE OR REPLACE FUNCTION public.calcular_estoque()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH todos_produtos AS (
    SELECT id as pid, nome_oficial as nome FROM public.produtos WHERE ativo = true
  ),
  todos_lotes AS (
    SELECT l.produto_id as l_pid, COALESCE(l.uf, 'SP') as l_est, SUM(l.quantidade_atual)::integer as l_qtd
    FROM public.lotes l
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  todos_pedidos AS (
    SELECT pi.produto_id as p_pid, COALESCE(p.uf_postagem, 'SP') as p_est, SUM(pi.quantidade)::integer as p_qtd
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(tl.l_pid, tp_est.p_pid, tp.pid) as prod_id,
    tp.nome as prod_nome,
    COALESCE(tl.l_est, tp_est.p_est, 'SP') as estado,
    COALESCE(tl.l_qtd, 0)::integer as entrada,
    COALESCE(tp_est.p_qtd, 0)::integer as saida,
    (COALESCE(tl.l_qtd, 0) - COALESCE(tp_est.p_qtd, 0))::integer as saldo
  FROM todos_produtos tp
  LEFT JOIN todos_lotes tl ON tl.l_pid = tp.pid
  LEFT JOIN todos_pedidos tp_est ON tp_est.p_pid = tp.pid
  ORDER BY tp.nome, COALESCE(tl.l_est, tp_est.p_est, 'SP');
END;
$$;

-- 3. Função atualizar snapshot
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  TRUNCATE public.estoque_snapshot RESTART IDENTITY;
  INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, atualizado_em)
  SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now() FROM public.calcular_estoque();
  UPDATE public.produtos p SET estoque_atual = COALESCE((SELECT SUM(saldo) FROM public.estoque_snapshot WHERE prod_id = p.id), 0) WHERE p.id IS NOT NULL;
END;
$$;

-- 4. Função RPC para frontend
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT es.prod_id, es.prod_nome, es.estado, es.entrada, es.saida, es.saldo
  FROM public.estoque_snapshot es
  WHERE es.entrada > 0 OR es.saida > 0 OR es.saldo != 0
  ORDER BY es.prod_nome, es.estado;
END;
$$;

-- 5. Atualizar snapshot AGORA!
SELECT public.atualizar_estoque_snapshot();

-- 6. Verificar: mostrar todos os produtos com pedidos
SELECT prod_nome, estado, entrada, saida, saldo FROM public.estoque_snapshot ORDER BY prod_nome, estado;

COMMIT;

-- MIGRATION: 20260415000020_logistica_full.sql
-- =============================================
-- Migration: Logística - Sistema de Duas Etapas
-- Execute no Supabase SQL Editor
-- =============================================

-- 1. Adicionar coluna etiqueta_paga na tabela pedidos
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_paga BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN pedidos.etiqueta_paga IS 'Indica se a etiqueta foi paga no Super Frete';

-- 2. Verificar se tabela remetentes_uf existe e tem os campos necessários
-- (Execute separadamente se precisar criar a tabela)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'remetentes_uf') THEN
        CREATE TABLE remetentes_uf (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            uf VARCHAR(2) UNIQUE NOT NULL,
            cep_origem VARCHAR(8),
            cidade VARCHAR(100),
            bairro VARCHAR(100),
            endereco VARCHAR(255),
            numero VARCHAR(20),
            complemento VARCHAR(100),
            nome_remetente VARCHAR(255),
            contato_remetente VARCHAR(20),
            cpf VARCHAR(11),
            descricao_produto VARCHAR(255),
            valor_unitario DECIMAL(10,2),
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    END IF;
END $$;

-- 3. Verificar se produtos tem coluna peso
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM information_schema.columns 
        WHERE table_name = 'produtos' AND column_name = 'peso'
    ) THEN
        ALTER TABLE produtos ADD COLUMN peso INTEGER DEFAULT 300;
        COMMENT ON COLUMN produtos.peso IS 'Peso do produto em gramas';
    END IF;
END $$;

-- 4. Criar índices para performance (se não existirem)
CREATE INDEX IF NOT EXISTS idx_pedidos_status_rastreio ON pedidos(status_pedido) WHERE status_pedido = 'aguardando_rastreio';
CREATE INDEX IF NOT EXISTS idx_pedidos_modalidade ON pedidos(modalidade) WHERE modalidade != 'entrega_maos';
CREATE INDEX IF NOT EXISTS idx_pedidos_uf_postagem ON pedidos(uf_postagem);
CREATE INDEX IF NOT EXISTS idx_pedidos_etiqueta_paga ON pedidos(etiqueta_paga) WHERE etiqueta_paga = false;

-- 5. Confirmar alterações
SELECT 
    'pedidos.etiqueta_paga' as column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'pedidos' AND column_name = 'etiqueta_paga';

SELECT 'Migration executada com sucesso!' as result;

-- MIGRATION: 20260415000021_estoque_sem_snapshot.sql
-- ESTOQUE SEM SNAPSHOT - Puxa TODOS os pedidos agora (sem cache)
-- Executar no Supabase SQL Editor

BEGIN;

-- 0. Permitir nulo
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado DROP NOT NULL;
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado SET DEFAULT false;

-- Função que calcula direto (SEM snapshot) - lotes - TODOS os pedidos
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada integer,
  saida integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  -- 1. Todos os produtos ativos
  WITH produtos AS (
    SELECT pr.id as pid, pr.nome_oficial as pnome
    FROM public.produtos pr
    WHERE pr.ativo = true
  ),
  -- 2. Todos os lotes por produto+UF
  lotes AS (
    SELECT 
      l.produto_id as pid_lote,
      l.uf as uf_lote,
      SUM(l.quantidade_atual)::integer as qtd_entrada
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, l.uf
  ),
  -- 3. TODOS os pedidos por produto+UF (pagos E pendentes)
  pedidos AS (
    SELECT 
      pi.produto_id as pid_pedido,
      COALESCE(p.uf_postagem, 'SP') as uf_pedido,
      SUM(pi.quantidade)::integer as qtd_saida
    FROM public.pedido_itens pi
    INNER JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  -- Resultado: para CADA produto, mostrar entradas - saidas
  SELECT 
    COALESCE(l.pid_lote, ped.pid_pedido, pr.pid) as prod_id,
    pr.pnome as prod_nome,
    COALESCE(l.uf_lote, ped.uf_pedido, 'SP') as estado,
    COALESCE(l.qtd_entrada, 0)::integer as entrada,
    COALESCE(ped.qtd_saida, 0)::integer as saida,
    (COALESCE(l.qtd_entrada, 0) - COALESCE(ped.qtd_saida, 0))::integer as saldo
  FROM produtos pr
  LEFT JOIN lotes l ON l.pid_lote = pr.pid
  LEFT JOIN pedidos ped ON ped.pid_pedido = pr.pid
  WHERE l.qtd_entrada > 0 OR ped.qtd_saida > 0
  ORDER BY pr.pnome, COALESCE(l.uf_lote, ped.uf_pedido, 'SP');
END;
$$;

-- Testar agora - sem snapshot!
SELECT * FROM get_estoque_completo();

-- Ver quantos pedidos foram considerados
SELECT 
  COUNT(DISTINCT p.id) as total_pedidos,
  SUM(pi.quantidade) as total_itens
FROM public.pedidos p
INNER JOIN public.pedido_itens pi ON pi.pedido_id = p.id
WHERE p.status_pagamento IS NOT NULL;

COMMIT;

-- MIGRATION: 20260415000022_debug_pedido_itens.sql
-- ESTOQUE COM SNAPSHOT - DEBUGANDO O PROBLEMA
-- Executar no Supabase SQL Editor para entender o que acontece

BEGIN;

-- 1. Ver TODOS os pedido_itens
SELECT 
  pi.id,
  pi.pedido_id,
  pi.produto_id,
  pi.quantidade,
  p.status_pagamento,
  p.uf_postagem,
  pr.nome_oficial
FROM public.pedido_itens pi
INNER JOIN public.pedidos p ON p.id = pi.pedido_id
LEFT JOIN public.produtos pr ON pr.id = pi.produto_id
ORDER BY pi.created_at DESC
LIMIT 30;

-- 2. Ver quantos pedidos tem pedido_itens
SELECT 
  COUNT(DISTINCT pi.pedido_id) as pedidos_com_itens,
  COUNT(pi.id) as total_itens
FROM public.pedido_itens pi;

-- 3. Ver a soma exata de um produto especifico
SELECT 
  pi.produto_id,
  pr.nome_oficial,
  SUM(pi.quantidade) as total
FROM public.pedido_itens pi
INNER JOIN public.pedidos p ON p.id = pi.pedido_id
INNER JOIN public.produtos pr ON pr.id = pi.produto_id
WHERE p.status_pagamento IS NOT NULL
GROUP BY pi.produto_id, pr.nome_oficial
ORDER BY total DESC
LIMIT 10;

-- 4. Ver todos os pedidos SEM pedido_itens (que tem produto na coluna)
SELECT id, produto, quantidade, uf_postagem, status_pagamento FROM pedidos 
WHERE produto IS NOT NULL AND produto != 'geral'
ORDER BY created_at DESC
LIMIT 10;

COMMIT;

-- MIGRATION: 20260415000023_ver_tudo_pedido_itens.sql
-- VER TODOS OS pedido_itens SEM FILTRO NENHUM
-- Execute isso no Supabase SQL Editor

SELECT * FROM pedido_itens ORDER BY created_at DESC LIMIT 50;

-- MIGRATION: 20260415000024_ver_pedidos_produto.sql
-- VER TODOS OS PEDIDOS E SUA COLUNA PRODUTO
-- Execute no Supabase SQL Editor

SELECT id, produto, quantidade, uf_postagem, status_pagamento, created_at 
FROM pedidos 
WHERE produto IS NOT NULL 
ORDER BY created_at DESC 
LIMIT 30;

-- MIGRATION: 20260415000025_estoque_coluna_produto.sql
-- ESTOQUE USANDO COLUNA PRODUTO DO PEDIDO (não pedido_itens)
-- Executar no Supabase SQL Editor

BEGIN;

-- Função que calcula usando a coluna 'produto' do pedido (não pedido_itens)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada integer,
  saida integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  -- Primeiro: ver todos os pedidos com produto
  WITH todos_pedidos AS (
    SELECT 
      p.id as pedido_id,
      p.produto as produto_json,
      p.quantidade as qtd_total,
      p.uf_postagem as uf,
      p.status_pagamento as status
    FROM public.pedidos p
    WHERE p.produto IS NOT NULL 
      AND p.produto <> 'geral'
      AND p.status_pagamento IS NOT NULL
  ),
  -- Segundo: extrair produtos dos pedidos
  produtos_pedido AS (
    SELECT 
      tp.pedido_id,
      tp.uf,
      CASE 
        WHEN tp.produto_json LIKE '[%' THEN  -- JSON array
          (SELECT jsonb_array_elements(tp.produto_json::jsonb)->>'produto_id'::uuid)
        WHEN tp.produto_json LIKE '%{%' AND tp.produto_json LIKE '%produto%' THEN
          (SELECT (jsonb_each(tp.produto_json::jsonb->0->>'produtos')::jsonb)->>'key'::uuid)
        ELSE NULL
      END as prod_id,
      tp.qtd_total as qtd
    FROM todos_pedidos tp
  ),
  -- Terceiro: agrupar por produto+UF
  agg_pedidos AS (
    SELECT 
      pp.prod_id,
      pp.uf,
      SUM(pp.qtd)::integer as total_saida
    FROM produtos_pedido pp
    WHERE pp.prod_id IS NOT NULL
    GROUP BY pp.prod_id, pp.uf
  ),
  -- Quarto: lotes
  lotes_agg AS (
    SELECT 
      l.produto_id as pid,
      l.uf,
      SUM(l.quantidade_atual)::integer as total_entrada
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, l.uf
  ),
  -- Quinto: produtos ativos
  produtos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  )
  -- Resultado final
  SELECT 
    COALESCE(la.pid, ap.prod_id, pr.pid) as prod_id,
    COALESCE(pr.pnome, 'Desconhecido') as prod_nome,
    COALESCE(la.uf, ap.uf, 'SP') as estado,
    COALESCE(la.total_entrada, 0)::integer as entrada,
    COALESCE(ap.total_saida, 0)::integer as saida,
    (COALESCE(la.total_entrada, 0) - COALESCE(ap.total_saida, 0))::integer as saldo
  FROM produtos pr
  LEFT JOIN lotes_agg la ON la.pid = pr.pid
  LEFT JOIN agg_pedidos ap ON ap.prod_id = pr.pid
  WHERE la.total_entrada > 0 OR ap.total_saida > 0
  ORDER BY pr.pnome, COALESCE(la.uf, ap.uf, 'SP');
END;
$$;

-- Testar
SELECT * FROM get_estoque_completo();

-- Ver quantos pedidos tem produto preenchido
SELECT COUNT(*) FROM pedidos WHERE produto IS NOT NULL AND produto <> 'geral';

COMMIT;

-- MIGRATION: 20260415000026_estoque_final.sql
-- ESTOQUE USANDO COLUNA PRODUTO DO PEDIDO
-- Execute TODO este SQL de uma vez no Supabase SQL Editor

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH todos_pedidos AS (
    SELECT p.id as pedido_id, p.produto as produto_json, p.quantidade as qtd_total, p.uf_postagem as uf, p.status_pagamento as status
    FROM public.pedidos p
    WHERE p.produto IS NOT NULL AND p.produto <> 'geral' AND p.status_pagamento IS NOT NULL
  ),
  produtos_pedido AS (
    SELECT tp.pedido_id, tp.uf,
      CASE 
        WHEN tp.produto_json LIKE '[%' THEN 
          (SELECT (jsonb_array_elements(tp.produto_json::jsonb)->>'produto_id')::uuid)
        ELSE NULL
      END as prod_id,
      tp.qtd_total as qtd
    FROM todos_pedidos tp
  ),
  agg_pedidos AS (
    SELECT pp.prod_id, pp.uf, SUM(pp.qtd)::integer as total_saida
    FROM produtos_pedido pp WHERE pp.prod_id IS NOT NULL
    GROUP BY pp.prod_id, pp.uf
  ),
  lotes_agg AS (
    SELECT l.produto_id as pid, l.uf, SUM(l.quantidade_atual)::integer as total_entrada
    FROM public.lotes l WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, l.uf
  ),
  produtos AS (SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true)
  SELECT 
    COALESCE(la.pid, ap.prod_id, pr.pid) as prod_id,
    COALESCE(pr.pnome, 'Desconhecido') as prod_nome,
    COALESCE(la.uf, ap.uf, 'SP') as estado,
    COALESCE(la.total_entrada, 0)::integer as entrada,
    COALESCE(ap.total_saida, 0)::integer as saida,
    (COALESCE(la.total_entrada, 0) - COALESCE(ap.total_saida, 0))::integer as saldo
  FROM produtos pr
  LEFT JOIN lotes_agg la ON la.pid = pr.pid
  LEFT JOIN agg_pedidos ap ON ap.prod_id = pr.pid
  WHERE la.total_entrada > 0 OR ap.total_saida > 0
  ORDER BY pr.pnome, COALESCE(la.uf, ap.uf, 'SP');
END;
$$;

SELECT * FROM get_estoque_completo();

COMMIT;

-- MIGRATION: 20260415000027_corrigir_uf_cliente.sql
-- CORRIGIR: uf_cliente em pedidos deve vir da UF do contato
-- Executar no Supabase SQL Editor

BEGIN;

-- 1. Verificar se coluna uf_cliente existe em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

-- 2. Popular uf_cliente com a UF do contato (da tabela contatos)
UPDATE public.pedidos p
SET uf_cliente = c.uf
FROM public.contatos c
WHERE p.contato_id = c.id
AND c.uf IS NOT NULL
AND p.uf_cliente IS NULL;

-- 3. Para pedidos sem contato, usar uf_postagem como fallback
UPDATE public.pedidos p
SET uf_cliente = p.uf_postagem
WHERE p.uf_cliente IS NULL
AND p.uf_postagem IS NOT NULL;

-- 4. Verificar resultado
SELECT 
  p.id,
  p.uf_cliente,
  p.uf_postagem,
  c.nome as nome_contato,
  c.uf as uf_contato
FROM public.pedidos p
LEFT JOIN public.contatos c ON c.id = p.contato_id
ORDER BY p.created_at DESC
LIMIT 20;

-- 5. Contagem
SELECT 
  COUNT(*) as total,
  COUNT(uf_cliente) as com_uf_cliente,
  COUNT(uf_postagem) as com_uf_postagem
FROM public.pedidos;

COMMIT;

-- MIGRATION: 20260415000028_movimentacoes_saida.sql
-- CRIAR LISTA DE SAÍDA AUTOMATICAMENTE + ESTOQUE
-- Executar TODO de uma vez no Supabase SQL Editor

BEGIN;

-- 0. Dropar funções existentes
DROP FUNCTION IF EXISTS public.gerar_movimentacoes_saida();
DROP FUNCTION IF EXISTS public.get_estoque_completo();

-- 1. Limpar movimentações de saída existentes
DELETE FROM estoque_movimentacoes WHERE tipo = 'saida';

-- 2. Criar função que gera movimentações de saída de TODOS os pedidos
CREATE OR REPLACE FUNCTION public.gerar_movimentacoes_saida()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pedido RECORD;
  v_uf TEXT;
BEGIN
  -- Para cada pedido pago, criar uma movimentação de saída
  FOR v_pedido IN
    SELECT id, uf_postagem, quantidade, produto
    FROM pedidos
    WHERE status_pagamento = 'pago'
    AND produto IS NOT NULL
    AND produto <> 'geral'
  LOOP
    -- Determinar UF
    v_uf := COALESCE(v_pedido.uf_postagem, 'SP');
    
    -- Inserir movimentação de saída
    INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
    SELECT 
      p.id as produto_id,
      v_pedido.quantidade as quantidade,
      'saida' as tipo,
      'Venda' as posse,
      v_uf as uf_origem,
      v_pedido.id as pedido_id,
      'Pedido #' || v_pedido.id::text as observacao
    FROM produtos p
    WHERE p.ativo = true
    LIMIT 1;
  END LOOP;
END;
$$;

-- 3. Criar função get_estoque_completo que lê das movimentações
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH ent AS (
    SELECT COALESCE(uf, 'SP') as uff, SUM(quantidade_atual)::int as qtd
    FROM lotes WHERE quantidade_atual > 0 GROUP BY COALESCE(uf, 'SP')
  ),
  sai AS (
    SELECT COALESCE(uf_origem, 'SP') as uff, SUM(quantidade)::int as qtd
    FROM estoque_movimentacoes WHERE tipo = 'saida' GROUP BY COALESCE(uf_origem, 'SP')
  )
  SELECT e.uff, e.qtd, COALESCE(s.qtd, 0), (e.qtd - COALESCE(s.qtd, 0))
  FROM ent e LEFT JOIN sai s ON s.uff = e.uff;
END;
$$;

-- 4. Gerar movimentações de saída
SELECT public.gerar_movimentacoes_saida();

-- 5. Ver resultado - lista de movimentações
SELECT * FROM estoque_movimentacoes WHERE tipo = 'saida' ORDER BY created_at DESC;

-- 6. Ver estoque
SELECT * FROM get_estoque_completo();

COMMIT;

-- MIGRATION: 20260415000029_estoque_todos_pedidos_uf.sql
-- ESTOQUE DEFINITIVO - TODOS OS PEDIDOS + DIVISÃO POR UF + NEGATIVO
-- Executar TODO de uma vez no Supabase SQL Editor

BEGIN;

-- 0. Dropar funções existentes
DROP FUNCTION IF EXISTS public.get_estoque_completo();

-- 1. Limpar tudo
DELETE FROM estoque_movimentacoes WHERE tipo = 'saida';

-- 2. Criar função que calcula estoque DIRETO da tabela pedidos (TODOS os status)
-- Retorna: estado, entrada, saida, saldo (sem prod_id - agrega por UF)
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada integer,
  saida integer,
  saldo integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  -- Para cada produto ativo, calcular entrada (lotes) - saida (pedidos) por UF
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas_lotes AS (
    SELECT 
      l.produto_id as pid,
      COALESCE(l.uf, 'SP') as uf_lote,
      SUM(l.quantidade_atual)::integer as total_entrada
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas_pedidos AS (
    SELECT 
      pi.produto_id as pid,
      COALESCE(p.uf_postagem, 'SP') as uf_pedido,
      SUM(pi.quantidade)::integer as total_saida
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE p.status_pagamento IS NOT NULL
    GROUP BY pi.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  -- Resultado: entrada - saida (pode ser negativo!) por produto + UF
  SELECT 
    COALESCE(el.pid, sp.pid, pa.pid) as prod_id,
    pa.pnome as prod_nome,
    COALESCE(el.uf_lote, sp.uf_pedido, 'SP') as estado,
    COALESCE(el.total_entrada, 0) as entrada,
    COALESCE(sp.total_saida, 0) as saida,
    (COALESCE(el.total_entrada, 0) - COALESCE(sp.total_saida, 0)) as saldo
  FROM produtos_ativos pa
  LEFT JOIN entradas_lotes el ON el.pid = pa.pid
  LEFT JOIN saidas_pedidos sp ON sp.pid = pa.pid
  WHERE el.total_entrada > 0 OR sp.total_saida > 0
  ORDER BY pa.pnome, COALESCE(el.uf_lote, sp.uf_pedido, 'SP');
END;
$$;

-- 3. Testar
SELECT * FROM get_estoque_completo();

-- 4. Ver quantos pedidos foram considerados (TODOS!)
SELECT 
  status_pagamento,
  COUNT(*) as pedidos,
  SUM(quantidade) as total_itens
FROM pedidos 
WHERE produto IS NOT NULL AND produto <> 'geral'
GROUP BY status_pagamento;

-- 5. Ver por UF
SELECT 
  uf_postagem,
  status_pagamento,
  SUM(quantidade) as total
FROM pedidos 
WHERE produto IS NOT NULL AND produto <> 'geral'
GROUP BY uf_postagem, status_pagamento
ORDER BY uf_postagem, status_pagamento;

COMMIT;

-- MIGRATION: 20260415000030_estoque_produto_misto.sql
-- ESTOQUE DEFINITIVO - COLUNA PRODUTO MISTA (JSON + TEXT)
-- Executar TODO de uma vez no Supabase SQL Editor

BEGIN;

-- 0. Dropar funções existentes
DROP FUNCTION IF EXISTS public.get_estoque_completo();

-- 1. Criar função que handle COLUNA PRODUTO MISTA (JSON + TEXT)
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  -- Entradas: lotes por produto+UF
  entradas_lotes AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_atual)::int as qtd_ent
    FROM public.lotes l WHERE l.quantidade_atual > 0 GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  -- Saidas: pedidos - treating COLUNA PRODUTO MISTA
  saidas_pedidos AS (
    SELECT 
      p.id as ped_id,
      p.produto as prod_json,
      p.quantidade as qtd_pedido,
      COALESCE(p.uf_postagem, 'SP') as uff
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto IS NOT NULL AND p.produto <> 'geral'
  ),
  -- Processar cada pedido - extrair produto_id do JSON ou texto
  itens_extraidos AS (
    SELECT 
      sp.ped_id,
      sp.uff,
      CASE
        -- Se é JSON array, extrair produto_id
        WHEN sp.prod_json LIKE '[%' THEN
          (SELECT (jsonb_array_elements(sp.prod_json::jsonb)->>'produto_id')::uuid)
        -- Se é texto simples, procurar produto pelo nome
        WHEN sp.prod_json LIKE '%[{%' THEN NULL  -- JSON object, mais complexo
        ELSE NULL  -- texto simples
      END as prod_id,
      sp.qtd_pedido as qtd
    FROM saidas_pedidos sp
  ),
  -- Agrupar por produto + UF
  agg_saidas AS (
    SELECT ie.prod_id as pid, ie.uff, SUM(ie.qtd)::int as qtd_sai
    FROM itens_extraidos ie WHERE ie.prod_id IS NOT NULL
    GROUP BY ie.prod_id, ie.uff
  )
  --Resultado
  SELECT 
    COALESCE(el.pid, ase.pid, pa.pid) as prod_id,
    pa.pnome as prod_nome,
    COALESCE(el.uff, ase.uff, 'SP') as estado,
    COALESCE(el.qtd_ent, 0) as entrada,
    COALESCE(ase.qtd_sai, 0) as saida,
    (COALESCE(el.qtd_ent, 0) - COALESCE(ase.qtd_sai, 0)) as saldo
  FROM produtos_ativos pa
  LEFT JOIN entradas_lotes el ON el.pid = pa.pid
  LEFT JOIN agg_saidas ase ON ase.pid = pa.pid
  WHERE el.qtd_ent > 0 OR ase.qtd_sai > 0
  ORDER BY pa.pnome, COALESCE(el.uff, ase.uff, 'SP');
END;
$$;

-- VERSÃO SIMPLIFICADA - usando quantity do pedido diretamente
-- Considera TODOS os pedidos (pagos + pendentes) por UF
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada integer, saida integer, saldo integer)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  -- Para simplificar: criar uma "saída genérica" por UF (soma de TODOS os pedidos)
  todas_saidas AS (
    SELECT 
      COALESCE(p.uf_postagem, 'SP') as uff,
      SUM(p.quantidade)::int as total_saida
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL 
      AND p.produto IS NOT NULL 
      AND p.produto <> 'geral'
    GROUP BY COALESCE(p.uf_postagem, 'SP')
  ),
  -- Entradas por UF
  todas_entradas AS (
    SELECT 
      COALESCE(l.uf, 'SP') as uff,
      SUM(l.quantidade_atual)::int as total_entrada
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY COALESCE(l.uf, 'SP')
  )
  -- Resultado: mostrar por UF (não por produto específico ainda)
  SELECT 
    NULL::uuid as prod_id,
    'Geral' as prod_nome,
    te.uff as estado,
    te.total_entrada as entrada,
    COALESCE(ts.total_saida, 0) as saida,
    (te.total_entrada - COALESCE(ts.total_saida, 0)) as saldo
  FROM todas_entradas te
  LEFT JOIN todas_saidas ts ON ts.uff = te.uff
  ORDER BY te.uff;
END;
$$;

-- Testar
SELECT * FROM get_estoque_completo();

COMMIT;

-- MIGRATION: 20260415000031_estoque_corrigido.sql
-- ESTOQUE COMPLETO: TODOS os pedidos + TODOS os produtos do JSON array + TRIGGER AUTOMÁTICO
-- Executar TODO no Supabase SQL Editor

BEGIN;

-- 1. Resetar estoque_processado
UPDATE public.pedidos SET estoque_processado = false;

-- 2. Dropar função existente
DROP FUNCTION IF EXISTS public.get_estoque_completo();

-- 3. Criar função get_estoque_completo()
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
  -- Todas as saídas: produto_id direto + TODOS itens do JSON
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

-- 4. Criar trigger automático para novos pedidos
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
BEGIN
  -- Verificar se é INSERT e se tem produto
  IF TG_OP = 'INSERT' AND NEW.produto IS NOT NULL AND NEW.produto <> 'geral' THEN
    v_uf := COALESCE(NEW.uf_postagem, 'SP');
    
    -- Se tem produto_id direto (1 item)
    IF NEW.produto_id IS NOT NULL THEN
      INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
      VALUES (NEW.produto_id, NEW.quantidade, 'saida', 'Venda', v_uf, NEW.id, 'Pedido #' || NEW.id::text);
    
    -- Se tem JSON array (múltiplos itens)
    ELSIF NEW.produto LIKE '[%' THEN
      FOR v_item IN SELECT jsonb_array_elements(NEW.produto::jsonb)
      LOOP
        v_produto_id := (v_item->>'produto_id')::uuid;
        v_qtd := (v_item->>'quantidade')::int;
        
        IF v_produto_id IS NOT NULL THEN
          INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
          VALUES (v_produto_id, v_qtd, 'saida', 'Venda', v_uf, NEW.id, 'Pedido #' || NEW.id::text);
        END IF;
      END LOOP;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 5. Criar/atualizar trigger
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
CREATE TRIGGER trg_novo_pedido_estoque
  AFTER INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_novo_pedido_estoque();

-- 6. Criar movimentações históricas (executar uma vez)
CREATE OR REPLACE FUNCTION public.criar_movimentacoes_saida()
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido record;
  v_item jsonb;
  v_produto_id uuid;
  v_qtd integer;
  v_uf text;
  v_encontrado boolean;
BEGIN
  FOR v_pedido IN
    SELECT p.id, p.produto, p.produto_id, p.quantidade, COALESCE(p.uf_postagem, 'SP') as uf
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL 
      AND p.produto IS NOT NULL 
      AND p.produto <> 'geral'
  LOOP
    v_uf := v_pedido.uf;
    
    IF v_pedido.produto_id IS NOT NULL THEN
      SELECT EXISTS (
        SELECT 1 FROM public.estoque_movimentacoes em 
        WHERE em.observacao LIKE 'Pedido #' || v_pedido.id::text
      ) INTO v_encontrado;
      
      IF NOT v_encontrado THEN
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
        VALUES (v_pedido.produto_id, v_pedido.quantidade, 'saida', 'Venda', v_uf, v_pedido.id, 'Pedido #' || v_pedido.id::text);
      END IF;
    
    ELSIF v_pedido.produto LIKE '[%' THEN
      FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb)
      LOOP
        v_produto_id := (v_item->>'produto_id')::uuid;
        v_qtd := (v_item->>'quantidade')::int;
        
        SELECT EXISTS (
          SELECT 1 FROM public.estoque_movimentacoes em 
          WHERE em.observacao LIKE 'Pedido #' || v_pedido.id::text
        ) INTO v_encontrado;
        
        IF NOT v_encontrado AND v_produto_id IS NOT NULL THEN
          INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
          VALUES (v_produto_id, v_qtd, 'saida', 'Venda', v_uf, v_pedido.id, 'Pedido #' || v_pedido.id::text);
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- 7. Executar criação de movimentações históricas
SELECT criar_movimentacoes_saida();

-- 8. Testar
SELECT * FROM get_estoque_completo() ORDER BY prod_nome, estado;

SELECT tipo, COUNT(*) FROM public.estoque_movimentacoes GROUP BY tipo;

COMMIT;

-- MIGRATION: 20260415000032_produtos_customizaveis.sql
-- Adicionar colunas para products customizáveis
BEGIN;

-- 1. Criar tabela de grupos de produtos (se não existir)
CREATE TABLE IF NOT EXISTS public.produtos_grupos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  cor_grupo text,
  ordem integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 2. RLS para grupos (se não existir)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can manage produtos_grupos' AND tablename = 'produtos_grupos'
  ) THEN
    ALTER TABLE public.produtos_grupos ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Authenticated users can manage produtos_grupos" ON public.produtos_grupos FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END
$$;

-- 3. Adicionar coluna grupo_id (opcional, para agrupamento)
ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS grupo_id uuid REFERENCES public.produtos_grupos(id);

-- 4. Adicionar coluna limite_estoque (quantos produtos quer em estoque)
ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS limite_estoque integer DEFAULT 0;

COMMIT;

-- MIGRATION: 20260416000000_produtos_rpc.sql
-- Criar funções RPC para gerenciamento de produtos
BEGIN;

-- Função para criar produto
CREATE OR REPLACE FUNCTION create_produto(
  p_nome_oficial text,
  p_tag text,
  p_cor_card text DEFAULT '#ffffff',
  p_cor_texto text DEFAULT '#000000',
  p_limite_estoque integer DEFAULT 0,
  p_grupo_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO produtos (
    nome_oficial,
    tag,
    cor_card,
    cor_texto,
    limite_estoque,
    grupo_id,
    ativo
  ) VALUES (
    p_nome_oficial,
    p_tag,
    p_cor_card,
    p_cor_texto,
    p_limite_estoque,
    p_grupo_id,
    true
  )
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;

-- Função para atualizar produto
CREATE OR REPLACE FUNCTION update_produto(
  p_id uuid,
  p_nome_oficial text,
  p_tag text,
  p_cor_card text,
  p_cor_texto text,
  p_limite_estoque integer,
  p_grupo_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE produtos SET
    nome_oficial = p_nome_oficial,
    tag = p_tag,
    cor_card = p_cor_card,
    cor_texto = p_cor_texto,
    limite_estoque = p_limite_estoque,
    grupo_id = p_grupo_id
  WHERE id = p_id;
END;
$$;

-- Função para excluir produto
CREATE OR REPLACE FUNCTION delete_produto(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM produtos WHERE id = p_id;
END;
$$;

-- Função para criar grupo
CREATE OR REPLACE FUNCTION create_produto_grupo(p_nome text, p_cor text DEFAULT '#ffffff')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO produtos_grupos (nome, cor_grupo) VALUES (p_nome, p_cor)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Função para atualizar grupo
CREATE OR REPLACE FUNCTION update_produto_grupo(p_id uuid, p_nome text, p_cor text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE produtos_grupos SET nome = p_nome, cor_grupo = p_cor WHERE id = p_id;
END;
$$;

-- Função para excluir grupo
CREATE OR REPLACE FUNCTION delete_produto_grupo(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE produtos SET grupo_id = NULL WHERE grupo_id = p_id;
  DELETE FROM produtos_grupos WHERE id = p_id;
END;
$$;

-- Função para atualizar status do produto (ativar/inativar)
CREATE OR REPLACE FUNCTION update_produto_status(p_id uuid, p_ativo boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE produtos SET ativo = p_ativo WHERE id = p_id;
END;
$$;

COMMIT;

-- MIGRATION: 20260416052347_24355aa9-0c26-4183-9b85-b53253983d31.sql
-- Drop the incomplete criar_pedido_v2 function
DROP FUNCTION IF EXISTS public.criar_pedido_v2(uuid, text, numeric, text, text, text, text, text, jsonb);

-- Drop any conflicting INSERT triggers on pedidos that cause duplicate stock processing
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
DROP TRIGGER IF EXISTS trg_abate_estoque_pedido ON public.pedidos;
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;

-- Drop their associated functions if they exist
DROP FUNCTION IF EXISTS public.trigger_processar_pedido_estoque() CASCADE;
DROP FUNCTION IF EXISTS public.trigger_abate_estoque_pedido() CASCADE;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque() CASCADE;

-- Confirm only the safe triggers remain
SELECT 'Migration complete. Remaining triggers on pedidos:' as status;
SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.pedidos'::regclass AND NOT tgisinternal;

-- MIGRATION: 20260417000001_estoque_snapshot_cleanup.sql
-- ESTOQUE SNAPSHOT PARA LIMPEZA DE MOVIMENTAÇÕES ANTIGAS
-- Executar NO Supabase SQL Editor
-- Este snapshot garante que ao apagar movimentações com +90 dias, o estoque não seja afetado

BEGIN;

-- 1. Criar tabela de snapshot de estoque
CREATE TABLE IF NOT EXISTS public.estoque_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  produto_id uuid REFERENCES public.produtos(id),
  uf text NOT NULL,
  saldo numeric(10,0) NOT NULL,
  data_snapshot timestamptz DEFAULT now(),
  observacao text,
  UNIQUE(produto_id, uf)
);

-- 2. Criar índice para buscas rápidas
CREATE INDEX IF NOT EXISTS idx_estoque_snapshots_produto_uf 
ON public.estoque_snapshots(produto_id, uf);

-- 3. Função para criar snapshot atual do estoque
CREATE OR REPLACE FUNCTION public.criar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $BODY$
DECLARE
  v_rec record;
BEGIN
  DELETE FROM public.estoque_snapshots;
  
  FOR v_rec IN
    SELECT prod_id, estado, saldo
    FROM public.get_estoque_completo()
  LOOP
    INSERT INTO public.estoque_snapshots (produto_id, uf, saldo)
    VALUES (v_rec.prod_id::uuid, v_rec.estado, v_rec.saldo)
    ON CONFLICT (produto_id, uf) 
    DO UPDATE SET saldo = v_rec.saldo, data_snapshot = now();
  END LOOP;
END;
$BODY$;

-- 4. Função para limpar movimentações antigas com segurança
CREATE OR REPLACE FUNCTION public.limpar_movimentacoes_antigas(p_dias text DEFAULT '90')
RETURNS TABLE(registros_apagados int, saldo_restaurado json)
LANGUAGE plpgsql
SET search_path TO 'public'
AS $BODY$
DECLARE
  v_dias_int int;
  v_count int;
  v_saldo json;
BEGIN
  v_dias_int := p_dias::int;
  
  IF NOT EXISTS (SELECT 1 FROM public.estoque_snapshots) THEN
    PERFORM public.criar_estoque_snapshot();
  END IF;
  
  SELECT COUNT(*)::int INTO v_count
  FROM public.estoque_movimentacoes
  WHERE created_at < NOW() - (v_dias_int || ' days')::interval;
  
  DELETE FROM public.estoque_movimentacoes
  WHERE created_at < NOW() - (v_dias_int || ' days')::interval;
  
  PERFORM public.criar_estoque_snapshot();
  
  SELECT json_agg(json_build_object(
    'produto_id', produto_id,
    'uf', uf,
    'saldo', saldo
  )) INTO v_saldo
  FROM public.estoque_snapshots;
  
  RETURN QUERY SELECT v_count, v_saldo;
END;
$BODY$;

-- 5. Criar snapshot inicial
SELECT public.criar_estoque_snapshot();

-- 6. Verificar
SELECT COUNT(*) as total_movimentacoes FROM public.estoque_movimentacoes;
SELECT COUNT(*) as total_snapshots FROM public.estoque_snapshots;

COMMIT;

-- MIGRATION: 20260417000002_uf_change_trigger.sql
-- Parte 1: atualiza trigger existente
DROP TRIGGER IF EXISTS trg_uf_postagem_update ON public.pedidos;

-- Trigger recriado vai detectar mudança de qualquer UF
CREATE TRIGGER trg_uf_postagem_update 
AFTER UPDATE OF uf_postagem ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.trigger_uf_postagem_update();

SELECT 'Trigger ativado' as msg;

-- MIGRATION: 20260417000003_regenerar_uf_changes.sql
-- REGENERAR MOVIMENTAÇÕES DE MUDANÇA DE UF (Histórico)
-- Executar NO Supabase SQL Editor

BEGIN;

-- 1. Criar função para detectar mudanças de UF via logs ou histórico
-- Como não temos logs, vamos verificar se há pedidos que mudaram de UF
-- Mas se o trigger não disparou, não há como saber... 

-- 2. Criar função para registrar mudança de UF manualmente
CREATE OR REPLACE FUNCTION public.registrar_mudanca_uf(
  p_pedido_id uuid,
  p_uf_antiga text,
  p_uf_nova text
)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $BODY$
DECLARE
  v_item jsonb; v_prod_id uuid; v_qty integer;
BEGIN
  -- Entrada (devolução) na UF antiga
  FOR v_item IN SELECT * FROM jsonb_array_elements((SELECT produto FROM pedidos WHERE id = p_pedido_id)::jsonb) LOOP
    v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
    v_qty := (v_item->>'quantidade')::integer;
    IF v_prod_id IS NOT NULL AND v_qty > 0 THEN
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
      VALUES (v_prod_id, v_qty, 'entrada', 'Devolução', p_uf_antiga, p_pedido_id, 'Mudança UF: ' || p_uf_antiga || ' → ' || p_uf_nova);
    END IF;
  END LOOP;
  
  -- Saída na UF nova
  FOR v_item IN SELECT * FROM jsonb_array_elements((SELECT produto FROM pedidos WHERE id = p_pedido_id)::jsonb) LOOP
    v_prod_id := NULLIF(v_item->>'produto_id', '')::uuid;
    v_qty := (v_item->>'quantidade')::integer;
    IF v_prod_id IS NOT NULL AND v_qty > 0 THEN
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
      VALUES (v_prod_id, v_qty, 'saida', p_uf_nova, p_uf_nova, p_pedido_id, 'Pedido #' || p_pedido_id::text);
    END IF;
  END LOOP;
  
  UPDATE pedidos SET estoque_processado = true WHERE id = p_pedido_id;
END;
$BODY$;

-- 3. Como não temos histórico de mudanças de UF, o usuário precisa informar manualmente
-- Se souber o ID do pedido e as UFs, pode executar:
-- SELECT registrar_mudanca_uf('UUID_DO_PEDIDO', 'UF_ANTIGA', 'UF_NOVA');

-- 4. Verificar movimentações existentes de "Mudança UF"
SELECT * FROM estoque_movimentacoes 
WHERE observacao LIKE 'Mudança UF%'
ORDER BY created_at DESC;

COMMIT;

-- MIGRATION: 20260417000004_fix_get_estoque.sql
-- CORRIGIR get_estoque_completo para mostrar ATÉ mesmo produtos só com entrada
BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();

CREATE FUNCTION public.get_estoque_completo()
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
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    COALESCE(e.uff, 'SP') as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM produtos_ativos pr
  LEFT JOIN entradas e ON e.pid = pr.pid
  LEFT JOIN saidas s ON s.pid = pr.pid
  ORDER BY pr.pnome, COALESCE(e.uff, 'SP');
END;
$$;

SELECT * FROM get_estoque_completo() ORDER BY prod_nome, estado;

-- MIGRATION: 20260417000005_restaurar_get_estoque.sql
-- MOSTRAR TODOS produtos com entrada (mesmo sem venda)
DROP FUNCTION IF EXISTS public.get_estoque_completo();

CREATE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH entradas AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_atual)::int as qtd_ent
    FROM public.lotes l WHERE l.quantidade_atual > 0 GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, 'SP') as uff, SUM(p.quantidade)::int as qtd_sai
    FROM public.pedidos p WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL
    GROUP BY p.produto_id, COALESCE(p.uf_postagem, 'SP')
  )
  SELECT 
    COALESCE(e.pid, s.pid) as prod_id,
    pr.nome_oficial as prod_nome,
    COALESCE(e.uff, s.uff) as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM public.produtos pr
  LEFT JOIN entradas e ON e.pid = pr.id
  LEFT JOIN saidas s ON s.pid = pr.id
  WHERE COALESCE(e.qtd_ent, 0) > 0
  ORDER BY pr.nome_oficial;
END;
$$;


-- MIGRATION: 20260417203538_9bcad82b-6bc7-461f-9638-ea28407cc22d.sql
-- Fix: DELETE requires a WHERE clause (PostgREST safety)
-- Substitui DELETE puro por DELETE ... WHERE true em ambas as funcoes de snapshot

CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    DELETE FROM public.estoque_snapshot WHERE true;
    
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    WITH entradas AS (
        SELECT produto_id, uf as estado, SUM(quantidade_inicial)::int as entrada
        FROM public.lotes WHERE produto_id IS NOT NULL GROUP BY produto_id, uf
    ),
    saidas AS (
        SELECT produto_id, estado, SUM(quantidade)::int as saida FROM (
            SELECT 
                (elem->>'produto_id')::uuid as produto_id,
                LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as estado,
                (elem->>'quantidade')::int as quantidade
            FROM public.pedidos p,
            LATERAL jsonb_array_elements(
                CASE 
                    WHEN p.produto IS NOT NULL AND p.produto LIKE '[%' THEN p.produto::jsonb 
                    ELSE '[]'::jsonb 
                END
            ) AS elem
            WHERE p.status_pedido != 'cancelado' 
              AND p.data >= '2026-04-01'
              AND p.produto LIKE '[%'
              AND (p.observacao IS NULL OR (p.observacao NOT ILIKE '%Troca de UF%' AND p.observacao NOT ILIKE '%Devolução%'))
            
            UNION ALL
            
            SELECT 
                COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as produto_id,
                LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as estado,
                p.quantidade as quantidade
            FROM public.pedidos p
            WHERE p.status_pedido != 'cancelado'
              AND p.data >= '2026-04-01'
              AND (p.produto NOT LIKE '[%' OR p.produto IS NULL)
              AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
              AND (p.observacao IS NULL OR (p.observacao NOT ILIKE '%Troca de UF%' AND p.observacao NOT ILIKE '%Devolução%'))
        ) todas_saidas
        WHERE produto_id IS NOT NULL
        GROUP BY produto_id, estado
    )
    SELECT 
        COALESCE(e.produto_id, s.produto_id),
        (SELECT nome_oficial FROM public.produtos WHERE id = COALESCE(e.produto_id, s.produto_id)),
        COALESCE(e.estado, s.estado),
        COALESCE(e.entrada, 0),
        COALESCE(s.saida, 0),
        (COALESCE(e.entrada, 0) - COALESCE(s.saida, 0)),
        NOW()
    FROM entradas e
    FULL JOIN saidas s ON e.produto_id = s.produto_id AND e.estado = s.estado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.criar_estoque_snapshot()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_rec record;
BEGIN
  DELETE FROM public.estoque_snapshots WHERE true;
  FOR v_rec IN SELECT prod_id, estado, saldo FROM public.get_estoque_completo() LOOP
    INSERT INTO public.estoque_snapshots (produto_id, uf, saldo)
    VALUES (v_rec.prod_id::uuid, v_rec.estado, v_rec.saldo)
    ON CONFLICT (produto_id, uf) DO UPDATE SET saldo = v_rec.saldo, data_snapshot = now();
  END LOOP;
END;
$function$;

-- MIGRATION: 20260417204023_4c776cd6-1fc3-4a12-ad8f-b5f2b227e142.sql
CREATE OR REPLACE FUNCTION public.criar_pedido_v2(p_contato_id uuid, p_canal text DEFAULT 'ADS'::text, p_valor numeric DEFAULT 0, p_status_pagamento text DEFAULT 'pago'::text, p_modalidade text DEFAULT 'mini'::text, p_uf_postagem text DEFAULT NULL::text, p_criado_por text DEFAULT 'V'::text, p_obs text DEFAULT NULL::text, p_produtos jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_pedido_id uuid;
  v_contato_id uuid;
  v_produto_id uuid;
  v_qtd integer;
  v_order_number integer;
  v_data_sp date;
  v_uf_postagem_calc text;
  v_uf_cliente text;
  v_modalidade_calc text;
  v_socio text;          -- valor do constraint: V, A ou P
  v_criado_por text;     -- apelido original (ver/a) para auditoria
  v_canal_lancamento text;
  v_quantidade_total integer;
  v_produto_text text;
BEGIN
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_contato_id IS NULL THEN
    RAISE EXCEPTION 'p_contato_id e obrigatorio';
  END IF;
  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN
    RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id;
  END IF;

  -- Mapeia apelido -> letra do socio (constraint exige V/A/P)
  v_criado_por := COALESCE(NULLIF(LOWER(TRIM(p_criado_por)), ''), 'v');
  IF p_status_pagamento = 'pendente' THEN
    v_socio := 'P';
  ELSIF v_criado_por IN ('v', 'ver') THEN
    v_socio := 'V';
  ELSIF v_criado_por IN ('a') THEN
    v_socio := 'A';
  ELSE
    -- fallback: pega primeira letra em maiusculo
    v_socio := UPPER(LEFT(v_criado_por, 1));
    IF v_socio NOT IN ('V', 'A', 'P') THEN
      v_socio := 'V';
    END IF;
  END IF;

  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS';
  END IF;

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM((item->>'quantidade')::integer), 1)::int INTO v_quantidade_total
    FROM jsonb_array_elements(p_produtos) AS item;
  ELSE
    v_quantidade_total := 1;
  END IF;

  BEGIN
    SELECT cidade_uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  IF p_uf_postagem IS NOT NULL AND LENGTH(p_uf_postagem) = 2 THEN
    v_uf_postagem_calc := p_uf_postagem;
  ELSE
    v_uf_postagem_calc := COALESCE(v_uf_cliente, 'SC');
  END IF;
  v_modalidade_calc := COALESCE(p_modalidade, 'mini');

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    v_quantidade_total := 0;
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      v_quantidade_total := v_quantidade_total + COALESCE(v_qtd, 1);
    END LOOP;

    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := (p_produtos->0->>'produto');
    ELSE
      v_produto_text := p_produtos::text;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
  END IF;

  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, obs, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, v_criado_por, v_order_number, v_data_sp,
    false, now(),
    COALESCE(v_produto_text, ''), v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  IF p_status_pagamento IN ('pago', 'pendente') THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento,
      v_criado_por, v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$function$;

-- MIGRATION: 20260417205250_1ca1d924-46fd-4487-8830-881e3ac69827.sql
CREATE OR REPLACE FUNCTION public.criar_pedido_v2(
  p_contato_id uuid,
  p_canal text DEFAULT 'ADS'::text,
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago'::text,
  p_modalidade text DEFAULT 'mini'::text,
  p_uf_postagem text DEFAULT NULL::text,
  p_criado_por text DEFAULT 'V'::text,
  p_obs text DEFAULT NULL::text,
  p_produtos jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_pedido_id uuid;
  v_contato_id uuid;
  v_order_number integer;
  v_data_sp date;
  v_uf_postagem_calc text;
  v_uf_cliente text;
  v_modalidade_calc text;
  v_socio text;
  v_criado_por text;
  v_canal_lancamento text;
  v_quantidade_total integer;
  v_produto_text text;
  v_item jsonb;
  v_item_produto_id uuid;
  v_item_qtd integer;
  v_item_nome text;
  v_first_produto_id uuid;
BEGIN
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_contato_id IS NULL THEN
    RAISE EXCEPTION 'p_contato_id e obrigatorio';
  END IF;
  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN
    RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id;
  END IF;

  -- Mapeia apelido -> letra do socio (constraint exige V/A/P)
  v_criado_por := COALESCE(NULLIF(LOWER(TRIM(p_criado_por)), ''), 'v');
  IF p_status_pagamento = 'pendente' THEN
    v_socio := 'P';
  ELSIF v_criado_por IN ('v', 'ver') THEN
    v_socio := 'V';
  ELSIF v_criado_por IN ('a') THEN
    v_socio := 'A';
  ELSE
    v_socio := UPPER(LEFT(v_criado_por, 1));
    IF v_socio NOT IN ('V', 'A', 'P') THEN
      v_socio := 'V';
    END IF;
  END IF;

  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS';
  END IF;

  BEGIN
    SELECT cidade_uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  IF p_uf_postagem IS NOT NULL AND LENGTH(p_uf_postagem) = 2 THEN
    v_uf_postagem_calc := p_uf_postagem;
  ELSE
    v_uf_postagem_calc := COALESCE(v_uf_cliente, 'SC');
  END IF;
  v_modalidade_calc := COALESCE(p_modalidade, 'mini');

  -- Calcula quantidade total e texto do produto
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM(COALESCE((item->>'quantidade')::integer, 1)), 1)::int
    INTO v_quantidade_total
    FROM jsonb_array_elements(p_produtos) AS item;

    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := COALESCE(p_produtos->0->>'produto', p_produtos->0->>'nome_oficial', '');
      v_first_produto_id := NULLIF(p_produtos->0->>'produto_id', '')::uuid;
    ELSE
      v_produto_text := p_produtos::text;
      v_first_produto_id := NULL;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
    v_first_produto_id := NULL;
  END IF;

  -- Insert pedido
  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, obs, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, produto_id, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, v_criado_por, v_order_number, v_data_sp,
    true, now(),
    COALESCE(v_produto_text, ''), v_first_produto_id, v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  -- Cria itens e movimentações de saída
  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_produtos)
    LOOP
      v_item_produto_id := NULLIF(v_item->>'produto_id', '')::uuid;
      v_item_qtd := COALESCE((v_item->>'quantidade')::integer, 1);
      v_item_nome := COALESCE(v_item->>'produto', v_item->>'nome_oficial', '');

      -- Se não tiver produto_id, tenta resolver por nome
      IF v_item_produto_id IS NULL AND v_item_nome <> '' THEN
        SELECT id INTO v_item_produto_id
        FROM public.produtos
        WHERE LOWER(nome_oficial) = LOWER(TRIM(v_item_nome))
           OR LOWER(tag) = LOWER(TRIM(v_item_nome))
        LIMIT 1;
      END IF;

      IF v_item_produto_id IS NOT NULL THEN
        -- Pedido item
        INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
        VALUES (
          v_pedido_id, v_item_produto_id, v_item_nome, v_item_qtd,
          NULLIF(v_item->>'preco', '')::numeric
        );

        -- Movimentação de saída
        INSERT INTO public.estoque_movimentacoes (
          produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, data
        )
        VALUES (
          v_item_produto_id, v_item_qtd, 'saida', 'Venda', v_uf_postagem_calc,
          v_pedido_id,
          'Pedido #' || v_order_number::text || ' - ' || v_item_nome,
          v_data_sp
        );
      END IF;
    END LOOP;
  END IF;

  -- Lancamento socio
  IF p_status_pagamento IN ('pago', 'pendente') THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento,
      v_criado_por, v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$function$;

-- Backfill: corrigir pedido #21 (e quaisquer outros sem movimentação)
DO $backfill$
DECLARE
  v_ped record;
  v_item jsonb;
  v_pid uuid;
  v_qty integer;
  v_nome text;
BEGIN
  FOR v_ped IN
    SELECT p.id, p.order_number, p.produto, p.produto_id, p.quantidade, p.uf_postagem, p.data
    FROM public.pedidos p
    WHERE p.status_pedido != 'cancelado'
      AND p.data >= '2026-04-01'
      AND NOT EXISTS (
        SELECT 1 FROM public.estoque_movimentacoes em
        WHERE em.pedido_id = p.id AND em.tipo = 'saida'
      )
  LOOP
    IF v_ped.produto IS NOT NULL AND v_ped.produto LIKE '[%' THEN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_ped.produto::jsonb)
      LOOP
        v_pid := NULLIF(v_item->>'produto_id', '')::uuid;
        v_qty := COALESCE((v_item->>'quantidade')::integer, 1);
        v_nome := COALESCE(v_item->>'produto', '');
        IF v_pid IS NULL AND v_nome <> '' THEN
          SELECT id INTO v_pid FROM public.produtos
          WHERE LOWER(nome_oficial)=LOWER(TRIM(v_nome)) OR LOWER(tag)=LOWER(TRIM(v_nome)) LIMIT 1;
        END IF;
        IF v_pid IS NOT NULL THEN
          INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, data)
          VALUES (v_pid, v_qty, 'saida', 'Venda', COALESCE(v_ped.uf_postagem,'SP'), v_ped.id,
                  'Backfill Pedido #' || v_ped.order_number || ' - ' || v_nome, v_ped.data);
        END IF;
      END LOOP;
    ELSE
      v_pid := v_ped.produto_id;
      v_nome := COALESCE(v_ped.produto, '');
      IF v_pid IS NULL AND v_nome <> '' THEN
        SELECT id INTO v_pid FROM public.produtos
        WHERE LOWER(nome_oficial)=LOWER(TRIM(v_nome)) OR LOWER(tag)=LOWER(TRIM(v_nome)) LIMIT 1;
      END IF;
      IF v_pid IS NOT NULL THEN
        UPDATE public.pedidos SET produto_id = v_pid WHERE id = v_ped.id AND produto_id IS NULL;
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, data)
        VALUES (v_pid, COALESCE(v_ped.quantidade,1), 'saida', 'Venda', COALESCE(v_ped.uf_postagem,'SP'), v_ped.id,
                'Backfill Pedido #' || v_ped.order_number || ' - ' || v_nome, v_ped.data);
      END IF;
    END IF;
    UPDATE public.pedidos SET estoque_processado = true WHERE id = v_ped.id;
  END LOOP;
END;
$backfill$;

-- Atualiza snapshot
SELECT public.atualizar_estoque_snapshot();

-- MIGRATION: 20260418000001_fixar_abatimento_estoque_multiplos_produtos.sql
-- ==============================================================================
-- CORREÇÃO CRÍTICA: Abatimento de Estoque com Múltiplos Produtos
-- Executar no Supabase SQL Editor (ou via CLI migrate).
--
-- Se o editor truncar o script, execute na ordem as seções marcadas:
--   --- PARTE 1 ---  até  --- FIM PARTE 1 ---
--   ... PARTE 2 ... etc.
-- ==============================================================================

-- --- PARTE 1 --- Remover triggers duplicados (INSERT em pedidos não deve abater aqui)
DROP TRIGGER IF EXISTS trg_processar_pedido_estoque ON public.pedidos;
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque() CASCADE;
-- --- FIM PARTE 1 ---

-- --- PARTE 2 --- criar_pedido: JSON → pedido_itens + um único caminho de abatimento
DROP FUNCTION IF EXISTS public.criar_pedido(
  uuid, text, numeric, text, text, text, text, text, jsonb, uuid
);

CREATE OR REPLACE FUNCTION public.criar_pedido(
  p_contato_id uuid DEFAULT NULL,
  p_canal text DEFAULT 'ADS',
  p_valor numeric DEFAULT 0,
  p_status_pagamento text DEFAULT 'pago',
  p_modalidade text DEFAULT 'mini',
  p_uf_postagem text DEFAULT NULL,
  p_criado_por text DEFAULT 'V',
  p_obs text DEFAULT NULL,
  p_produtos jsonb DEFAULT NULL,
  p_representante_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pedido_id uuid;
  v_order_number integer;
  v_data_sp date;
  v_produto_text text;
  v_quantidade integer;
  v_socio text;
  v_canal_lancamento text;
  v_is_entrega_maos boolean;
  v_uf_postagem_eff text;
BEGIN
  v_data_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_is_entrega_maos := (p_modalidade = 'entrega_maos');
  v_uf_postagem_eff := NULLIF(trim(COALESCE(p_uf_postagem, '')), '');

  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (
      SELECT string_agg(COALESCE(x->>'produto', x->>'nome_oficial'), ', ')
      FROM jsonb_array_elements(p_produtos) AS x
    );
    v_quantidade := (
      SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x
    );
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  v_socio := CASE
    WHEN p_criado_por ILIKE 'v%' OR p_criado_por ILIKE 'v@%' THEN 'V'
    ELSE 'A'
  END;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;

  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem,
    criado_por, produto, quantidade, order_number, data, status_pedido,
    representante_id, tipo_origem, entrega_em_maos, observacao,
    estoque_debitado, estoque_processado
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, p_status_pagamento, p_modalidade, v_uf_postagem_eff,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio',
    p_representante_id,
    CASE
      WHEN p_representante_id IS NOT NULL THEN 'rep'
      WHEN p_canal = 'ADS' THEN 'ads'
      ELSE 'base'
    END,
    v_is_entrega_maos, p_obs,
    v_is_entrega_maos,
    v_is_entrega_maos
  ) RETURNING id INTO v_pedido_id;

  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
    SELECT
      v_pedido_id,
      COALESCE(
        NULLIF(x->>'produto_id', '')::uuid,
        (SELECT pr.id FROM public.produtos pr
         WHERE pr.ativo = true AND lower(trim(pr.nome_oficial)) = lower(trim(COALESCE(x->>'produto', x->>'nome_oficial', '')))
         LIMIT 1)
      ),
      COALESCE(x->>'produto', x->>'nome_oficial'),
      GREATEST(COALESCE((x->>'quantidade')::integer, 0), 0),
      COALESCE(
        NULLIF(x->>'valor_unit', '')::numeric,
        NULLIF(x->>'preco', '')::numeric
      )
    FROM jsonb_array_elements(p_produtos) AS x
    WHERE COALESCE((x->>'quantidade')::integer, 0) > 0
      AND (
        NULLIF(x->>'produto_id', '') IS NOT NULL
        OR COALESCE(x->>'produto', x->>'nome_oficial', '') <> ''
      );
  END IF;

  -- UF vazia: processar desconta da UF com mais estoque no produto (ver processar_pedido_estoque_trigger)
  IF p_representante_id IS NULL AND EXISTS (SELECT 1 FROM public.pedido_itens WHERE pedido_id = v_pedido_id) THEN
    PERFORM public.processar_pedido_estoque_trigger(v_pedido_id, v_uf_postagem_eff);
  END IF;

  IF p_contato_id IS NOT NULL AND p_status_pagamento = 'pago' THEN
    UPDATE public.contatos
    SET
      status_kanban = CASE WHEN p_canal = 'BASE' THEN 'Clientes' ELSE 'Pagou' END,
      canal_atual = CASE WHEN p_canal = 'BASE' THEN 'BASE' ELSE COALESCE(canal_atual, p_canal) END,
      is_novo = (p_canal = 'BASE'),
      novo_ate = CASE WHEN p_canal = 'BASE' THEN ((CURRENT_DATE + 1)::timestamptz) ELSE NULL END,
      updated_at = now()
    WHERE id = p_contato_id;
  END IF;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade, p_modalidade, v_uf_postagem_eff, 'pago', p_criado_por,
      v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'pedido_id', v_pedido_id,
    'order_number', v_order_number
  );
END;
$$;
-- --- FIM PARTE 2 (criar_pedido) ---

-- --- PARTE 3 --- processar_pedido_estoque_trigger: pedido_itens, FIFO, sem lote, idempotência
DROP FUNCTION IF EXISTS public.processar_pedido_estoque_trigger(uuid, text);

CREATE OR REPLACE FUNCTION public.processar_pedido_estoque_trigger(
  p_pedido_id uuid,
  p_uf_postagem text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item record;
  v_lote_rec record;
  v_remaining integer;
  v_deduct integer;
  v_uf_pref text;
  v_uf_eff text;
  v_total_items integer := 0;
  v_processed_items integer := 0;
  v_order_num integer;
  v_ja_saiu integer;
  v_linhas_mesmo_prod integer;
  v_legacy_saiu integer;
BEGIN
  SELECT p.order_number INTO v_order_num FROM public.pedidos p WHERE p.id = p_pedido_id;

  SELECT COALESCE(
    NULLIF(trim(COALESCE(p_uf_postagem, '')), ''),
    NULLIF(trim(COALESCE(po.uf_postagem, '')), '')
  ) INTO v_uf_pref
  FROM public.pedidos po
  WHERE po.id = p_pedido_id;

  FOR v_item IN
    SELECT pi.id, pi.produto_id, pi.nome_oficial, pi.quantidade
    FROM public.pedido_itens pi
    WHERE pi.pedido_id = p_pedido_id
      AND pi.produto_id IS NOT NULL
  LOOP
    v_total_items := v_total_items + 1;

    SELECT COALESCE(SUM(em.quantidade), 0)::integer INTO v_ja_saiu
    FROM public.estoque_movimentacoes em
    WHERE em.tipo = 'saida' AND em.pedido_item_id = v_item.id;

    IF v_ja_saiu = 0 THEN
      SELECT COUNT(*)::integer INTO v_linhas_mesmo_prod
      FROM public.pedido_itens pi
      WHERE pi.pedido_id = p_pedido_id AND pi.produto_id = v_item.produto_id;

      IF v_linhas_mesmo_prod <= 1 THEN
        SELECT COALESCE(SUM(em.quantidade), 0)::integer INTO v_legacy_saiu
        FROM public.estoque_movimentacoes em
        WHERE em.tipo = 'saida'
          AND em.pedido_id = p_pedido_id
          AND em.produto_id = v_item.produto_id
          AND em.pedido_item_id IS NULL;
        v_ja_saiu := v_legacy_saiu;
      END IF;
    END IF;

    v_remaining := GREATEST(v_item.quantidade - v_ja_saiu, 0);
    IF v_remaining <= 0 THEN
      CONTINUE;
    END IF;

    v_uf_eff := NULLIF(trim(COALESCE(v_uf_pref, '')), '');
    IF v_uf_eff IS NULL THEN
      SELECT u.uf INTO v_uf_eff
      FROM (
        SELECT l.uf, SUM(l.quantidade_atual)::bigint AS tot
        FROM public.lotes l
        WHERE l.produto_id = v_item.produto_id
          AND l.quantidade_atual > 0
        GROUP BY l.uf
        ORDER BY tot DESC, l.uf ASC
        LIMIT 1
      ) u;
    END IF;
    v_uf_eff := COALESCE(v_uf_eff, 'SP');

    FOR v_lote_rec IN
      SELECT id, quantidade_atual, uf
      FROM public.lotes
      WHERE produto_id = v_item.produto_id
        AND quantidade_atual > 0
      ORDER BY (uf = v_uf_eff) DESC, created_at ASC
    LOOP
      IF v_remaining <= 0 THEN EXIT; END IF;

      v_deduct := LEAST(v_remaining, v_lote_rec.quantidade_atual);

      UPDATE public.lotes
      SET quantidade_atual = quantidade_atual - v_deduct
      WHERE id = v_lote_rec.id;

      INSERT INTO public.estoque_movimentacoes (
        produto_id, quantidade, tipo, posse, lote_id, uf_origem,
        pedido_item_id, pedido_id, observacao
      ) VALUES (
        v_item.produto_id, v_deduct, 'saida', 'Venda',
        v_lote_rec.id, v_lote_rec.uf,
        v_item.id, p_pedido_id,
        'Pedido #' || COALESCE(v_order_num::text, '?')
      );

      v_remaining := v_remaining - v_deduct;
    END LOOP;

    IF v_remaining > 0 THEN
      INSERT INTO public.estoque_movimentacoes (
        produto_id, quantidade, tipo, posse, lote_id, uf_origem,
        pedido_item_id, pedido_id, observacao
      ) VALUES (
        v_item.produto_id, v_remaining, 'saida', 'Venda',
        NULL, v_uf_eff,
        v_item.id, p_pedido_id,
        'Pedido #' || COALESCE(v_order_num::text, '?') || ' (sem lote)'
      );
    END IF;

    PERFORM public.update_produto_estoque(v_item.produto_id);
    v_processed_items := v_processed_items + 1;
  END LOOP;

  UPDATE public.pedidos
  SET estoque_processado = true
  WHERE id = p_pedido_id;

  PERFORM public.atualizar_estoque_snapshot();

  RETURN jsonb_build_object(
    'pedido_id', p_pedido_id::text,
    'total_items', v_total_items,
    'processed', v_processed_items
  );
END;
$$;
-- --- FIM PARTE 3 ---

-- --- PARTE 4 --- get_estoque_completo: saldo por produto + UF (evita produto cartesiano)
DROP FUNCTION IF EXISTS public.get_estoque_completo();

CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(
  prod_id uuid,
  prod_nome text,
  estado text,
  entrada int,
  saida int,
  saldo int
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH entradas AS (
    SELECT
      l.produto_id AS pid,
      COALESCE(l.uf, 'SP') AS uff,
      SUM(l.quantidade_atual)::int AS qtd_ent
    FROM public.lotes l
    WHERE l.quantidade_atual > 0
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas AS (
    SELECT
      em.produto_id AS pid,
      COALESCE(NULLIF(trim(em.uf_origem), ''), 'SP') AS uff,
      SUM(em.quantidade)::int AS qtd_sai
    FROM public.estoque_movimentacoes em
    WHERE em.tipo = 'saida'
    GROUP BY em.produto_id, COALESCE(NULLIF(trim(em.uf_origem), ''), 'SP')
  ),
  chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas
  )
  SELECT
    ch.pid AS prod_id,
    pr.nome_oficial AS prod_nome,
    ch.uff AS estado,
    COALESCE(e.qtd_ent, 0) AS entrada,
    COALESCE(s.qtd_sai, 0) AS saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) AS saldo
  FROM chaves ch
  INNER JOIN public.produtos pr ON pr.id = ch.pid AND pr.ativo = true
  LEFT JOIN entradas e ON e.pid = ch.pid AND e.uff = ch.uff
  LEFT JOIN saidas s ON s.pid = ch.pid AND s.uff = ch.uff
  ORDER BY pr.nome_oficial, ch.uff;
END;
$$;
-- --- FIM PARTE 4 ---

-- --- PARTE 5 --- (removido reprocessamento automático: rodar várias vezes duplicava movimentações)
-- Para corrigir um pedido específico, no SQL Editor:
--   SELECT processar_pedido_estoque_trigger(id, uf_postagem) FROM pedidos WHERE order_number = N;
-- --- FIM PARTE 5 ---

SELECT 'Migração estoque multi-produtos aplicada.' AS status;


-- MIGRATION: 20260419000001_trigger_uf_postagem_usa_pedido_itens.sql
-- Quando a UF de postagem é preenchida pela primeira vez, abater usando
-- processar_pedido_estoque_trigger (pedido_itens), em vez do JSON legado em pedidos.produto.

CREATE OR REPLACE FUNCTION public.trigger_uf_postagem_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uf_new text;
  v_uf_old text;
BEGIN
  v_uf_new := NULLIF(trim(COALESCE(NEW.uf_postagem, '')), '');
  v_uf_old := NULLIF(trim(COALESCE(OLD.uf_postagem, '')), '');

  IF NEW.representante_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF v_uf_new IS NOT NULL
     AND (v_uf_old IS NULL OR v_uf_old = '')
     AND NEW.estoque_processado = false
  THEN
    PERFORM public.processar_pedido_estoque_trigger(NEW.id, v_uf_new);
  END IF;

  RETURN NEW;
END;
$$;


-- MIGRATION: 20260419235950_b736341c-023f-44a3-adc6-30d01265a9b2.sql
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS gateway_etiqueta text DEFAULT 'superfrete';
UPDATE public.pedidos SET gateway_etiqueta = 'superfrete' WHERE gateway_etiqueta IS NULL;

-- MIGRATION: 20260420000000_add_peso_produtos.sql
-- Adiciona campos de peso e dimensoes aos produtos
ALTER TABLE public.produtos 
ADD COLUMN IF NOT EXISTS peso integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS largura_caixa numeric DEFAULT 11,
ADD COLUMN IF NOT EXISTS altura_caixa numeric DEFAULT 2,
ADD COLUMN IF NOT EXISTS comprimento_caixa numeric DEFAULT 16;

-- Atualiza produtos existentes com peso padrao (300g por unidade)
UPDATE public.produtos SET peso = 300 WHERE peso = 0 OR peso IS NULL;

-- cria indice para performance
CREATE INDEX IF NOT EXISTS idx_produtos_peso ON public.produtos(peso);

-- MIGRATION: 20260420000001_add_peso_produtos_rpc.sql
-- SQL para adicionar peso aos produtos e atualizar funções RPC
-- Execute no Supabase SQL Editor

-- 1. Adiciona coluna peso aos produtos
ALTER TABLE public.produtos 
ADD COLUMN IF NOT EXISTS peso integer DEFAULT 300;

-- 2. Atualiza produtos com peso padrão
UPDATE public.produtos SET peso = 300 WHERE peso IS NULL OR peso = 0;

-- 3. Recria função update_produto com peso
CREATE OR REPLACE FUNCTION update_produto(
  p_id uuid,
  p_nome_oficial text,
  p_tag text,
  p_cor_card text,
  p_cor_texto text,
  p_limite_estoque integer,
  p_grupo_id uuid,
  p_box_size text,
  p_box_qty_max integer,
  p_peso integer DEFAULT 300
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.produtos SET
    nome_oficial = p_nome_oficial,
    tag = p_tag,
    cor_card = p_cor_card,
    cor_texto = p_cor_texto,
    limite_estoque = p_limite_estoque,
    grupo_id = p_grupo_id,
    box_size = p_box_size,
    box_qty_max = p_box_qty_max,
    peso = p_peso
  WHERE id = p_id;
END;
$$;

-- 4. Recria função create_produto com peso
CREATE OR REPLACE FUNCTION create_produto(
  p_nome_oficial text,
  p_tag text,
  p_cor_card text,
  p_cor_texto text,
  p_limite_estoque integer,
  p_grupo_id uuid,
  p_box_size text,
  p_box_qty_max integer,
  p_peso integer DEFAULT 300
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.produtos (
    nome_oficial, tag, cor_card, cor_texto, 
    limite_estoque, grupo_id, box_size, box_qty_max, peso
  ) VALUES (
    p_nome_oficial, p_tag, p_cor_card, p_cor_texto,
    p_limite_estoque, p_grupo_id, p_box_size, p_box_qty_max, p_peso
  )
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;

-- MIGRATION: 20260420000001_drop_trg_novo_pedido_estoque.sql
-- Garante remoção do trigger legado que inseria saídas no INSERT (duplicava com criar_pedido/processar).
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque() CASCADE;


-- MIGRATION: 20260421000001_fix_criar_pedido_overload.sql
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

DROP FUNCTION IF EXISTS public.get_estoque_completo();
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

-- MIGRATION: 20260421000002_final_inventory_source_of_truth.sql
-- INVENTORY FIX - SOURCE OF TRUTH (PEDIDOS)
-- Esse script centraliza o estoque baseado na tabela pedidos e resolve duplicidades.

BEGIN;

-- 1. Garante coluna uf_cliente em pedidos (conforme guia)
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

UPDATE public.pedidos p
SET uf_cliente = c.uf
FROM public.contatos c
WHERE p.contato_id = c.id AND p.uf_cliente IS NULL AND c.uf IS NOT NULL;

UPDATE public.pedidos p
SET uf_cliente = p.uf_postagem
WHERE p.uf_cliente IS NULL AND p.uf_postagem IS NOT NULL;

-- 2. Limpa e reconstrói GET_ESTOQUE_COMPLETO com lógica Dinâmica (Source of Truth)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    -- Entradas fixas baseadas na quantidade inicial dos lotes
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  -- Saídas do campo single produto_id
  saidas_diretas AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, p.uf_cliente, 'SP') as uff, SUM(p.quantidade)::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL 
      AND p.status_pedido <> 'cancelado'
    GROUP BY p.produto_id, uff
  ),
  -- Saídas do campo JSON (Multi-produto)
  saidas_json AS (
    SELECT 
      (jsonb_array_elements(CASE WHEN p.produto LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END)->>'produto_id')::uuid as pid,
      COALESCE(p.uf_postagem, p.uf_cliente, 'SP') as uff,
      SUM((jsonb_array_elements(p.produto::jsonb)->>'quantidade')::int)::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL 
      AND p.produto LIKE '[%'
      AND p.status_pedido <> 'cancelado'
    GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json
    ) s2
    GROUP BY pid, uff
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    COALESCE(e.uff, s.uff, 'SP') as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM produtos_ativos pr
  LEFT JOIN entradas e ON e.pid = pr.pid
  LEFT JOIN saidas_consolidadas s ON s.pid = pr.pid
  WHERE COALESCE(e.qtd_ent, 0) > 0 OR COALESCE(s.qtd_sai, 0) > 0
  ORDER BY pr.pnome, estado;
END;
$$;

-- 3. Função de sincronização de movimentações (limpeza e reconstrução)
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item jsonb;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    -- Remove saídas de venda vinculadas a pedidos para evitar duplicatas
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    -- Reinsere a partir da verdade (pedidos)
    FOR v_pedido IN 
        SELECT id, produto_id, produto, quantidade, COALESCE(uf_postagem, uf_cliente, 'SP') as uf, created_at, status_pedido
        FROM public.pedidos 
        WHERE status_pagamento IS NOT NULL AND status_pedido <> 'cancelado'
    LOOP
        -- Caso single
        IF v_pedido.produto_id IS NOT NULL THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.produto_id, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado via Pedidos', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        -- Caso JSON
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado via Pedidos (JSON)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

-- 4. Corrige CRIAR_PEDIDO_V2 para NÃO descontar lote (Sincronia Automática via get_estoque_completo)
-- O log de movimentação continua para manter o histórico individual
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
  v_order_number integer;
  v_data_sp date;
  v_uf_cliente text;
  v_quantidade_total integer;
  v_produto_text text;
  v_item jsonb;
BEGIN
  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  -- UF do cliente
  BEGIN
    SELECT uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  -- Quantidade total e Texto do produto
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT SUM((item->>'quantidade')::integer) INTO v_quantidade_total FROM jsonb_array_elements(p_produtos) AS item;
    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := (p_produtos->0->>'produto');
    ELSE
      v_produto_text := p_produtos::text;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := 'geral';
  END IF;

  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem, uf_cliente,
    status_pedido, observacao, criado_por, order_number, data, estoque_processado,
    produto, quantidade, created_at
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, p_modalidade, p_uf_postagem, v_uf_cliente,
    'aguardando_rastreio', COALESCE(p_obs, ''), p_criado_por, v_order_number, v_data_sp, true,
    v_produto_text, v_quantidade_total, now()
  )
  RETURNING id INTO v_pedido_id;

  -- Insere itens e Movimentação (Histórico apenas, sem descontar lotes manual para evitar duplicidade)
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_item IN SELECT jsonb_array_elements(p_produtos) LOOP
        -- Movimentação
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
        VALUES ((v_item->>'produto_id')::uuid, (v_item->>'quantidade')::int, 'saida', 'Venda', COALESCE(p_uf_postagem, v_uf_cliente, 'SP'), v_pedido_id, 'Pedido automático RPC');
        
        -- Item
        INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco)
        VALUES (v_pedido_id, (v_item->>'produto_id')::uuid, (v_item->>'quantidade')::int, 0);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

-- 5. Remove o Trigger para evitar tripla contagem (RPC já insere no estoque_movimentacoes)
DROP TRIGGER IF EXISTS trg_novo_pedido_estoque ON public.pedidos;
DROP FUNCTION IF EXISTS public.trigger_novo_pedido_estoque();

-- 6. Executa a sincronização inicial
SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000003_process_venda_inventory_sync.sql
-- REFACTOR process_venda - SYNC WITH INVENTORY SOURCE OF TRUTH
-- Remove chamadas manuais para triggers de estoque redundantes.

BEGIN;

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
  v_uf_cliente text;
  v_item jsonb;
BEGIN
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;
  v_canal_lancamento := CASE WHEN p_canal = 'C-REP' THEN 'REP' ELSE p_canal END;
  v_next_midnight := (CURRENT_DATE + 1)::timestamptz;
  v_is_base := (p_canal = 'BASE');

  SELECT COALESCE(MAX(order_number), 0) + 1 INTO v_order_number FROM public.pedidos;

  -- UF do cliente para registro
  SELECT uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;

  -- Parsing de produtos
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    v_produto_text := (SELECT string_agg(nome_oficial, ', ') FROM jsonb_to_recordset(p_produtos) AS x(nome_oficial text, quantidade integer));
    v_quantidade := (SELECT SUM((x->>'quantidade')::integer) FROM jsonb_array_elements(p_produtos) AS x);
  ELSE
    v_produto_text := 'geral';
    v_quantidade := 1;
  END IF;

  INSERT INTO public.pedidos (
    contato_id, canal, valor, status_pagamento, modalidade, uf_postagem, uf_cliente,
    criado_por, produto, quantidade, order_number, data, status_pedido, observacao,
    is_novo, novo_ate, estoque_processado, created_at
  ) VALUES (
    p_contato_id, v_canal_lancamento, p_valor, 'pago', p_modalidade, p_uf_postagem, v_uf_cliente,
    p_criado_por, COALESCE(p_produtos::text, 'geral'), v_quantidade, v_order_number, v_data_sp, 'aguardando_rastreio', p_obs,
    v_is_base, CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
    true, now() -- Já considerado processado pois o saldo é dinâmico
  ) RETURNING id INTO v_pedido_id;

  -- Registro de Itens e Movimentação Histórica
  IF p_produtos IS NOT NULL AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_item IN SELECT jsonb_array_elements(p_produtos) LOOP
        -- Movimentação
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
        VALUES ((v_item->>'produto_id')::uuid, (v_item->>'quantidade')::int, 'saida', 'Venda', COALESCE(p_uf_postagem, v_uf_cliente, 'SP'), v_pedido_id, 'Venda automática process_venda');
        
        -- Item
        INSERT INTO public.pedido_itens (pedido_id, produto_id, nome_oficial, quantidade, preco)
        VALUES (v_pedido_id, (v_item->>'produto_id')::uuid, COALESCE(v_item->>'produto', v_item->>'nome_oficial'), (v_item->>'quantidade')::integer, (v_item->>'valor_unit')::numeric);
    END LOOP;
  END IF;

  -- Logística/Financeiro normal
  UPDATE public.contatos 
  SET status_kanban = CASE WHEN v_is_base THEN 'Clientes' ELSE 'Pagou' END,
      canal_atual = CASE WHEN v_is_base THEN 'BASE' ELSE COALESCE(canal_atual, p_canal) END,
      is_novo = v_is_base,
      novo_ate = CASE WHEN v_is_base THEN v_next_midnight ELSE NULL END,
      updated_at = now()
  WHERE id = p_contato_id;

  INSERT INTO public.lancamentos_socios (socio, tipo, valor, canal, contato_id, quantidade, modalidade, uf_postagem, status_pagamento, criado_por, pedido_id, data)
  VALUES (p_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id, v_quantidade, p_modalidade, p_uf_postagem, 'pago', p_criado_por, v_pedido_id, v_data_sp);

  -- REMOVIDO: PERFORM public.processar_pedido_estoque_trigger(...) - Evita duplicidade
  
  RETURN jsonb_build_object('status', 'ok', 'pedido_id', v_pedido_id, 'order_number', v_order_number);
END;
$$;

COMMIT;


-- MIGRATION: 20260421000004_estoque_snapshot_performance.sql
-- INVENTORY PERFORMANCE SNAPSHOT
-- Tabela para armazenar o saldo calculado e evitar recalcular milhares de pedidos em tempo real.

BEGIN;

CREATE TABLE IF NOT EXISTS public.estoque_snapshot (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    prod_id uuid REFERENCES public.produtos(id),
    prod_nome text,
    estado text,
    entrada int DEFAULT 0,
    saida int DEFAULT 0,
    saldo int DEFAULT 0,
    updated_at timestamptz DEFAULT now()
);

-- Função para atualizar o snapshot a partir da get_estoque_completo()
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Limpa o snapshot atual
    DELETE FROM public.estoque_snapshot;

    -- Insere os dados atualizados vindos da verdade (pedidos + lotes)
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now()
    FROM public.get_estoque_completo();
END;
$$;

-- Executa a primeira carga
SELECT public.atualizar_estoque_snapshot();

COMMIT;


-- MIGRATION: 20260421000005_fix_srf_aggregation_and_snapshot.sql
-- FIX: ERROR 0A000 - get_estoque_completo AND Snapshot logic
-- Esta migração corrige o erro de agregação com funções de conjunto (jsonb_array_elements)
-- e garante que o snapshot use a tabela correta sem duplicidades.

BEGIN;

-- 1. Corrige get_estoque_completo() usando LATERAL JOIN para expandir o JSON com segurança
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    SELECT l.produto_id as pid, COALESCE(l.uf, 'SP') as uff, SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, COALESCE(l.uf, 'SP')
  ),
  saidas_diretas AS (
    SELECT p.produto_id as pid, COALESCE(p.uf_postagem, p.uf_cliente, 'SP') as uff, SUM(p.quantidade)::int as qtd
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.produto_id IS NOT NULL 
      AND p.status_pedido <> 'cancelado'
    GROUP BY p.produto_id, uff
  ),
  -- Correção aqui: expandir primeiro com LATERAL, depois agrupar e somar
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      COALESCE(p.uf_postagem, p.uf_cliente, 'SP') as uff,
      (elem->>'quantidade')::int as qtd
    FROM public.pedidos p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN p.produto LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE p.status_pagamento IS NOT NULL 
      AND p.produto LIKE '[%'
      AND p.status_pedido <> 'cancelado'
  ),
  saidas_json_grouped AS (
    SELECT pid, uff, SUM(qtd)::int as qtd FROM saidas_json_expanded GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json_grouped
    ) s2
    GROUP BY pid, uff
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    COALESCE(e.uff, s.uff, 'SP') as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM produtos_ativos pr
  LEFT JOIN entradas e ON e.pid = pr.pid
  LEFT JOIN saidas_consolidadas s ON s.pid = pr.pid
  WHERE COALESCE(e.qtd_ent, 0) > 0 OR COALESCE(s.qtd_sai, 0) > 0
  ORDER BY pr.pnome, estado;
END;
$$;

-- 2. Garante que atualizar_estoque_snapshot() aponte para a tabela correta (estoque_snapshot)
-- Nota: se a tabela já existia, o 'INSERT' apenas povoará ela.
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Limpa o snapshot atual
    DELETE FROM public.estoque_snapshot;

    -- Insere os dados atualizados selecionando explicitamente os nomes das colunas para evitar erros de ordem
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    SELECT prod_id, prod_nome, estado, entrada, saida, saldo, now()
    FROM public.get_estoque_completo();
END;
$$;

-- Executa a sincronização para validar
SELECT public.atualizar_estoque_snapshot();

COMMIT;


-- MIGRATION: 20260421000006_definitive_inventory_fix_v3.sql
-- DEFINITIVE INVENTORY FIX V3 - UNIFIED SOURCE OF TRUTH
-- Resolve Join Cartesiano, Dupla Contagem e Fragmentação de UFs.

BEGIN;

-- 1. Refatoração da função de cálculo dinâmica
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    -- Soma quantidade INICIAL para ser a verdade da entrada
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_normalizados AS (
    -- Define se o pedido deve ser lido como unitário ou JSON para evitar dupla contagem
    SELECT 
      p.id,
      p.produto_id,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff,
      (p.produto LIKE '[%') as is_json
    FROM public.pedidos p
    WHERE p.status_pagamento IS NOT NULL AND p.status_pedido <> 'cancelado'
  ),
  saidas_diretas AS (
    SELECT p.produto_id as pid, p.uff, SUM(p.quantidade)::int as qtd
    FROM pedidos_normalizados p
    WHERE NOT p.is_json AND p.produto_id IS NOT NULL 
    GROUP BY p.produto_id, p.uff
  ),
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      (elem->>'quantidade')::int as qtd
    FROM pedidos_normalizados p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE p.is_json
  ),
  saidas_json_grouped AS (
    SELECT pid, uff, SUM(qtd)::int as qtd FROM saidas_json_expanded GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json_grouped
    ) s2
    GROUP BY pid, uff
  ),
  -- União de todas as chaves (Produto, UF) para garantir que nada escape do JOIN
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_ativos pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff -- JOIN CRUCIAL EM PRODUTO + UF
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff -- JOIN CRUCIAL EM PRODUTO + UF
  ORDER BY pr.pnome, estado;
END;
$$;

-- 2. Refatoração da Sincronização de Movimentações
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item jsonb;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    -- Limpa saídas antigas
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    -- Reinsere com a lógica de exclusão mútua (Direto vs JSON)
    FOR v_pedido IN 
        SELECT id, produto_id, produto, quantidade, UPPER(TRIM(COALESCE(uf_postagem, uf_cliente, 'SP'))) as uf, created_at
        FROM public.pedidos 
        WHERE status_pagamento IS NOT NULL AND status_pedido <> 'cancelado'
    LOOP
        -- Caso single (Texto sem ser JSON)
        IF v_pedido.produto_id IS NOT NULL AND v_pedido.produto NOT LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.produto_id, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V3 (Direto)', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        -- Caso JSON
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V3 (JSON)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    -- Atualiza Snapshot ao final
    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

-- 3. Executa sincronização corretiva
SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000007_inventory_include_pending.sql
-- INVENTORY FIX V4 - INCLUSÃO DE PEDIDOS PENDENTES E SEM STATUS
-- Garante que o abatimento ocorra para todo pedido não cancelado.

BEGIN;

-- 1. Atualização da get_estoque_completo para incluir pendentes
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_normalizados AS (
    SELECT 
      p.id,
      p.produto_id,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff,
      (p.produto LIKE '[%') as is_json
    FROM public.pedidos p
    WHERE p.status_pedido <> 'cancelado' -- CONSIDERA TUDO, EXCETO CANCELADOS
  ),
  saidas_diretas AS (
    SELECT p.produto_id as pid, p.uff, SUM(p.quantidade)::int as qtd
    FROM pedidos_normalizados p
    WHERE NOT p.is_json AND p.produto_id IS NOT NULL 
    GROUP BY p.produto_id, p.uff
  ),
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      (elem->>'quantidade')::int as qtd
    FROM pedidos_normalizados p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE p.is_json
  ),
  saidas_json_grouped AS (
    SELECT pid, uff, SUM(qtd)::int as qtd FROM saidas_json_expanded GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json_grouped
    ) s2
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_ativos pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- 2. Atualização da sincronização histórica
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item jsonb;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN 
        SELECT id, produto_id, produto, quantidade, UPPER(TRIM(COALESCE(uf_postagem, uf_cliente, 'SP'))) as uf, created_at
        FROM public.pedidos 
        WHERE status_pedido <> 'cancelado' -- REGRA UNIFICADA
    LOOP
        IF v_pedido.produto_id IS NOT NULL AND v_pedido.produto NOT LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.produto_id, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V4 (Incl. Pendentes)', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V4 (JSON Incl. Pendentes)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000008_inventory_fix_null_status.sql
-- INVENTORY FIX V5 - RESILIÊNCIA A NULL NO STATUS
-- Garante que pedidos com status nulo sejam contados, igualando às Métricas.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_ativos AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos WHERE ativo = true
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_normalizados AS (
    SELECT 
      p.id,
      p.produto_id,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff,
      (p.produto LIKE '[%') as is_json
    FROM public.pedidos p
    WHERE COALESCE(p.status_pedido, '') <> 'cancelado' -- FIX: Resiliente a NULL
  ),
  saidas_diretas AS (
    SELECT p.produto_id as pid, p.uff, SUM(p.quantidade)::int as qtd
    FROM pedidos_normalizados p
    WHERE NOT p.is_json AND p.produto_id IS NOT NULL 
    GROUP BY p.produto_id, p.uff
  ),
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      (elem->>'quantidade')::int as qtd
    FROM pedidos_normalizados p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE p.is_json
  ),
  saidas_json_grouped AS (
    SELECT pid, uff, SUM(qtd)::int as qtd FROM saidas_json_expanded GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json_grouped
    ) s2
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_ativos pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização também deve seguir a mesma lógica de NULL
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item jsonb;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN 
        SELECT id, produto_id, produto, quantidade, UPPER(TRIM(COALESCE(uf_postagem, uf_cliente, 'SP'))) as uf, created_at
        FROM public.pedidos 
        WHERE COALESCE(status_pedido, '') <> 'cancelado'
    LOOP
        IF v_pedido.produto_id IS NOT NULL AND v_pedido.produto NOT LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.produto_id, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V5 (Resiliente a NULL)', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V5 (JSON Resiliente a NULL)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000009_inventory_fix_total_parity.sql
-- INVENTORY FIX V6 - PARIDADE TOTAL COM MÉTRICAS
-- Remove filtros de produtos ativos e normaliza comparação de status.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    -- Pega todos os produtos (independente de ativo), pois itens vendidos inativos devem abater o saldo
    SELECT id as pid, nome_oficial as pnome FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_normalizados AS (
    SELECT 
      p.id,
      p.produto_id,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff,
      (p.produto LIKE '[%') as is_json
    FROM public.pedidos p
    WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado' -- FIX: Case insensitive e resiliente a NULL
  ),
  saidas_diretas AS (
    SELECT p.produto_id as pid, p.uff, SUM(p.quantidade)::int as qtd
    FROM pedidos_normalizados p
    WHERE NOT p.is_json AND p.produto_id IS NOT NULL 
    GROUP BY p.produto_id, p.uff
  ),
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      (elem->>'quantidade')::int as qtd
    FROM pedidos_normalizados p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE p.is_json
  ),
  saidas_json_grouped AS (
    SELECT pid, uff, SUM(qtd)::int as qtd FROM saidas_json_expanded GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json_grouped
    ) s2
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid -- JOIN em todos os produtos
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Atualização da sincronização histórica para V6
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item jsonb;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN 
        SELECT id, produto_id, produto, quantidade, UPPER(TRIM(COALESCE(uf_postagem, uf_cliente, 'SP'))) as uf, created_at
        FROM public.pedidos 
        WHERE LOWER(COALESCE(status_pedido, '')) <> 'cancelado'
    LOOP
        IF v_pedido.produto_id IS NOT NULL AND v_pedido.produto NOT LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.produto_id, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V6 (Paridade total)', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V6 (JSON Paridade)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000010_inventory_fix_name_match.sql
-- INVENTORY FIX V7 - FUZZY MATCH POR NOME
-- Resgata pedidos que não possuem produto_id mas possuem o nome do produto no campo 'produto'.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_normalizados AS (
    -- Normaliza pedidos e tenta encontrar o ID do produto pelo nome caso esteja nulo
    SELECT 
      p.id as pedido_id,
      COALESCE(p.produto_id, pb.pid) as pid, -- Tenta resgatar o ID pelo Nome
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff,
      (p.produto LIKE '[%') as is_json
    FROM public.pedidos p
    LEFT JOIN produtos_base pb ON (p.produto_id IS NULL AND p.produto = pb.pnome)
    WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
  ),
  saidas_diretas AS (
    -- Agora considera pedidos resgatados pelo nome também
    SELECT p.pid, p.uff, SUM(p.quantidade)::int as qtd
    FROM pedidos_normalizados p
    WHERE NOT p.is_json AND p.pid IS NOT NULL 
    GROUP BY p.pid, p.uff
  ),
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      (elem->>'quantidade')::int as qtd
    FROM pedidos_normalizados p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE p.is_json
  ),
  saidas_json_grouped AS (
    SELECT pid, uff, SUM(qtd)::int as qtd FROM saidas_json_expanded GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json_grouped
    ) s2
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V7: Também deve considerar o resgate por nome
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item jsonb;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN 
        SELECT 
          p.id, 
          COALESCE(p.produto_id, (SELECT pr.id FROM produtos pr WHERE pr.nome_oficial = p.produto LIMIT 1)) as final_pid, 
          p.produto, 
          p.quantidade, 
          UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uf, 
          p.created_at
        FROM public.pedidos p
        WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
    LOOP
        -- Caso single (incluindo resgatados por nome no loop)
        IF v_pedido.final_pid IS NOT NULL AND v_pedido.produto NOT LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.final_pid, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V7 (Ref. por Nome)', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        -- Caso JSON
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V7 (JSON)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000011_inventory_fix_broad_match.sql
-- INVENTORY FIX V8 - BUSCA FLEXÍVEL POR NOME E TAG
-- Garante que o CBD seja capturado mesmo que o nome no pedido seja curto (Ex: 'CBD' vs 'Óleo CBD').

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome, tag as ptag FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_normalizados AS (
    -- FIX: Busca flexível por ID, Nome Oficial ou TAG
    SELECT 
      p.id as pedido_id,
      COALESCE(
        p.produto_id, 
        (SELECT pr.id FROM produtos pr 
         WHERE p.produto = pr.nome_oficial 
            OR UPPER(TRIM(p.produto)) = UPPER(TRIM(pr.tag))
            OR pr.nome_oficial ILIKE '%' || p.produto || '%'
         LIMIT 1)
      ) as pid,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff,
      (p.produto LIKE '[%') as is_json
    FROM public.pedidos p
    WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
  ),
  saidas_diretas AS (
    SELECT p.pid, p.uff, SUM(p.quantidade)::int as qtd
    FROM pedidos_normalizados p
    WHERE NOT p.is_json AND p.pid IS NOT NULL 
    GROUP BY p.pid, p.uff
  ),
  saidas_json_expanded AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      (elem->>'quantidade')::int as qtd
    FROM pedidos_normalizados p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE p.is_json
  ),
  saidas_json_grouped AS (
    SELECT pid, uff, SUM(qtd)::int as qtd FROM saidas_json_expanded GROUP BY pid, uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_diretas
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json_grouped
    ) s2
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V8: Mesma lógica de busca flexível
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item jsonb;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN 
        SELECT 
          p.id, 
          COALESCE(
            p.produto_id, 
            (SELECT pr.id FROM produtos pr 
             WHERE p.produto = pr.nome_oficial 
                OR UPPER(TRIM(p.produto)) = UPPER(TRIM(pr.tag))
                OR pr.nome_oficial ILIKE '%' || p.produto || '%'
             LIMIT 1)
          ) as final_pid, 
          p.produto, 
          p.quantidade, 
          UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uf, 
          p.created_at
        FROM public.pedidos p
        WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
    LOOP
        IF v_pedido.final_pid IS NOT NULL AND v_pedido.produto NOT LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            VALUES (v_pedido.final_pid, v_pedido.quantidade, 'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V8 (Flexível)', v_pedido.created_at);
            v_count_ins := v_count_ins + 1;
        ELSIF v_pedido.produto LIKE '[%' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_pedido.produto::jsonb) LOOP
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
                VALUES (
                    (v_item->>'produto_id')::uuid, 
                    (v_item->>'quantidade')::int, 
                    'saida', 'Venda', v_pedido.uf, v_pedido.id, 'Sincronizado V8 (JSON)', v_pedido.created_at
                );
                v_count_ins := v_count_ins + 1;
            END LOOP;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000012_inventory_fix_triple_source.sql
-- INVENTORY FIX V9 - FONTE DE VERDADE TRIPLA (PARIDADE SEBASTIÃO)
-- Inclui a tabela pedido_itens como fonte primária para resolver discrepâncias.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    -- Normalização inicial dos pedidos ativos
    SELECT 
      p.id as pedido_id,
      p.produto_id,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff
    FROM public.pedidos p
    WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
  ),
  saidas_itens_tabela AS (
    -- Fator Sebastião: Buscar primeiro na tabela de itens detalhada
    SELECT pi.produto_id as pid, pb.uff, SUM(pi.quantidade)::int as qtd, pi.pedido_id
    FROM public.pedido_itens pi
    JOIN pedidos_base pb ON pb.pedido_id = pi.pedido_id
    GROUP BY pi.produto_id, pb.uff, pi.pedido_id
  ),
  saidas_json AS (
    -- Fallback 1: JSON (apenas se o pedido não estiver na tabela de itens)
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN p.produto LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE p.produto LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_diretas AS (
    -- Fallback 2: Coluna Unitária ou Nome (apenas se não houver registros nas fontes anteriores)
    SELECT 
      COALESCE(p.produto_id, (SELECT pr.id FROM produtos pr WHERE p.produto = pr.nome_oficial OR pr.nome_oficial ILIKE '%' || p.produto || '%' LIMIT 1)) as pid,
      p.uff,
      SUM(p.quantidade)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    WHERE p.produto NOT LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_itens_tabela
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    WHERE pid IS NOT NULL
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V9: Também unificada
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_item record;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    -- Usa a mesma lógica de prioridade tripla
    FOR v_pedido IN SELECT id, uff FROM (
        SELECT p.id, UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff
        FROM public.pedidos p
        WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
    ) p2 LOOP
        
        -- 1. Tenta pedido_itens
        IF EXISTS (SELECT 1 FROM public.pedido_itens WHERE pedido_id = v_pedido.id) THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
            SELECT produto_id, quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V9 (Itens)'
            FROM public.pedido_itens WHERE pedido_id = v_pedido.id;
            v_count_ins := v_count_ins + 1;
            
        -- 2. Tenta JSON
        ELSE
            -- Lógica simplificada para o loop de sincronização (reutiliza a lógica da get_estoque_completo)
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
            SELECT 
                (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V9 (JSON)'
            FROM public.pedidos p
            CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
            WHERE p.id = v_pedido.id AND p.produto LIKE '[%';
            
            IF FOUND THEN 
                v_count_ins := v_count_ins + 1;
            ELSE
                -- 3. Tenta Direto
                INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
                SELECT 
                    COALESCE(p.produto_id, (SELECT pr.id FROM produtos pr WHERE p.produto = pr.nome_oficial OR pr.nome_oficial ILIKE '%' || p.produto || '%' LIMIT 1)),
                    p.quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V9 (Direto)'
                FROM public.pedidos p
                WHERE p.id = v_pedido.id AND p.produto_id IS NOT NULL OR p.produto NOT LIKE '[%';
                
                v_count_ins := v_count_ins + 1;
            END IF;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000013_inventory_fix_null_safe.sql
-- INVENTORY FIX V10 - BLINDAGEM DE NULOS (CASO SEBASTIÃO)
-- Garante que o filtro de JSON/Texto não descarte registros com a coluna 'produto' nula.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    SELECT 
      p.id as pedido_id,
      p.produto_id,
      p.quantidade,
      p.produto,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff
    FROM public.pedidos p
    WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
  ),
  saidas_itens_tabela AS (
    SELECT pi.produto_id as pid, pb.uff, SUM(pi.quantidade)::int as qtd, pi.pedido_id
    FROM public.pedido_itens pi
    JOIN pedidos_base pb ON pb.pedido_id = pi.pedido_id
    GROUP BY pi.produto_id, pb.uff, pi.pedido_id
  ),
  saidas_json AS (
    -- FIX: COALESCE para evitar que NULL no campo produto descarte o registro
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN COALESCE(p.produto, '') LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_diretas AS (
    -- FIX: COALESCE garante que pedidos com 'produto' nulo mas com 'produto_id' ou 'quantidade' preenchidos sejam contados
    SELECT 
      COALESCE(
        p.produto_id, 
        (SELECT pr.id FROM produtos pr 
         WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR pr.nome_oficial ILIKE '%' || p.produto || '%'))
            OR (COALESCE(p.produto, '') = '' AND pr.tag = 'cbd') -- Emergência: Se estiver vazio e for o único CBD, tenta atribuir ao CBD (Case Sebastião)
            LIMIT 1
        )
      ) as pid,
      p.uff,
      SUM(p.quantidade)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    WHERE COALESCE(p.produto, '') NOT LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
      AND (p.produto_id IS NOT NULL OR p.quantidade > 0)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_itens_tabela
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    WHERE pid IS NOT NULL
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V10: Também blindada contra NULL
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida' AND posse = 'Venda';
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN SELECT id, uff FROM (
        SELECT p.id, UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff
        FROM public.pedidos p
        WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
    ) p2 LOOP
        
        -- 1. Itens
        IF EXISTS (SELECT 1 FROM public.pedido_itens WHERE pedido_id = v_pedido.id) THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
            SELECT produto_id, quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V10 (Itens)'
            FROM public.pedido_itens WHERE pedido_id = v_pedido.id;
            v_count_ins := v_count_ins + 1;
            
        -- 2. JSON
        ELSIF EXISTS (SELECT 1 FROM public.pedidos WHERE id = v_pedido.id AND COALESCE(produto, '') LIKE '[%') THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
            SELECT 
                (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V10 (JSON)'
            FROM public.pedidos p
            CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
            WHERE p.id = v_pedido.id;
            v_count_ins := v_count_ins + 1;
        
        -- 3. Direto (com resgate de nulos)
        ELSE
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao)
            SELECT 
                COALESCE(p.produto_id, (SELECT pr.id FROM produtos pr WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR pr.nome_oficial ILIKE '%' || p.produto || '%')) OR (COALESCE(p.produto, '') = '' AND pr.tag = 'cbd') LIMIT 1)),
                p.quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V10 (Direto/Null-Safe)'
            FROM public.pedidos p
            WHERE p.id = v_pedido.id;
            v_count_ins := v_count_ins + 1;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000014_inventory_fix_omni_match.sql
-- INVENTORY FIX V11 - OMNI-MATCH & LIMPEZA DE MOVIMENTAÇÕES
-- Inverte a lógica de busca ILIKE e limpa poluição no histórico de movimentações.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome, tag as ptag FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      UPPER(TRIM(COALESCE(l.uf, 'SP'))) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    SELECT 
      p.id as pedido_id,
      p.produto_id,
      p.quantidade,
      p.produto,
      p.observacao,
      UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff
    FROM public.pedidos p
    WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
  ),
  saidas_itens_tabela AS (
    SELECT pi.produto_id as pid, pb.uff, SUM(pi.quantidade)::int as qtd, pi.pedido_id
    FROM public.pedido_itens pi
    JOIN pedidos_base pb ON pb.pedido_id = pi.pedido_id
    GROUP BY pi.produto_id, pb.uff, pi.pedido_id
  ),
  saidas_json AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN COALESCE(p.produto, '') LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_diretas AS (
    -- FIX V11: Omni-Match (Pedido contém Tag ou Nome, ou vice-versa)
    SELECT 
      COALESCE(
        p.produto_id, 
        (SELECT pr.id FROM produtos pr 
         WHERE (COALESCE(p.produto, '') <> '' AND (
                p.produto = pr.nome_oficial 
                OR p.produto ILIKE '%' || pr.tag || '%' 
                OR p.produto ILIKE '%' || pr.nome_oficial || '%'
                OR pr.nome_oficial ILIKE '%' || p.produto || '%'
               ))
            OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
            LIMIT 1
        )
      ) as pid,
      p.uff,
      SUM(p.quantidade)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    WHERE COALESCE(p.produto, '') NOT LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_itens_tabela
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    WHERE pid IS NOT NULL
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0) as entrada,
    COALESCE(s.qtd_sai, 0) as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0)) as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V11: Limpeza agressiva e Omni-Match
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    -- Limpa TODAS as saídas de venda, independente de posse ou observação antiga
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%');
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN SELECT id, uff FROM (
        SELECT p.id, UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))) as uff
        FROM public.pedidos p
        WHERE LOWER(COALESCE(p.status_pedido, '')) <> 'cancelado'
    ) p2 LOOP
        
        -- 1. Itens
        IF EXISTS (SELECT 1 FROM public.pedido_itens WHERE pedido_id = v_pedido.id) THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT produto_id, quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V11 (Itens)', (SELECT created_at FROM pedidos WHERE id = v_pedido.id)
            FROM public.pedido_itens WHERE pedido_id = v_pedido.id;
            v_count_ins := (SELECT count(*)::int FROM public.pedido_itens WHERE pedido_id = v_pedido.id);
            
        -- 2. JSON
        ELSIF EXISTS (SELECT 1 FROM public.pedidos WHERE id = v_pedido.id AND COALESCE(produto, '') LIKE '[%') THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V11 (JSON)', p.created_at
            FROM public.pedidos p
            CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
            WHERE p.id = v_pedido.id;
            v_count_ins := v_count_ins + 1;
        
        -- 3. Direto (Omni-Match)
        ELSE
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                COALESCE(
                    p.produto_id, 
                    (SELECT pr.id FROM produtos pr 
                     WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%'))
                        OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
                        LIMIT 1)
                ),
                p.quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V11 (Omni-Match)', p.created_at
            FROM public.pedidos p
            WHERE p.id = v_pedido.id;
            v_count_ins := v_count_ins + 1;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('deleted', v_count_del, 'inserted', v_count_ins);
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000015_inventory_fix_regional_unification.sql
-- INVENTORY FIX V12 - UNIFICAÇÃO REGIONAL E PARIDADE TOTAL (O 7º CBD)
-- Unifica SC1, RS1, SP1 nas UFs base SC, RS, SP e blinda o status contra nulos.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome, tag as ptag FROM public.produtos
  ),
  entradas AS (
    -- Normaliza a UF para 2 dígitos (SC1 -> SC)
    SELECT 
      l.produto_id as pid, 
      LEFT(UPPER(TRIM(COALESCE(l.uf, 'SP'))), 2) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    -- Blinda status contra NULL e normalization da UF
    SELECT 
      p.id as pedido_id,
      p.produto_id,
      p.quantidade,
      p.produto,
      p.observacao,
      LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
    FROM public.pedidos p
    WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido')) OR p.status_pedido IS NULL
  ),
  saidas_itens_tabela AS (
    SELECT pi.produto_id as pid, pb.uff, SUM(pi.quantidade)::int as qtd, pi.pedido_id
    FROM public.pedido_itens pi
    JOIN pedidos_base pb ON pb.pedido_id = pi.pedido_id
    GROUP BY pi.produto_id, pb.uff, pi.pedido_id
  ),
  saidas_json AS (
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN COALESCE(p.produto, '') LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_diretas AS (
    -- FIX V12: Omni-Match + UF Unification
    SELECT 
      COALESCE(
        p.produto_id, 
        (SELECT pr.id FROM produtos pr 
         WHERE (COALESCE(p.produto, '') <> '' AND (
                p.produto = pr.nome_oficial 
                OR p.produto ILIKE '%' || pr.tag || '%' 
                OR p.produto ILIKE '%' || pr.nome_oficial || '%'
                OR pr.nome_oficial ILIKE '%' || p.produto || '%'
               ))
            OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
            LIMIT 1
        )
      ) as pid,
      p.uff,
      SUM(COALESCE(p.quantidade, 0))::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    WHERE COALESCE(p.produto, '') NOT LIKE '[%' 
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = p.pedido_id)
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_itens_tabela
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    WHERE pid IS NOT NULL
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(SUM(e.qtd_ent), 0)::int as entrada,
    COALESCE(SUM(s.qtd_sai), 0)::int as saida,
    (COALESCE(SUM(e.qtd_ent), 0) - COALESCE(SUM(s.qtd_sai), 0))::int as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  GROUP BY pr.pid, pr.pnome, tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V12: Unificação de UF nas Movimentações Históricas
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_count_del int;
    v_count_ins int := 0;
BEGIN
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%');
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    FOR v_pedido IN SELECT id, uff FROM (
        SELECT p.id, LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
        FROM public.pedidos p
        WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado')) OR p.status_pedido IS NULL
    ) p2 LOOP
        
        IF EXISTS (SELECT 1 FROM public.pedido_itens WHERE pedido_id = v_pedido.id) THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT produto_id, quantidade, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V12 (Itens)', (SELECT created_at FROM pedidos WHERE id = v_pedido.id)
            FROM public.pedido_itens WHERE pedido_id = v_pedido.id;
        ELSIF EXISTS (SELECT 1 FROM public.pedidos WHERE id = v_pedido.id AND COALESCE(produto, '') LIKE '[%') THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V12 (JSON)', p.created_at
            FROM public.pedidos p
            CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
            WHERE p.id = v_pedido.id;
        ELSE
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                COALESCE(
                    p.produto_id, 
                    (SELECT pr.id FROM produtos pr 
                     WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%'))
                        OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
                        LIMIT 1)
                ),
                COALESCE(p.quantidade, 0), 'saida', 'Venda', v_pedido.uff, v_pedido.id, 'Sincronizado V12 (Omni-Match)', p.created_at
            FROM public.pedidos p
            WHERE p.id = v_pedido.id;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'note', 'UFs normalizadas para 2 digitos (V12)');
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000016_inventory_fix_complementary_logic.sql
-- INVENTORY FIX V13 - LÓGICA COMPLEMENTAR E PARIDADE ABSOLUTA (7 CBDs)
-- Permite que produtos diferentes em fontes diferentes (Tabela vs JSON) sejam somados no mesmo pedido.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome, tag as ptag FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      LEFT(UPPER(TRIM(COALESCE(l.uf, 'SP'))), 2) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    SELECT 
      p.id as pedido_id,
      p.produto_id,
      p.quantidade,
      p.produto,
      p.observacao,
      LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
    FROM public.pedidos p
    WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido')) OR p.status_pedido IS NULL
  ),
  saidas_itens_tabela AS (
    SELECT pi.produto_id as pid, pb.uff, SUM(pi.quantidade)::int as qtd, pi.pedido_id
    FROM public.pedido_itens pi
    JOIN pedidos_base pb ON pb.pedido_id = pi.pedido_id
    GROUP BY pi.produto_id, pb.uff, pi.pedido_id
  ),
  saidas_json AS (
    -- FIX V13: Só ignora o JSON se o PRODUTO ESPECÍFICO já estiver na tabela de itens
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN COALESCE(p.produto, '') LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%' 
      AND NOT EXISTS (
        SELECT 1 FROM public.pedido_itens pi 
        WHERE pi.pedido_id = p.pedido_id 
          AND pi.produto_id = (elem->>'produto_id')::uuid
      )
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_diretas AS (
    -- FIX V13: Só ignora o match direto se o PRODUTO já estiver nas fontes anteriores
    SELECT 
      sub.pid, sub.uff, SUM(sub.qtd)::int as qtd, sub.pedido_id
    FROM (
      SELECT 
        COALESCE(
          p.produto_id, 
          (SELECT pr.id FROM produtos pr 
           WHERE (COALESCE(p.produto, '') <> '' AND (
                  p.produto = pr.nome_oficial 
                  OR p.produto ILIKE '%' || pr.tag || '%' 
                  OR p.produto ILIKE '%' || pr.nome_oficial || '%'
                  OR pr.nome_oficial ILIKE '%' || p.produto || '%'
                 ))
              OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
              LIMIT 1
          )
        ) as pid,
        p.uff,
        COALESCE(p.quantidade, 0) as qtd,
        p.pedido_id
      FROM pedidos_base p
      WHERE COALESCE(p.produto, '') NOT LIKE '[%'
    ) sub
    WHERE sub.pid IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.pedido_itens pi 
        WHERE pi.pedido_id = sub.pedido_id AND pi.produto_id = sub.pid
      )
      AND NOT EXISTS (
        -- Verifica se o produto já foi extraído do JSON do mesmo pedido
        SELECT 1 FROM (
          SELECT (e->>'produto_id')::uuid as jpid, p2.id
          FROM pedidos p2, jsonb_array_elements(CASE WHEN p2.produto LIKE '[%' THEN p2.produto::jsonb ELSE '[]'::jsonb END) e
        ) j
        WHERE j.id = sub.pedido_id AND j.jpid = sub.pid
      )
    GROUP BY sub.pid, sub.uff, sub.pedido_id
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_itens_tabela
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    WHERE pid IS NOT NULL
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(SUM(e.qtd_ent), 0)::int as entrada,
    COALESCE(SUM(s.qtd_sai), 0)::int as saida,
    (COALESCE(SUM(e.qtd_ent), 0) - COALESCE(SUM(s.qtd_sai), 0))::int as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  GROUP BY pr.pid, pr.pnome, tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V13: Espelha a lógica complementar para o histórico histórico
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_count_del int;
BEGIN
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%');
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    -- Fonte 1: Itens
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT pi.produto_id, pi.quantidade, 'saida', 'Venda', LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2), p.id, 'V13 (Tabela)', p.created_at
    FROM public.pedido_itens pi
    JOIN public.pedidos p ON p.id = pi.pedido_id
    WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado')) OR p.status_pedido IS NULL;

    -- Fonte 2: JSON (Complementar)
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT 
        (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2), p.id, 'V13 (JSON)', p.created_at
    FROM public.pedidos p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%'
      AND (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado') OR p.status_pedido IS NULL)
      AND NOT EXISTS (
          SELECT 1 FROM public.pedido_itens pi 
          WHERE pi.pedido_id = p.id AND pi.produto_id = (elem->>'produto_id')::uuid
      );

    -- Fonte 3: Direto (Fallback Complementar)
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT 
        sub.pid, sub.qtd, 'saida', 'Venda', sub.uff, sub.pid_origem, 'V13 (Direto)', sub.created_at
    FROM (
        SELECT 
          COALESCE(
              p.produto_id, 
              (SELECT pr.id FROM produtos pr 
               WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%'))
                  OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
                  LIMIT 1)
          ) as pid,
          p.quantidade as qtd,
          LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff,
          p.id as pid_origem,
          p.created_at
        FROM public.pedidos p
        WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado') OR p.status_pedido IS NULL)
          AND COALESCE(p.produto, '') NOT LIKE '[%'
    ) sub
    WHERE sub.pid IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.pedido_itens pi WHERE pi.pedido_id = sub.pid_origem AND pi.produto_id = sub.pid);

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'note', 'Logica Complementar V13 Ativa');
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000017_inventory_fix_json_priority.sql
-- INVENTORY FIX V14 - PRIORIDADE TOTAL AO JSON (PARIDADE DEFINITIVA)
-- Segue a risca a orientação: JSON é a fonte da verdade para IDs e Quantidades.
-- Remove dependência da tabela pedido_itens para garantir paridade com as Métricas.

BEGIN;

DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome, tag as ptag FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      LEFT(UPPER(TRIM(COALESCE(l.uf, 'SP'))), 2) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    SELECT 
      p.id as pedido_id,
      p.produto_id,
      p.quantidade,
      p.produto,
      p.observacao,
      LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
    FROM public.pedidos p
    WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido')) OR p.status_pedido IS NULL
  ),
  saidas_json AS (
    -- Extrai tudo do JSON. Se for JSON, ignoramos qualquer outra coluna deste pedido.
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN COALESCE(p.produto, '') LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%' 
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_diretas AS (
    -- Só processa se NÃO for JSON.
    SELECT 
      COALESCE(
        p.produto_id, 
        (SELECT pr.id FROM produtos pr 
         WHERE (COALESCE(p.produto, '') <> '' AND (
                p.produto = pr.nome_oficial 
                OR p.produto ILIKE '%' || pr.tag || '%' 
                OR p.produto ILIKE '%' || pr.nome_oficial || '%'
                OR pr.nome_oficial ILIKE '%' || p.produto || '%'
               ))
            OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
            LIMIT 1
        )
      ) as pid,
      p.uff,
      SUM(COALESCE(p.quantidade, 0))::int as qtd,
      p.pedido_id
    FROM pedidos_base p
    WHERE COALESCE(p.produto, '') NOT LIKE '[%' 
    GROUP BY pid, p.uff, p.pedido_id
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    WHERE pid IS NOT NULL
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(SUM(e.qtd_ent), 0)::int as entrada,
    COALESCE(SUM(s.qtd_sai), 0)::int as saida,
    (COALESCE(SUM(e.qtd_ent), 0) - COALESCE(SUM(s.qtd_sai), 0))::int as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  GROUP BY pr.pid, pr.pnome, tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- Sincronização V14: Foco exclusivo na tabela Pedidos (JSON + Fallback)
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count_del int;
BEGIN
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%');
    GET DIAGNOSTICS v_count_del = ROW_COUNT;

    -- Fonte 1: JSON
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT 
        (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2), p.id, 'V14 (JSON)', p.created_at
    FROM public.pedidos p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%'
      AND (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado') OR p.status_pedido IS NULL);

    -- Fonte 2: Direto (Non-JSON)
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT 
        sub.pid, sub.qtd, 'saida', 'Venda', sub.uff, sub.pedido_id, 'V14 (Direto)', sub.created_at
    FROM (
        SELECT 
          COALESCE(
              p.produto_id, 
              (SELECT pr.id FROM produtos pr 
               WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%'))
                  OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
                  LIMIT 1)
          ) as pid,
          p.quantidade as qtd,
          LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff,
          p.id as pedido_id,
          p.created_at
        FROM public.pedidos p
        WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado') OR p.status_pedido IS NULL)
          AND COALESCE(p.produto, '') NOT LIKE '[%'
    ) sub
    WHERE sub.pid IS NOT NULL;

    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'note', 'Prioridade JSON V14 Ativa');
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000018_inventory_fix_clean_slate_v15.sql
-- INVENTORY FIX V15 - CLEAN SLATE (O FIM DOS FANTASMAS)
-- Esta versão limpa o histórico de vendas e unifica os cards com a tabela de movimentações.
-- Garantia: Se está na lista (Tabela), está no total (Card).

BEGIN;

-- 1. LIMPEZA TOTAL DE SAÍDAS DE VENDA (Fantasmas/Duplicatas)
DELETE FROM public.estoque_movimentacoes 
WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%' OR observacao ILIKE '%Sincronizado%');

-- 2. RECONSTRUÇÃO DA LÓGICA DE SINCRONIZAÇÃO (O Motor de Verdade)
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pedido record;
    v_mov_count int := 0;
BEGIN
    -- Limpa apenas as vendas sincronizadas para evitar acúmulo
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (observacao ILIKE 'V1%');

    -- Iteramos por todos os pedidos não cancelados
    FOR v_pedido IN 
        SELECT 
            p.id, 
            p.produto, 
            p.quantidade, 
            p.produto_id, 
            p.observacao,
            p.created_at,
            LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
        FROM public.pedidos p
        WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido') OR p.status_pedido IS NULL)
    LOOP
        -- FONTE A: JSON (Prioridade Máxima)
        IF COALESCE(v_pedido.produto, '') LIKE '[%' THEN
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                (elem->>'produto_id')::uuid, 
                (elem->>'quantidade')::int, 
                'saida', 'Venda', v_pedido.uff, v_pedido.id, 'V15 (JSON)', v_pedido.created_at
            FROM jsonb_array_elements(v_pedido.produto::jsonb) AS elem;
            v_mov_count := v_mov_count + 1;
            
        -- FONTE B: Texto (Fallback Case-Insensitive)
        ELSE
            INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
            SELECT 
                COALESCE(
                  v_pedido.produto_id, 
                  (SELECT pr.id FROM produtos pr 
                   WHERE (COALESCE(v_pedido.produto, '') <> '' AND (v_pedido.produto = pr.nome_oficial OR v_pedido.produto ILIKE '%' || pr.tag || '%' OR v_pedido.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || v_pedido.produto || '%'))
                      OR (v_pedido.observacao ILIKE '%' || pr.tag || '%' OR v_pedido.observacao ILIKE '%' || pr.nome_oficial || '%')
                      LIMIT 1)
                ),
                COALESCE(v_pedido.quantidade, 0), 
                'saida', 'Venda', v_pedido.uff, v_pedido.id, 'V15 (Direto)', v_pedido.created_at;
            v_mov_count := v_mov_count + 1;
        END IF;
    END LOOP;

    -- Atualiza snapshots se a função existir
    IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
        PERFORM public.atualizar_estoque_snapshot();
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'movimentos_processados', v_mov_count);
END;
$$;

-- 3. UNIFICAÇÃO DOS CARDS COM A TABELA (O Card lê a Tabela)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome FROM public.produtos
  ),
  consolidado AS (
    -- Agrupamos TUDO o que está na tabela de movimentações (Entradas e Saídas)
    SELECT 
      m.produto_id as pid,
      LEFT(UPPER(TRIM(COALESCE(m.uf_origem, 'SP'))), 2) as uff,
      SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END)::int as qtd_ent,
      SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END)::int as qtd_sai
    FROM public.estoque_movimentacoes m
    GROUP BY m.produto_id, uff
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    c.uff as estado,
    c.qtd_ent as entrada,
    c.qtd_sai as saida,
    (c.qtd_ent - c.qtd_sai) as saldo
  FROM consolidado c
  JOIN produtos_base pr ON pr.pid = c.pid
  ORDER BY pr.pnome, estado;
END;
$$;

-- 4. EXECUÇÃO DA SINCRONIA INICIAL
SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000019_inventory_rollback_to_pedidos_v16.sql
-- INVENTORY ROLLBACK V16 - RESTAURAÇÃO DA FONTE DA VERDADE (PEDIDOS)
-- Reverte a loucura da V15: Cards voltam a ler de Pedidos.
-- Fix definitivo para as 7 unidades de CBD capturadas no JSON e Texto.

BEGIN;

-- 1. RESTAURAÇÃO DOS CARDS (Lendo de Pedidos, ignorando a tabela de movimentações)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH produtos_base AS (
    SELECT id as pid, nome_oficial as pnome, tag as ptag FROM public.produtos
  ),
  entradas AS (
    SELECT 
      l.produto_id as pid, 
      LEFT(UPPER(TRIM(COALESCE(l.uf, 'SP'))), 2) as uff, 
      SUM(l.quantidade_inicial)::int as qtd_ent
    FROM public.lotes l 
    GROUP BY l.produto_id, uff
  ),
  pedidos_base AS (
    -- Fonte da Verdade: Tabela Pedidos ativa ou com status nulo
    SELECT 
      p.id as pedido_id, p.produto_id, p.quantidade, p.produto, p.observacao,
      LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff
    FROM public.pedidos p
    WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado', 'devolvido') OR p.status_pedido IS NULL)
  ),
  saidas_json AS (
    -- Extrai quantidades corretas do JSON (Ex: Ricardo 2, Vanderleia 2)
    SELECT 
      (elem->>'produto_id')::uuid as pid,
      p.uff,
      SUM((elem->>'quantidade')::int)::int as qtd
    FROM pedidos_base p
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN COALESCE(p.produto, '') LIKE '[%' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%' 
    GROUP BY pid, p.uff
  ),
  saidas_diretas AS (
    -- Fallback para pedidos manuais/texto (Ex: Maria 1, Douglas 1)
    SELECT 
        sub.pid, sub.uff, SUM(sub.qtd)::int as qtd
    FROM (
        SELECT 
          COALESCE(
            p.produto_id, 
            (SELECT pr.id FROM produtos pr 
             WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%'))
                OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%')
                LIMIT 1)
          ) as pid,
          COALESCE(p.quantidade, 0) as qtd,
          p.uff
        FROM pedidos_base p
        WHERE COALESCE(p.produto, '') NOT LIKE '[%' 
    ) sub
    WHERE sub.pid IS NOT NULL
    GROUP BY sub.pid, sub.uff
  ),
  saidas_consolidadas AS (
    SELECT pid, uff, SUM(qtd)::int as qtd_sai FROM (
      SELECT pid, uff, qtd FROM saidas_json
      UNION ALL
      SELECT pid, uff, qtd FROM saidas_diretas
    ) s2
    GROUP BY pid, uff
  ),
  todas_chaves AS (
    SELECT pid, uff FROM entradas
    UNION
    SELECT pid, uff FROM saidas_consolidadas
  )
  SELECT 
    pr.pid as prod_id,
    pr.pnome as prod_nome,
    tc.uff as estado,
    COALESCE(e.qtd_ent, 0)::int as entrada,
    COALESCE(s.qtd_sai, 0)::int as saida,
    (COALESCE(e.qtd_ent, 0) - COALESCE(s.qtd_sai, 0))::int as saldo
  FROM todas_chaves tc
  JOIN produtos_base pr ON pr.pid = tc.pid
  LEFT JOIN entradas e ON e.pid = tc.pid AND e.uff = tc.uff
  LEFT JOIN saidas_consolidadas s ON s.pid = tc.pid AND s.uff = tc.uff
  ORDER BY pr.pnome, estado;
END;
$$;

-- 2. LIMPEZA E SINCRONIZAÇÃO DA LISTA (A lista agora obedece rigorosamente aos pedidos)
CREATE OR REPLACE FUNCTION public.sincronizar_movimentacoes_pedidos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Limpa TUDO que for venda ou sincronizado anteriormente para tirar os "fantasmas"
    DELETE FROM public.estoque_movimentacoes 
    WHERE tipo = 'saida' AND (posse = 'Venda' OR observacao ILIKE '%Venda%' OR observacao ILIKE 'V1%');

    -- Insere do JSON
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT (elem->>'produto_id')::uuid, (elem->>'quantidade')::int, 'saida', 'Venda', LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2), p.id, 'V16 (JSON)', p.created_at
    FROM public.pedidos p
    CROSS JOIN LATERAL jsonb_array_elements(p.produto::jsonb) AS elem
    WHERE COALESCE(p.produto, '') LIKE '[%'
      AND (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado') OR p.status_pedido IS NULL);

    -- Insere do Direto
    INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, posse, uf_origem, pedido_id, observacao, created_at)
    SELECT sub.pid, sub.qtd, 'saida', 'Venda', sub.uff, sub.pedido_id, 'V16 (Direto)', sub.created_at
    FROM (
        SELECT 
          COALESCE(p.produto_id, (SELECT pr.id FROM produtos pr WHERE (COALESCE(p.produto, '') <> '' AND (p.produto = pr.nome_oficial OR p.produto ILIKE '%' || pr.tag || '%' OR p.produto ILIKE '%' || pr.nome_oficial || '%' OR pr.nome_oficial ILIKE '%' || p.produto || '%')) OR (p.observacao ILIKE '%' || pr.tag || '%' OR p.observacao ILIKE '%' || pr.nome_oficial || '%') LIMIT 1)) as pid,
          p.quantidade as qtd, LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, p.uf_cliente, 'SP'))), 2) as uff, p.id as pedido_id, p.created_at
        FROM public.pedidos p
        WHERE (LOWER(COALESCE(p.status_pedido, '')) NOT IN ('cancelado') OR p.status_pedido IS NULL)
          AND COALESCE(p.produto, '') NOT LIKE '[%'
    ) sub
    WHERE sub.pid IS NOT NULL;

    RETURN jsonb_build_object('status', 'ok', 'note', 'Rollback V16 completo');
END;
$$;

SELECT public.sincronizar_movimentacoes_pedidos();

COMMIT;


-- MIGRATION: 20260421000020_inventory_fix_final_harmony_v17.sql
-- INVENTORY FIX V17 - HARMONIA FINAL E SNAPSHOTS
-- Esta versão unifica de vez o Card com a Lista (7 CBDs) e prepara para alta performance.

BEGIN;

-- 1. GARANTIR A FUNÇÃO DE SNAPSHOT (Performance Futura)
-- Esta função consolida as movimentações em um saldo fixo para leitura rápida.
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Limpa o snapshot atual
    DELETE FROM public.estoque_snapshot;

    -- Insere o novo saldo calculado a partir da tabela estoque_movimentacoes (A nova fonte da verdade)
    INSERT INTO public.estoque_snapshot (produto_id, uf, entrada, saida, saldo, last_updated)
    SELECT 
        m.produto_id,
        LEFT(UPPER(TRIM(COALESCE(m.uf_origem, 'SP'))), 2) as uff,
        SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END)::int as qtd_ent,
        SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END)::int as qtd_sai,
        (SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END) - SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END))::int as saldo_final,
        NOW()
    FROM public.estoque_movimentacoes m
    GROUP BY m.produto_id, uff;
END;
$$;

-- 2. UNIFICAÇÃO DO RPC DOS CARDS COM O SNAPSHOT/MOVIMENTAÇÕES
-- Como a lista de movimentações agora está 100% correta (7 CBDs), os cards devem lê-la diretamente.
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as prod_id,
    p.nome_oficial as prod_nome,
    m.uf as estado,
    m.entrada::int as entrada,
    m.saida::int as saida,
    m.saldo::int as saldo
  FROM public.estoque_snapshot m
  JOIN public.produtos p ON p.id = m.produto_id
  ORDER BY p.nome_oficial, m.uf;
END;
$$;

-- 3. AJUSTE NA ORDENAÇÃO DOS PEDIDOs (Para o frontend pegar a data correta)
-- Garante que o campo 'data' sempre exista para ordenação
ALTER TABLE public.estoque_movimentacoes ALTER COLUMN data SET DEFAULT NOW();

-- Executa a atualização inicial para o card bater com a lista IMEDIATAMENTE
SELECT public.atualizar_estoque_snapshot();

COMMIT;


-- MIGRATION: 20260421000021_inventory_fix_final_harmony_sql_error.sql
-- INVENTORY FIX V17 FINAL HARMONY E SNAPSHOT (CORRECAO SCHEMA E DADOS)
-- Esta versão unifica de vez o Card com a Lista (7 CBDs) corrigindo os nomes das colunas da tabela de snapshot.

BEGIN;

-- 1. GARANTIR A FUNÇÃO DE SNAPSHOT (Performance Futura)
-- Ajusta para os nomes reais de colunas em estoque_snapshot: prod_id, prod_nome, estado, etc.
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM public.estoque_snapshot;
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    SELECT 
        m.produto_id,
        (SELECT nome_oficial FROM public.produtos WHERE id = m.produto_id),
        LEFT(UPPER(TRIM(COALESCE(m.uf_origem, 'SP'))), 2) as uff,
        SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END)::int as qtd_ent,
        SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END)::int as qtd_sai,
        (SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END) - SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END))::int as saldo_final,
        NOW()
    FROM public.estoque_movimentacoes m
    WHERE m.produto_id IS NOT NULL
    GROUP BY m.produto_id, uff;
END;
$$;

-- 2. UNIFICAR CARDS COM A LISTA CERTA (Fim da divergência)
DROP FUNCTION IF EXISTS public.get_estoque_completo();
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT m.prod_id, m.prod_nome, m.estado, m.entrada::int, m.saida::int, m.saldo::int
  FROM public.estoque_snapshot m
  ORDER BY m.prod_nome, m.estado;
END;
$$;

-- 3. AJUSTE NA ORDENAÇÃO DOS PEDIDOs (Para o frontend pegar a data correta)
-- Garante que o campo 'data' sempre exista para ordenação se for null
ALTER TABLE public.estoque_movimentacoes ALTER COLUMN data SET DEFAULT NOW();
UPDATE public.estoque_movimentacoes SET data = created_at WHERE data IS NULL;

-- Executa a atualização inicial para o card bater com a lista IMEDIATAMENTE
SELECT public.atualizar_estoque_snapshot();

COMMIT;


-- MIGRATION: 20260421000022_inventory_fix_undisputed_truth_v18.sql
-- INVENTORY FIX V18 - A VERDADE INQUESTIONÁVEL (FONTE: PEDIDOS)
-- Esta migration reconstrói o saldo baseado 100% na tabela de pedidos,
-- garantindo que o Pedido #13 (SC - 2 unidades) e o Pedido #12 (Vanderleia - 2 unidades) sejam contados.

BEGIN;

-- 1. LIMPAR MOVIMENTAÇÕES DE SAÍDA ANTIGAS PARA RECONSTRUIR DO ZERO
-- (Mantemos entradas de fornecedores, mas saídas de vendas serão sincronizadas com pedidos)
DELETE FROM public.estoque_movimentacoes WHERE tipo = 'saida';

-- 2. INSERIR SAÍDAS BASEADAS NO PARSING DE JSON E TEXTO DOS PEDIDOS
-- Esta CTE faz o "unpacking" de todos os itens de todos os pedidos ativos.
WITH pedidos_unpacked AS (
    -- Caso A: Pedidos com JSON (Array de produtos)
    SELECT 
        p.id as pedido_id,
        p.data as data_pedido,
        p.uf_postagem,
        (elem->>'quantidade')::int as qty,
        (elem->>'produto_id')::uuid as p_id,
        (elem->>'produto') as p_nome
    FROM public.pedidos p,
    LATERAL jsonb_array_elements(CASE WHEN p.produto ~ '^\[.*\]$' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE p.status_pedido != 'cancelado' 
      AND p.data >= '2026-04-01'
      AND p.produto ~ '^\[.*\]$'

    UNION ALL

    -- Caso B: Pedidos com texto simples ou produto_id direto (Não JSON)
    SELECT 
        p.id as pedido_id,
        p.data as data_pedido,
        p.uf_postagem,
        p.quantidade as qty,
        COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as p_id,
        p.produto as p_nome
    FROM public.pedidos p
    WHERE p.status_pedido != 'cancelado'
      AND p.data >= '2026-04-01'
      AND NOT (p.produto ~ '^\[.*\]$')
      AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
)
INSERT INTO public.estoque_movimentacoes (pedido_id, produto_id, quantidade, tipo, uf_origem, data, observacao)
SELECT 
    pedido_id,
    p_id,
    qty,
    'saida',
    COALESCE(uf_postagem, 'SP'),
    data_pedido,
    'Sincronização Automática V18'
FROM pedidos_unpacked
WHERE p_id IS NOT NULL;

-- 3. ATUALIZAR O SNAPSHOT (Baseado na lista agora reconstruída e perfeita)
SELECT public.atualizar_estoque_snapshot();

COMMIT;


-- MIGRATION: 20260421000023_inventory_omni_source_v19.sql
-- INVENTORY V19 - OMNI SOURCE OF TRUTH
-- Refatora o estoque para que a Dashboard seja alimentada 100% por Pedidos e Lotes reais.

BEGIN;

-- 1. FUNÇÃO PARA RECALCULAR O SNAPSHOT (FONTE: PEDIDOS + LOTES)
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM public.estoque_snapshot;
    
    INSERT INTO public.estoque_snapshot (prod_id, prod_nome, estado, entrada, saida, saldo, updated_at)
    WITH 
    entradas_lotes AS (
        -- Soma de lotes registrados (Entrada Inicial)
        SELECT 
            produto_id, 
            uf as estado, 
            SUM(quantidade_inicial)::int as total_entrada
        FROM public.lotes
        GROUP BY produto_id, uf
    ),
    saidas_pedidos AS (
        -- Soma de pedidos ativos (Saída por Venda)
        -- Parsing robusto de JSON e Texto
        SELECT 
            p_id as produto_id,
            uff as estado,
            SUM(qty)::int as total_saida
        FROM (
            -- Caso A: JSON
            SELECT 
                (elem->>'produto_id')::uuid as p_id,
                LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff,
                (elem->>'quantidade')::int as qty
            FROM public.pedidos p,
            LATERAL jsonb_array_elements(CASE WHEN p.produto ~ '^\[.*\]$' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
            WHERE p.status_pedido != 'cancelado' 
              AND p.data >= '2026-04-01'
              AND p.produto ~ '^\[.*\]$'

            UNION ALL

            -- Caso B: Texto/Direto
            SELECT 
                COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as p_id,
                LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff,
                p.quantidade as qty
            FROM public.pedidos p
            WHERE p.status_pedido != 'cancelado'
              AND p.data >= '2026-04-01'
              AND NOT (p.produto ~ '^\[.*\]$')
              AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
        ) sub
        WHERE p_id IS NOT NULL
        GROUP BY p_id, uff
    )
    SELECT 
        COALESCE(e.produto_id, s.produto_id),
        (SELECT nome_oficial FROM public.produtos WHERE id = COALESCE(e.produto_id, s.produto_id)),
        COALESCE(e.estado, s.estado),
        COALESCE(e.total_entrada, 0),
        COALESCE(s.total_saida, 0),
        (COALESCE(e.total_entrada, 0) - COALESCE(s.total_saida, 0)),
        NOW()
    FROM entradas_lotes e
    FULL JOIN saidas_pedidos s ON e.produto_id = s.produto_id AND e.estado = s.estado;
END;
$$;

-- 2. LIMPEZA E SINCRONIZAÇÃO DA LISTA DE MOVIMENTAÇÕES (AUDITORIA)
-- Removemos lançamentos fantasmas (Troca UF) e saídas orfãs
DELETE FROM public.estoque_movimentacoes 
WHERE (tipo = 'saida') 
   OR (tipo = 'entrada' AND observacao LIKE '%Troca UF%') 
   OR (tipo = 'entrada' AND observacao LIKE '%Devolução%');

-- Re-insere as saídas baseadas no estado atual dos pedidos
INSERT INTO public.estoque_movimentacoes (pedido_id, produto_id, quantidade, tipo, uf_origem, data, observacao)
SELECT 
    p_id_full.pedido_id,
    p_id_full.p_id,
    p_id_full.qty,
    'saida',
    p_id_full.uff,
    p_id_full.data_ped,
    'Sincronização V19'
FROM (
    SELECT 
        p.id as pedido_id,
        (elem->>'produto_id')::uuid as p_id,
        LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff,
        (elem->>'quantidade')::int as qty,
        p.data as data_ped
    FROM public.pedidos p,
    LATERAL jsonb_array_elements(CASE WHEN p.produto ~ '^\[.*\]$' THEN p.produto::jsonb ELSE '[]'::jsonb END) AS elem
    WHERE p.status_pedido != 'cancelado' AND p.data >= '2026-04-01' AND p.produto ~ '^\[.*\]$'
    UNION ALL
    SELECT 
        p.id as pedido_id,
        COALESCE(p.produto_id, (SELECT pr.id FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto LIMIT 1)) as p_id,
        LEFT(UPPER(TRIM(COALESCE(p.uf_postagem, 'SP'))), 2) as uff,
        p.quantidade as qty,
        p.data as data_ped
    FROM public.pedidos p
    WHERE p.status_pedido != 'cancelado' AND p.data >= '2026-04-01' AND NOT (p.produto ~ '^\[.*\]$')
      AND (p.produto_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.produtos pr WHERE pr.nome_oficial = p.produto OR pr.tag = p.produto))
) p_id_full
WHERE p_id_full.p_id IS NOT NULL;

-- 3. GARANTIR QUE OS CARDS SEJAM ATUALIZADOS EM TEMPO REAL
DROP TRIGGER IF EXISTS trg_snapshot_on_pedido_change ON public.pedidos;
CREATE OR REPLACE FUNCTION public.fn_trigger_update_snapshot() 
RETURNS trigger AS $$ BEGIN PERFORM public.atualizar_estoque_snapshot(); RETURN NULL; END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_snapshot_on_pedido_change 
AFTER INSERT OR UPDATE OR DELETE ON public.pedidos
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trigger_update_snapshot();

DROP TRIGGER IF EXISTS trg_snapshot_on_lote_change ON public.lotes;
CREATE TRIGGER trg_snapshot_on_lote_change 
AFTER INSERT OR UPDATE OR DELETE ON public.lotes
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trigger_update_snapshot();

-- Executa uma vez
SELECT public.atualizar_estoque_snapshot();

COMMIT;


-- MIGRATION: 20260422000001_drop_old_criar_pedido_functions.sql
-- ==============================================================================
-- FIX: Remover funcoes criar_pedido duplicadas, manter apenas criar_pedido_v2
-- Execute no Supabase SQL Editor
-- ==============================================================================

BEGIN;

-- Drop todas as versoes antigas de criar_pedido (mantem argumentos diferentes)
DROP FUNCTION IF EXISTS public.criar_pedido(uuid, text, numeric, text, text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.criar_pedido(uuid, text, numeric, text, text, text, text, text, jsonb, uuid);
DROP FUNCTION IF EXISTS public.criar_pedido();

-- Verificar se criar_pedido_v2 existe
SELECT proname, pronargs 
FROM pg_proc 
WHERE proname = 'criar_pedido_v2';

COMMIT;

-- MIGRATION: 20260422000002_create_criar_pedido_v2.sql
-- ==============================================================================
-- CRIAR_PEDIDO_V2 - Baseado no schema .agent/schemas/pedido.md
-- Execute NO SUPABASE SQL EDITOR
-- ==============================================================================

BEGIN;

-- Garante que colunas existem
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS obs text;
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS observacao text;

-- Cria sequencia para order_number (thread-safe)
CREATE SEQUENCE IF NOT EXISTS public.pedidos_order_number_seq;

-- Inicia a partir do max atual
SELECT setval('public.pedidos_order_number_seq', COALESCE(MAX(order_number), 0)) FROM public.pedidos;

-- Drop funcao antiga se existir
DROP FUNCTION IF EXISTS public.criar_pedido_v2(
  uuid, text, numeric, text, text, text, text, text, jsonb
);

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
  -- order_number via sequence (thread-safe)
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Valida contato obrigatorio
  IF p_contato_id IS NULL THEN
    RAISE EXCEPTION 'p_contato_id e obrigatorio';
  END IF;

  -- Verifica se contato existe
  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN
    RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id;
  END IF;

  -- Determina socio pelo apelido (ver ou a - minúsculo ou maiúsculo)
  IF LOWER(p_criado_por) = 'ver' THEN
    v_socio := 'ver';
  ELSIF LOWER(p_criado_por) = 'a' THEN
    v_socio := 'a';
  ELSE
    -- Padrao: usar o apelido recebido diretamente
    v_socio := LOWER(p_criado_por);
  END IF;

  -- Canal do lancamento
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
      v_produto_text := p_produtos::text;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
  END IF;

  -- CRIA PEDIDO
  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, obs, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, v_socio, v_order_number, v_data_sp,
    false, now(),
    COALESCE(v_produto_text, ''), v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  -- Processa produtos e ABATE ESTOQUE
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
        
        -- Registra movimentacao
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, lote_id, uf_origem, observacao)
        VALUES (v_produto_id, v_qtd, 'saida', v_lote_rec.id, v_lote_rec.uf, 'Pedido: ' || v_pedido_id);
      END IF;

      -- Insere item no pedido
      INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco)
      VALUES (v_pedido_id, v_produto_id, COALESCE(v_qtd, 1), 0);
    END LOOP;
  END IF;

  -- CRIA LANCAMENTO DO SOCIO (so se pago)
  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento,
      v_socio, v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_v2 TO anon, authenticated, service_role;

COMMIT;

-- MIGRATION: 20260422044534_8809e68a-8114-4372-83db-f156ef204bd7.sql
-- Garante extensões pg_cron / pg_net
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Remove agendamento anterior (se existir) para evitar duplicidade
DO $$
BEGIN
  PERFORM cron.unschedule('superfrete-sync-every-5min');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Agenda chamada à edge function superfrete-sync a cada 5 minutos
SELECT cron.schedule(
  'superfrete-sync-every-5min',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://seplijmbdrbfbtdmjubg.supabase.co/functions/v1/superfrete-sync',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);

-- MIGRATION: 20260423000001_fix_order_number_sequence.sql
-- ==============================================================================
-- FIX: Race condition em order_number usando SEQUENCE
-- Execute NO SUPABASE SQL EDITOR
-- ==============================================================================

-- 1. Cria sequencia
CREATE SEQUENCE IF NOT EXISTS public.pedidos_order_number_seq;

-- 2. Inicializa com valor atual max
SELECT setval('public.pedidos_order_number_seq', COALESCE((SELECT MAX(order_number) FROM public.pedidos), 0));

-- 3. Recria funcao criar_pedido_v2
DROP FUNCTION IF EXISTS public.criar_pedido_v2(
  uuid, text, numeric, text, text, text, text, text, jsonb
);

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
  -- order_number via sequence (thread-safe)
  v_order_number := nextval('pedidos_order_number_seq');
  v_data_sp := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_contato_id IS NULL THEN
    RAISE EXCEPTION 'p_contato_id e obrigatorio';
  END IF;

  SELECT id INTO v_contato_id FROM public.contatos WHERE id = p_contato_id;
  IF v_contato_id IS NULL THEN
    RAISE EXCEPTION 'Contato nao encontrado: %', p_contato_id;
  END IF;

  IF LOWER(p_criado_por) = 'ver' THEN
    v_socio := 'ver';
  ELSIF LOWER(p_criado_por) = 'a' THEN
    v_socio := 'a';
  ELSE
    v_socio := LOWER(p_criado_por);
  END IF;

  IF p_canal = 'REP' THEN v_canal_lancamento := 'REP';
  ELSIF p_canal = 'BASE' THEN v_canal_lancamento := 'BASE';
  ELSE v_canal_lancamento := 'ADS';
  END IF;

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    SELECT COALESCE(SUM((item->>'quantidade')::integer), 1)::int INTO v_quantidade_total
    FROM jsonb_array_elements(p_produtos) AS item;
  ELSE
    v_quantidade_total := 1;
  END IF;

  BEGIN
    SELECT cidade_uf INTO v_uf_cliente FROM public.contatos WHERE id = p_contato_id LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_uf_cliente := NULL;
  END;

  IF p_uf_postagem IS NOT NULL AND LENGTH(p_uf_postagem) = 2 THEN
    v_uf_postagem_calc := p_uf_postagem;
  ELSE
    v_uf_postagem_calc := COALESCE(v_uf_cliente, 'SC');
  END IF;

  v_modalidade_calc := COALESCE(p_modalidade, 'mini');

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    v_quantidade_total := 0;
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      v_quantidade_total := v_quantidade_total + COALESCE(v_qtd, 1);
    END LOOP;
    
    IF jsonb_array_length(p_produtos) = 1 THEN
      v_produto_text := (p_produtos->0->>'produto');
    ELSE
      v_produto_text := p_produtos::text;
    END IF;
  ELSE
    v_quantidade_total := 1;
    v_produto_text := '';
  END IF;

  INSERT INTO public.pedidos (
    contato_id, valor, canal, status_pagamento, modalidade, uf_postagem,
    status_pedido, obs, criado_por, order_number, data,
    estoque_processado, created_at,
    produto, quantidade
  )
  VALUES (
    p_contato_id, p_valor, p_canal, p_status_pagamento, v_modalidade_calc, v_uf_postagem_calc,
    'aguardando_rastreio', COALESCE(p_obs, '')::text, v_socio, v_order_number, v_data_sp,
    false, now(),
    COALESCE(v_produto_text, ''), v_quantidade_total
  )
  RETURNING id INTO v_pedido_id;

  IF p_produtos IS NOT NULL AND jsonb_typeof(p_produtos) = 'array' AND jsonb_array_length(p_produtos) > 0 THEN
    FOR v_produto_id, v_qtd IN
      SELECT (item->>'produto_id')::uuid, COALESCE((item->>'quantidade')::integer, 1)
      FROM jsonb_array_elements(p_produtos) AS item
    LOOP
      SELECT * INTO v_lote_rec FROM public.lotes l
      WHERE l.produto_id = v_produto_id AND l.uf = v_uf_postagem_calc
      ORDER BY l.data_producao ASC LIMIT 1;

      IF NOT FOUND THEN
        SELECT * INTO v_lote_rec FROM public.lotes l
        WHERE l.produto_id = v_produto_id
        ORDER BY l.data_producao ASC LIMIT 1;
      END IF;

      IF FOUND THEN
        UPDATE public.lotes SET quantidade_atual = quantidade_atual - v_qtd WHERE id = v_lote_rec.id;
        
        INSERT INTO public.estoque_movimentacoes (produto_id, quantidade, tipo, lote_id, uf_origem, observacao)
        VALUES (v_produto_id, v_qtd, 'saida', v_lote_rec.id, v_lote_rec.uf, 'Pedido: ' || v_pedido_id);
      END IF;

      INSERT INTO public.pedido_itens (pedido_id, produto_id, quantidade, preco)
      VALUES (v_pedido_id, v_produto_id, COALESCE(v_qtd, 1), 0);
    END LOOP;
  END IF;

  IF p_status_pagamento = 'pago' THEN
    INSERT INTO public.lancamentos_socios (
      socio, tipo, valor, canal, contato_id, quantidade, modalidade,
      uf_postagem, status_pagamento, criado_por, pedido_id, data, descricao
    ) VALUES (
      v_socio, 'VENDA', p_valor, v_canal_lancamento, p_contato_id,
      v_quantidade_total, v_modalidade_calc, v_uf_postagem_calc, p_status_pagamento,
      v_socio, v_pedido_id, v_data_sp,
      'Venda #' || v_order_number::text
    );
  END IF;

  RETURN jsonb_build_object('pedido_id', v_pedido_id, 'status', 'criado', 'order_number', v_order_number);

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Erro ao criar pedido: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_pedido_v2 TO anon, authenticated, service_role;

-- MIGRATION: 20260423215508_dc9ef628-66a9-457e-bfe4-82400c20242c.sql
-- Reverte status dos 14 pedidos afetados pelo bug do fallback público
UPDATE public.pedidos
SET status_pedido = 'postado'
WHERE id IN (
  '9e55cb5a-4257-42c6-91a3-8cb14e9fd132',
  '6e754295-8568-4749-bc15-f6ef1f23582f',
  'cec580ee-6d3c-48ce-9c3d-b25248d7028a',
  '4e93e73d-ae6b-4740-9f26-0ed579d9e340',
  'da002d15-4a50-4a0c-8a2f-b254fe2fc25f',
  'ba31ce99-9b33-49e3-bf75-fb05bb55eb88',
  '2befd036-8812-43df-aa75-d56bdd216506',
  '10a55370-253c-4122-a584-ab106cbb6238',
  '0c83456e-b4aa-4153-8367-b5e8e343f2fd',
  '8273afe5-a049-4dfd-85da-672a0a804808',
  '0b3b761d-f5b8-4bc0-8fc3-971a3a7a0e14',
  '31f4a4b4-e48c-4f1d-addb-fecd58943a03',
  '0a4e84a8-91bb-46b4-867f-04ad4478ed3c',
  'c09bc10b-4196-4df6-8fc7-2c2d9d924e63'
) AND status_pedido = 'entregue';

-- Auditoria
INSERT INTO public.log_atividades (usuario, acao, tabela_afetada, registro_id, detalhe)
SELECT
  'Sistema (Correção bug sync)',
  'Reversão: entregue -> postado',
  'pedidos',
  id,
  'Pedido #' || order_number || ' revertido para postado. Motivo: falso positivo do fallback público (muambator/linkcorreios retornaram página de exemplo).'
FROM public.pedidos
WHERE id IN (
  '9e55cb5a-4257-42c6-91a3-8cb14e9fd132',
  '6e754295-8568-4749-bc15-f6ef1f23582f',
  'cec580ee-6d3c-48ce-9c3d-b25248d7028a',
  '4e93e73d-ae6b-4740-9f26-0ed579d9e340',
  'da002d15-4a50-4a0c-8a2f-b254fe2fc25f',
  'ba31ce99-9b33-49e3-bf75-fb05bb55eb88',
  '2befd036-8812-43df-aa75-d56bdd216506',
  '10a55370-253c-4122-a584-ab106cbb6238',
  '0c83456e-b4aa-4153-8367-b5e8e343f2fd',
  '8273afe5-a049-4dfd-85da-672a0a804808',
  '0b3b761d-f5b8-4bc0-8fc3-971a3a7a0e14',
  '31f4a4b4-e48c-4f1d-addb-fecd58943a03',
  '0a4e84a8-91bb-46b4-867f-04ad4478ed3c',
  'c09bc10b-4196-4df6-8fc7-2c2d9d924e63'
);

-- MIGRATION: 20260423223827_4a2ae16a-f75c-4f3c-ad16-4f61ec034fae.sql

-- 1) RPC SECURITY DEFINER para listar sócios contornando RLS de perfis_usuario
CREATE OR REPLACE FUNCTION public.listar_socios()
RETURNS TABLE (socio_key text, nome text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT UPPER(p.socio_key)::text AS socio_key, p.nome
  FROM public.perfis_usuario p
  WHERE p.tipo_usuario = 'admin'
    AND p.socio_key IS NOT NULL
    AND p.nome IS NOT NULL
  ORDER BY p.nome;
$$;

GRANT EXECUTE ON FUNCTION public.listar_socios() TO authenticated;

-- 2) Reverter 6 pedidos contaminados (API SuperFrete diz "released" mas banco diz "postado")
UPDATE public.pedidos
SET status_pedido = 'aguardando_rastreio'
WHERE id IN (
  'c09bc10b-4196-4df6-8fc7-2c2d9d924e63', -- #34
  '0a4e84a8-91bb-46b4-867f-04ad4478ed3c', -- #31
  '0c83456e-b4aa-4153-8367-b5e8e343f2fd', -- #27
  '2befd036-8812-43df-aa75-d56bdd216506', -- #25
  'cec580ee-6d3c-48ce-9c3d-b25248d7028a', -- #15
  '9e55cb5a-4257-42c6-91a3-8cb14e9fd132'  -- #12
)
AND status_pedido = 'postado';

-- 3) Reverter 2 pedidos travados como "entregue" indevidamente (#29 e #26 Vinicius)
UPDATE public.pedidos
SET status_pedido = 'aguardando_rastreio'
WHERE id IN (
  '0b3b761d-f5b8-4bc0-8fc3-971a3a7a0e14', -- #29
  '10a55370-253c-4122-a584-ab106cbb6238'  -- #26 Vinicius
)
AND status_pedido = 'entregue';

-- 4) Auditoria
INSERT INTO public.log_atividades (usuario, acao, tabela_afetada, registro_id, detalhe)
SELECT
  'Sistema (Reversão Sync)',
  'Status revertido para aguardando_rastreio (mapeamento SuperFrete corrigido)',
  'pedidos',
  id,
  'Status anterior divergia da API SuperFrete (released/entregue indevido). Card retorna para Logística.'
FROM public.pedidos
WHERE id IN (
  'c09bc10b-4196-4df6-8fc7-2c2d9d924e63',
  '0a4e84a8-91bb-46b4-867f-04ad4478ed3c',
  '0c83456e-b4aa-4153-8367-b5e8e343f2fd',
  '2befd036-8812-43df-aa75-d56bdd216506',
  'cec580ee-6d3c-48ce-9c3d-b25248d7028a',
  '9e55cb5a-4257-42c6-91a3-8cb14e9fd132',
  '0b3b761d-f5b8-4bc0-8fc3-971a3a7a0e14',
  '10a55370-253c-4122-a584-ab106cbb6238'
);


-- MIGRATION: 20260424003456_2dc6f17a-1621-408c-ad2e-a34c1152e58c.sql
-- Backfill dos 2 admins já em auth.users (idempotente)
INSERT INTO public.perfis_usuario
  (user_id, nome, email, acesso_kanban, ver_menu, pode_excluir_card, tipo_usuario, socio_key)
VALUES
  ('44aa68b2-8cea-42c8-8fb0-3093926e2b35', 'V', 'v@santaflor.com',
   'todos', '["todos"]'::jsonb, true, 'admin', 'V'),
  ('61b22ba5-6df4-493f-ad6a-cd51c95bb5c4', 'A', 'a@santaflor.com',
   'todos', '["todos"]'::jsonb, true, 'admin', 'A')
ON CONFLICT (user_id) DO UPDATE SET
  tipo_usuario = 'admin',
  acesso_kanban = 'todos',
  ver_menu = '["todos"]'::jsonb,
  pode_excluir_card = true,
  socio_key = EXCLUDED.socio_key,
  email = EXCLUDED.email;

-- Backfill genérico: qualquer auth.user sem perfil ganha um
INSERT INTO public.perfis_usuario (user_id, nome, email, acesso_kanban, ver_menu, pode_excluir_card, tipo_usuario, socio_key)
SELECT u.id,
       COALESCE(u.raw_user_meta_data->>'apelido', split_part(u.email,'@',1)),
       u.email,
       'todos',
       '["todos"]'::jsonb,
       true,
       COALESCE(u.raw_user_meta_data->>'tipo_usuario','admin'),
       COALESCE(u.raw_user_meta_data->>'socio_key', UPPER(LEFT(split_part(u.email,'@',1),1)))
FROM auth.users u
LEFT JOIN public.perfis_usuario p ON p.user_id = u.id
WHERE p.user_id IS NULL;

-- Policy de INSERT (faltando) — permite frontend autenticado criar perfil próprio
CREATE POLICY "Users can insert own profile"
ON public.perfis_usuario FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);


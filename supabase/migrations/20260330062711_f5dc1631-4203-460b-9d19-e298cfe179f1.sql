
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

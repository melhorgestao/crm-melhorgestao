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
-- 10. ADICIONAR 'ADMIN' AO CHECK DE canal_origem (se existir)
-- ============================================================

-- Verificar se existe constraint de canal_origem
DO $$
BEGIN
  -- Tentar adicionar 'ADMIN' à constraint se existir
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

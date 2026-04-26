-- CLEAN SCHEMA EXPORT (Option B)
-- Generated on 2026-04-26T05:33:27.351Z

-- 0. Cleanup & Environment
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
SET search_path = public, auth, extensions;

-- 1. Extensions & Sequences
-- Create pg_cron extension for archiving
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
-- Enable pg_cron and pg_net extensions
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
-- CRITICAL: Enable pg_trgm for fast text search (ilike %...%)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- Garante extensões pg_cron / pg_net
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE SEQUENCE IF NOT EXISTS pedidos_order_number_seq;
-- Cria sequencia para order_number (thread-safe)
CREATE SEQUENCE IF NOT EXISTS public.pedidos_order_number_seq;
-- ==============================================================================
-- FIX: Race condition em order_number usando SEQUENCE
-- Execute NO SUPABASE SQL EDITOR
-- ==============================================================================

-- 1. Cria sequencia
CREATE SEQUENCE IF NOT EXISTS public.pedidos_order_number_seq;

-- 2. Tables
-- perfis_usuario
CREATE TABLE public.perfis_usuario (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  nome text NOT NULL,
  acesso_kanban text NOT NULL DEFAULT 'todos' CHECK (acesso_kanban IN ('ads', 'base', 'todos')),
  ver_menu jsonb NOT NULL DEFAULT '["todos"]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- instancias
CREATE TABLE public.instancias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  tipo text NOT NULL CHECK (tipo IN ('ads', 'base')),
  numero_final text,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

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

-- 2. Create configuracoes table for API keys
CREATE TABLE public.configuracoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chave text UNIQUE NOT NULL,
  valor text,
  updated_at timestamp with time zone DEFAULT now()
);

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

-- Migration: tabela estoque_ufs para UFs dinâmicas
-- EXECUTAR MANUALMENTE NO SQL EDITOR DO SUPABASE

-- 1. Criar tabela
CREATE TABLE IF NOT EXISTS estoque_ufs (
  uf TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now()
);

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

-- 1. Criar tabela de grupos de produtos (se não existir)
CREATE TABLE IF NOT EXISTS public.produtos_grupos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  cor_grupo text,
  ordem integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

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

-- 3. Alterations (Columns & Constraints)
-- Add columns to contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS cpf text;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS data_nascimento date;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS utm_origem text;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS como_conheceu text;

-- Add columns to pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS produto_id uuid REFERENCES public.produtos(id);

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS preco_unitario numeric;

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

-- Add columns to estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS lote_id uuid REFERENCES public.lotes(id);

ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS uf_origem text;

-- Add snapshot columns to lancamentos_socios
ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS snapshot_saldo_v numeric;

ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS snapshot_saldo_a numeric;

-- Add rua_numero and bairro to contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS rua_numero text;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS bairro text;

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

-- 1. pedidos: add status_pagamento, order_number, complemento
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS status_pagamento text DEFAULT 'pago';

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS complemento text;

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS order_number integer;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS complemento text;

-- 3. remetentes_uf: add descricao_produto, valor_unitario
ALTER TABLE public.remetentes_uf ADD COLUMN IF NOT EXISTS descricao_produto text;

ALTER TABLE public.remetentes_uf ADD COLUMN IF NOT EXISTS valor_unitario numeric;

-- 4. perfis_usuario: add pode_excluir_card
ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS pode_excluir_card boolean DEFAULT true;

-- Add separate cidade and uf columns to contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS cidade text;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS uf text;

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

-- 3. lancamentos_socios → pedidos
ALTER TABLE lancamentos_socios
  ADD COLUMN IF NOT EXISTS pedido_id uuid;

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

-- Add obs column to pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS obs text;

-- Add columns for representative attribution and conversion tracking
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES public.contatos(id);

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS primeira_venda_em date;

-- 1. Add is_default_base to public.instancias
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='instancias' AND column_name='is_default_base') THEN
        ALTER TABLE public.instancias ADD COLUMN is_default_base boolean DEFAULT false;
    END IF;
END $$;

-- Add representante_id to contatos (references another contato REP)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS representante_id uuid;

-- Add primeira_venda_em to contatos (used by midnight migration function)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS primeira_venda_em timestamptz;

-- Add observacao to pedidos (for notes/obs on pending orders)
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS observacao text;

-- Lock status after midnight - prevents changes to delivered orders and paid vendas

-- Add locked_at column to pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS locked_at timestamptz;

-- Add locked_at column to lancamentos_socios
ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS locked_at timestamptz;

-- Add transferencia_direcao column to lancamentos_socios
ALTER TABLE lancamentos_socios ADD COLUMN IF NOT EXISTS transferencia_direcao TEXT;

-- 2. Adicionar coluna pedido_item_id em estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_item_id uuid REFERENCES public.pedido_itens(id);

-- RPC definitivo: processar_pedido_estoque
-- Suporta pedidos com produto=text ou produto=json array
-- Idempotente: nao duplica movimentacoes
-- Nao altera estrutura da tabela pedidos

-- 1. Garantir coluna pedido_id em estoque_movimentacoes (ja existe observacao como fallback)
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

-- CONSISTENCIA TOTAL DE ESTOQUE
-- Adiciona flag anti-duplicacao, sync de estoque, e atualiza trigger

-- ============================================================
-- ETAPA 1: Coluna anti-duplicacao em pedidos
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;

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

-- CORRECAO DEFINITIVA DO ESTOQUE
-- 1. process_venda insere estoque_processado=true
-- 2. Trigger ignora pedidos ja processados
-- 3. Reprocessa TODOS pedidos existentes sem movimentacao

-- ============================================================
-- 1. Garantir colunas necessarias
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;

ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

-- ESTOQUE DEFINITIVO: reprocessa TODOS pedidos + trigger automatico
-- Esta migration deve ser executada UMA VEZ no Supabase SQL Editor

-- ============================================================
-- PASSO 1: Garantir estrutura necessaria
-- ============================================================
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;

ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

-- ============================================================
-- COPIE E COLE TUDO NO SUPABASE SQL EDITOR
-- Estoque definitivo: cria colunas, trigger e reprocessa pedidos
-- ============================================================

-- 1. Adiciona colunas que faltam
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean NOT NULL DEFAULT false;

ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

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

-- Colunas novas para identificar dono da instância
ALTER TABLE public.instancias ADD COLUMN IF NOT EXISTS dono_tipo text DEFAULT 'admin' CHECK (dono_tipo IN ('admin', 'representante'));

ALTER TABLE public.instancias ADD COLUMN IF NOT EXISTS representante_user_id uuid REFERENCES auth.users(id);

-- ============================================================
-- 2. PERFIS_USUARIO - Colunas para multi-instância
-- ============================================================

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS tipo_usuario text DEFAULT 'admin';

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS socio_key text CHECK (socio_key IN ('V', 'A'));

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS servico_tipo text;

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS uf_fixa text;

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS instancia_id uuid REFERENCES public.instancias(id);

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS criado_por uuid REFERENCES auth.users(id);

-- ============================================================
-- 3. PEDIDOS - Vincular a contato e instância
-- ============================================================

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS contato_id uuid REFERENCES public.contatos(id);

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS instancia_id uuid REFERENCES public.instancias(id);

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS tipo_origem text;

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS entrega_em_maos boolean DEFAULT false;

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_debitado boolean DEFAULT false;

-- ============================================================
-- 4. LOTES - Suporte a estoque atribuído
-- ============================================================

ALTER TABLE public.lotes ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES auth.users(id);

-- ============================================================
-- 6.5 PREPARAÇÃO CONTATOS (canal_atual + constraint ADMIN)
-- ============================================================

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS canal_atual text;

-- ============================================================
-- Admin: adicionar email em perfis_usuario
-- ============================================================

ALTER TABLE public.perfis_usuario ADD COLUMN IF NOT EXISTS email text;

-- Nova coluna
ALTER TABLE perfis_usuario ADD COLUMN IF NOT EXISTS is_socio boolean DEFAULT false;

-- Migration: Canal Atual + Tag New para transferência midnight
-- Rode este SQL no Supabase SQL Editor

-- 1. Adiciona coluna canal_atual (canal atual para visualização no Kanban)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS canal_atual text;

-- 2. Adiciona coluna is_novo (para tag "Novo" azul por 24h após transferência)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS is_novo boolean DEFAULT false;

-- 3. Adiciona coluna novo_ate (timestamp até quando a tag "Novo" expira)
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS novo_ate timestamptz;

-- 1. SCHEMA: Adiciona coluna criado_por em estoque_movimentacoes
ALTER TABLE public.estoque_movimentacoes ADD COLUMN IF NOT EXISTS criado_por text;

-- Adicionar coluna etiqueta_valor para armazenar custo do frete
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_valor NUMERIC(10,2);

-- Adiciona coluna representante_id à tabela pedidos
-- Rode no Supabase SQL Editor

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES auth.users(id);

-- Migration: Box Size automático por produto

-- 1. Adicionar coluna box_size na tabela produtos
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_size TEXT;

-- 2. Adicionar coluna box_size na tabela pedidos  
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS box_size TEXT;

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

-- 12. Adicionar colunas em contatos
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS canal_atual text;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS is_novo boolean DEFAULT false;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS novo_ate timestamptz;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS ultima_venda_em date;

ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS instancia_id uuid REFERENCES public.instancias(id);

-- 13. Adicionar representante_id em lotes
ALTER TABLE public.lotes ADD COLUMN IF NOT EXISTS representante_id uuid REFERENCES auth.users(id);

-- Migration completa: Box Size com quantidade máxima

-- 1. Adicionar colunas na tabela produtos
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_size TEXT;

ALTER TABLE produtos ADD COLUMN IF NOT EXISTS box_qty_max INTEGER DEFAULT 10;

ALTER TABLE produtos ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE produtos ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- 2. Adicionar coluna box_size na tabela pedidos  
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS box_size TEXT;

-- Adicionar coluna pedido_id em lancamentos_socios
-- Execute no Supabase SQL Editor

ALTER TABLE public.lancamentos_socios ADD COLUMN IF NOT EXISTS pedido_id uuid REFERENCES public.pedidos(id);

-- Verificar e criar colunas para valor dofrete
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_valor NUMERIC(10,2);

ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS shipping_price NUMERIC(10,2);

-- 4. Criar tabela de controle para saber quais pedidos ja processaram estoque
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean DEFAULT false;

-- 1. Garantir coluna estoque_processado nos pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS estoque_processado boolean DEFAULT false;

-- Add etiqueta_paga column to pedidos
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_paga BOOLEAN DEFAULT FALSE;

-- =============================================
-- Migration: Logística - Sistema de Duas Etapas
-- Execute no Supabase SQL Editor
-- =============================================

-- 1. Adicionar coluna etiqueta_paga na tabela pedidos
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS etiqueta_paga BOOLEAN DEFAULT FALSE;

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

-- 1. Verificar se coluna uf_cliente existe em pedidos
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

-- 3. Adicionar coluna grupo_id (opcional, para agrupamento)
ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS grupo_id uuid REFERENCES public.produtos_grupos(id);

-- 4. Adicionar coluna limite_estoque (quantos produtos quer em estoque)
ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS limite_estoque integer DEFAULT 0;

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS gateway_etiqueta text DEFAULT 'superfrete';

-- Adiciona campos de peso e dimensoes aos produtos
ALTER TABLE public.produtos 
ADD COLUMN IF NOT EXISTS peso integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS largura_caixa numeric DEFAULT 11,
ADD COLUMN IF NOT EXISTS altura_caixa numeric DEFAULT 2,
ADD COLUMN IF NOT EXISTS comprimento_caixa numeric DEFAULT 16;

-- SQL para adicionar peso aos produtos e atualizar funções RPC
-- Execute no Supabase SQL Editor

-- 1. Adiciona coluna peso aos produtos
ALTER TABLE public.produtos 
ADD COLUMN IF NOT EXISTS peso integer DEFAULT 300;

-- 1. Garante coluna uf_cliente em pedidos (conforme guia)
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

-- Garante que colunas existem
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS obs text;

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS observacao text;

-- Rename cidade to cidade_uf
ALTER TABLE public.contatos RENAME COLUMN cidade TO cidade_uf;

-- 1. Drop como_conheceu column
ALTER TABLE public.contatos DROP COLUMN IF EXISTS como_conheceu;

-- Drop endereco column
ALTER TABLE public.contatos DROP COLUMN IF EXISTS endereco;

-- Drop como_conheceu if it exists
ALTER TABLE public.contatos DROP COLUMN IF EXISTS como_conheceu;

-- Drop data_nascimento from contatos
ALTER TABLE public.contatos DROP COLUMN IF EXISTS data_nascimento;

ALTER TABLE public.pedidos ALTER COLUMN order_number SET DEFAULT nextval('pedidos_order_number_seq');

ALTER TABLE public.pedidos ALTER COLUMN order_number SET NOT NULL;

ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_order_number_unique UNIQUE (order_number);

-- 2. contatos: rename rua_numero → endereco, add complemento
ALTER TABLE public.contatos RENAME COLUMN rua_numero TO endereco;

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

-- 2. UPDATE CONSTRAINTS
ALTER TABLE lancamentos_socios 
  DROP CONSTRAINT IF EXISTS lancamentos_socios_socio_check,
  ADD CONSTRAINT lancamentos_socios_socio_check 
    CHECK (socio IN ('V', 'A', 'P'));

ALTER TABLE financeiro 
  DROP CONSTRAINT IF EXISTS financeiro_tipo_check,
  ADD CONSTRAINT financeiro_tipo_check 
    CHECK (tipo IN ('receita', 'despesa', 'receita_pendente'));

-- 1. UPDATE status_pagamento constraint to allow '-'
ALTER TABLE lancamentos_socios 
  DROP CONSTRAINT IF EXISTS lancamentos_socios_status_pagamento_check;

ALTER TABLE lancamentos_socios 
  ADD CONSTRAINT lancamentos_socios_status_pagamento_check 
    CHECK (status_pagamento IN ('pago', 'pendente', '-'));

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

-- Update canal_origem constraint to include C-REP
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP'));

-- Add 'entregue' to status_pedido CHECK constraint
ALTER TABLE public.pedidos DROP CONSTRAINT IF EXISTS pedidos_status_pedido_check;

ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_status_pedido_check CHECK (status_pedido IN ('aguardando_rastreio', 'postado', 'entregue'));

-- Fix: Ensure C-REP is in canal_origem constraint
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));

-- Fix timezone: pedidos.data must use America/Sao_Paulo date, not UTC
-- This ensures orders placed after 21h SP time get the correct Brazil date

-- 1. Change DEFAULT of pedidos.data to use Sao Paulo timezone
ALTER TABLE public.pedidos ALTER COLUMN data SET DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo')::date;

-- 3. Constraint UNIQUE para idempotencia (um item = uma movimentacao)
ALTER TABLE public.estoque_movimentacoes ADD CONSTRAINT estoque_movimentacoes_pedido_item_id_key UNIQUE (pedido_item_id);

-- ============================================================
-- 1. INSTANCIAS - Relaxar constraint e adicionar colunas
-- ============================================================

-- Remover constraint antiga que só允许 'ads' e 'base'
ALTER TABLE public.instancias DROP CONSTRAINT IF EXISTS instancias_tipo_check;

-- Adicionar nova constraint com 'rep'
ALTER TABLE public.instancias ADD CONSTRAINT instancias_tipo_check CHECK (tipo IN ('ads', 'base', 'rep'));

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
-- Fix: lancamentos_socios.data timezone + backfill
-- ============================================================

-- Fix column default to use Sao Paulo timezone
ALTER TABLE public.lancamentos_socios ALTER COLUMN data SET DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo')::date;

-- Migration: Inserir capital inicial dos sócios V e A
-- Substitui o hardcoded +49/+942 do frontend por registros reais no banco

-- Sócio V: Capital inicial R$ 49,00
-- Atualiza a constraint para permitir CAPITAL_INICIAL
ALTER TABLE public.lancamentos_socios DROP CONSTRAINT IF EXISTS lancamentos_socios_tipo_check;

ALTER TABLE public.lancamentos_socios ADD CONSTRAINT lancamentos_socios_tipo_check 
  CHECK (tipo IN ('VENDA', 'ADS', 'ETIQUETA', 'MATERIAL', 'LOGISTICA', 'TRANSFERENCIA', 'LUCRO', 'CAPITAL_INICIAL'));

-- Rename primeira_venda_em to ultima_venda_em and add FK
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contatos' AND column_name = 'primeira_venda_em') AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contatos' AND column_name = 'ultima_venda_em') THEN
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

-- Migration completa para rodar no Supabase SQL Editor AGORA
-- Este SQL renomeia a coluna e executa a migração na mesma execução

-- 1. Renomear coluna primeira_venda_em para ultima_venda_em
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contatos' AND column_name = 'primeira_venda_em') AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contatos' AND column_name = 'ultima_venda_em') THEN
      ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;
  END IF;
END $$;

-- Migration completa - renomeia coluna + executa migração
-- Rode este SQL no Supabase SQL Editor

-- 1. Renomear coluna
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contatos' AND column_name = 'primeira_venda_em') AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contatos' AND column_name = 'ultima_venda_em') THEN
      ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;
  END IF;
END $$;

-- Migration completa para rodar no Supabase SQL Editor
--一步到位: renomeia coluna + corrige dados existentes + triggers + migração

-- 1. Renomear coluna primeira_venda_em para ultima_venda_em
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contatos' AND column_name = 'primeira_venda_em') AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contatos' AND column_name = 'ultima_venda_em') THEN
      ALTER TABLE public.contatos RENAME COLUMN primeira_venda_em TO ultima_venda_em;
  END IF;
END $$;

-- Fix: Ensure C-REP is in canal_origem constraint (in case migration wasn't applied)
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));

-- Fix canal_origem check constraint to include C-REP
-- This is needed because the original table creation had a constraint without C-REP

ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

ALTER TABLE public.contatos ADD CONSTRAINT contatos_canal_origem_check 
  CHECK (canal_origem IS NULL OR canal_origem IN ('ADS', 'BASE', 'REP', 'C-REP', 'ADMIN'));

-- ULTIMATE FIX: Remove canal_origem constraint completely to allow any value
-- This was broken after adding C-REP because the constraint wasn't properly updated

-- Drop the check constraint completely
ALTER TABLE public.contatos DROP CONSTRAINT IF EXISTS contatos_canal_origem_check;

-- Add a simple NOT NULL constraint (no value restrictions)
ALTER TABLE public.contatos ALTER COLUMN canal_origem SET NOT NULL;

-- 0. Primeiro: permitir nulo na coluna estoque_processado
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado DROP NOT NULL;

ALTER TABLE public.pedidos ALTER COLUMN estoque_processado SET DEFAULT false;

-- 0. Permitir nulo
ALTER TABLE public.pedidos ALTER COLUMN estoque_processado DROP NOT NULL;

ALTER TABLE public.pedidos ALTER COLUMN estoque_processado SET DEFAULT false;

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

-- 3. AJUSTE NA ORDENAÇÃO DOS PEDIDOs (Para o frontend pegar a data correta)
-- Garante que o campo 'data' sempre exista para ordenação
ALTER TABLE public.estoque_movimentacoes ALTER COLUMN data SET DEFAULT NOW();

-- 3. AJUSTE NA ORDENAÇÃO DOS PEDIDOs (Para o frontend pegar a data correta)
-- Garante que o campo 'data' sempre exista para ordenação se for null
ALTER TABLE public.estoque_movimentacoes ALTER COLUMN data SET DEFAULT NOW();

-- 4. Indexes
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

-- 2. Index para performance de idempotencia
CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido_id ON public.estoque_movimentacoes(pedido_id);

CREATE INDEX IF NOT EXISTS idx_pedidos_estoque_processado ON public.pedidos(estoque_processado) WHERE estoque_processado = false;

CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido_id ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido_id ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_estoque_mov_pedido ON public.estoque_movimentacoes(pedido_id) WHERE pedido_id IS NOT NULL;

-- Index para busca por dono_tipo
CREATE INDEX IF NOT EXISTS idx_instancias_dono_tipo ON public.instancias(dono_tipo) WHERE dono_tipo = 'representante';

-- Index para busca por tipo_usuario e instancia_id
CREATE INDEX IF NOT EXISTS idx_perfis_usuario_tipo ON public.perfis_usuario(tipo_usuario);

CREATE INDEX IF NOT EXISTS idx_perfis_usuario_instancia ON public.perfis_usuario(instancia_id) WHERE instancia_id IS NOT NULL;

-- Index para filtro por instancia_id e tipo_origem
CREATE INDEX IF NOT EXISTS idx_pedidos_instancia ON public.pedidos(instancia_id) WHERE instancia_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pedidos_tipo_origem ON public.pedidos(tipo_origem) WHERE tipo_origem IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pedidos_contato ON public.pedidos(contato_id) WHERE contato_id IS NOT NULL;

-- Index para lotes de representante
CREATE INDEX IF NOT EXISTS idx_lotes_representante ON public.lotes(representante_id) WHERE representante_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_comissoes_representante ON public.comissoes(representante_id);

CREATE INDEX IF NOT EXISTS idx_comissoes_pedido ON public.comissoes(pedido_id);

CREATE INDEX IF NOT EXISTS idx_comissoes_status ON public.comissoes(status) WHERE status = 'pendente';

CREATE INDEX IF NOT EXISTS idx_notificacoes_user_lido ON public.notificacoes(user_id, lido) WHERE lido = false;

CREATE INDEX IF NOT EXISTS idx_pedidos_representante ON public.pedidos(representante_id) WHERE representante_id IS NOT NULL;

-- 2. Criar índices pedido_itens
CREATE INDEX IF NOT EXISTS idx_pedido_itens_pedido ON public.pedido_itens(pedido_id);

CREATE INDEX IF NOT EXISTS idx_pedido_itens_produto ON public.pedido_itens(produto_id);

CREATE INDEX IF NOT EXISTS idx_lancamentos_pedido ON public.lancamentos_socios(pedido_id) WHERE pedido_id IS NOT NULL;

-- 4. Criar índices para performance (se não existirem)
CREATE INDEX IF NOT EXISTS idx_pedidos_status_rastreio ON pedidos(status_pedido) WHERE status_pedido = 'aguardando_rastreio';

CREATE INDEX IF NOT EXISTS idx_pedidos_modalidade ON pedidos(modalidade) WHERE modalidade != 'entrega_maos';

CREATE INDEX IF NOT EXISTS idx_pedidos_uf_postagem ON pedidos(uf_postagem);

CREATE INDEX IF NOT EXISTS idx_pedidos_etiqueta_paga ON pedidos(etiqueta_paga) WHERE etiqueta_paga = false;

-- 2. Criar índice para buscas rápidas
CREATE INDEX IF NOT EXISTS idx_estoque_snapshots_produto_uf 
ON public.estoque_snapshots(produto_id, uf);

-- cria indice para performance
CREATE INDEX IF NOT EXISTS idx_produtos_peso ON public.produtos(peso);

-- 5. Functions & RPCs
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

-- 6. RLS & Policies
ALTER TABLE public.perfis_usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instancias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contatos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financeiro ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lancamentos_socios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque_movimentacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follow_up ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.log_atividades ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metas_mensais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remetentes_uf ENABLE ROW LEVEL SECURITY;
-- 2. Habilitar RLS
ALTER TABLE estoque_ufs ENABLE ROW LEVEL SECURITY;
-- Habilitar RLS
ALTER TABLE public.uf_regioes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own profile" ON public.perfis_usuario;
CREATE POLICY "Users can read own profile" ON public.perfis_usuario FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.perfis_usuario;
CREATE POLICY "Users can update own profile" ON public.perfis_usuario FOR UPDATE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authenticated users can read instancias" ON public.instancias;
CREATE POLICY "Authenticated users can read instancias" ON public.instancias FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can manage instancias" ON public.instancias;
CREATE POLICY "Authenticated users can manage instancias" ON public.instancias FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can read contatos" ON public.contatos;
CREATE POLICY "Authenticated users can read contatos" ON public.contatos FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert contatos" ON public.contatos;
CREATE POLICY "Authenticated users can insert contatos" ON public.contatos FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update contatos" ON public.contatos;
CREATE POLICY "Authenticated users can update contatos" ON public.contatos FOR UPDATE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can delete contatos" ON public.contatos;
CREATE POLICY "Authenticated users can delete contatos" ON public.contatos FOR DELETE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can read produtos" ON public.produtos;
CREATE POLICY "Authenticated users can read produtos" ON public.produtos FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can manage produtos" ON public.produtos;
CREATE POLICY "Authenticated users can manage produtos" ON public.produtos FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can read pedidos" ON public.pedidos;
CREATE POLICY "Authenticated users can read pedidos" ON public.pedidos FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert pedidos" ON public.pedidos;
CREATE POLICY "Authenticated users can insert pedidos" ON public.pedidos FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update pedidos" ON public.pedidos;
CREATE POLICY "Authenticated users can update pedidos" ON public.pedidos FOR UPDATE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can delete pedidos" ON public.pedidos;
CREATE POLICY "Authenticated users can delete pedidos" ON public.pedidos FOR DELETE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can read financeiro" ON public.financeiro;
CREATE POLICY "Authenticated users can read financeiro" ON public.financeiro FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert financeiro" ON public.financeiro;
CREATE POLICY "Authenticated users can insert financeiro" ON public.financeiro FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update financeiro" ON public.financeiro;
CREATE POLICY "Authenticated users can update financeiro" ON public.financeiro FOR UPDATE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can delete financeiro" ON public.financeiro;
CREATE POLICY "Authenticated users can delete financeiro" ON public.financeiro FOR DELETE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can read lancamentos_socios" ON public.lancamentos_socios;
CREATE POLICY "Authenticated users can read lancamentos_socios" ON public.lancamentos_socios FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert lancamentos_socios" ON public.lancamentos_socios;
CREATE POLICY "Authenticated users can insert lancamentos_socios" ON public.lancamentos_socios FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update lancamentos_socios" ON public.lancamentos_socios;
CREATE POLICY "Authenticated users can update lancamentos_socios" ON public.lancamentos_socios FOR UPDATE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can delete lancamentos_socios" ON public.lancamentos_socios;
CREATE POLICY "Authenticated users can delete lancamentos_socios" ON public.lancamentos_socios FOR DELETE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can read estoque_movimentacoes" ON public.estoque_movimentacoes;
CREATE POLICY "Authenticated users can read estoque_movimentacoes" ON public.estoque_movimentacoes FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert estoque_movimentacoes" ON public.estoque_movimentacoes;
CREATE POLICY "Authenticated users can insert estoque_movimentacoes" ON public.estoque_movimentacoes FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can read follow_up" ON public.follow_up;
CREATE POLICY "Authenticated users can read follow_up" ON public.follow_up FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can manage follow_up" ON public.follow_up;
CREATE POLICY "Authenticated users can manage follow_up" ON public.follow_up FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can read log_atividades" ON public.log_atividades;
CREATE POLICY "Authenticated users can read log_atividades" ON public.log_atividades FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert log_atividades" ON public.log_atividades;
CREATE POLICY "Authenticated users can insert log_atividades" ON public.log_atividades FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can read configuracoes" ON public.configuracoes;
CREATE POLICY "Authenticated users can read configuracoes" ON public.configuracoes FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can manage configuracoes" ON public.configuracoes;
CREATE POLICY "Authenticated users can manage configuracoes" ON public.configuracoes FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can read lotes" ON public.lotes;
CREATE POLICY "Authenticated users can read lotes" ON public.lotes FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can manage lotes" ON public.lotes;
CREATE POLICY "Authenticated users can manage lotes" ON public.lotes FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Users can manage own metas" ON public.metas_mensais;
CREATE POLICY "Users can manage own metas" ON public.metas_mensais FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authenticated users can manage remetentes_uf" ON public.remetentes_uf;
CREATE POLICY "Authenticated users can manage remetentes_uf" ON public.remetentes_uf FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated can read estoque_ufs" ON public.estoque_ufs;
-- 3. Policy de leitura pública (autenticados)
CREATE POLICY "Authenticated can read estoque_ufs" ON estoque_ufs
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated can insert estoque_ufs" ON public.estoque_ufs;
-- 4. Policy de inserção (autenticados)
CREATE POLICY "Authenticated can insert estoque_ufs" ON estoque_ufs
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated can delete estoque_ufs" ON public.estoque_ufs;
-- 5. Policy de deleção (autenticados)
CREATE POLICY "Authenticated can delete estoque_ufs" ON estoque_ufs
  FOR DELETE TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated can read uf_regioes" ON public.uf_regioes;
CREATE POLICY "Authenticated can read uf_regioes" ON public.uf_regioes
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated can insert uf_regioes" ON public.uf_regioes;
CREATE POLICY "Authenticated can insert uf_regioes" ON public.uf_regioes
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated can delete uf_regioes" ON public.uf_regioes;
CREATE POLICY "Authenticated can delete uf_regioes" ON public.uf_regioes
  FOR DELETE TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.perfis_usuario;
-- Policy de INSERT (faltando) — permite frontend autenticado criar perfil próprio
CREATE POLICY "Users can insert own profile"
ON public.perfis_usuario FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 7. Triggers
DROP TRIGGER IF EXISTS "trigger_abate_estoque_pedido" ON public.pedidos;
CREATE TRIGGER trigger_abate_estoque_pedido
AFTER INSERT ON public.pedidos
FOR EACH ROW
EXECUTE FUNCTION public.abate_estoque_pedido();

DROP TRIGGER IF EXISTS "trg_processar_pedido_estoque" ON public.pedidos;
CREATE TRIGGER trg_processar_pedido_estoque AFTER INSERT ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.trigger_abate_estoque_pedido();

DROP TRIGGER IF EXISTS "trg_uf_postagem_update" ON public.pedidos;
-- Trigger recriado vai detectar mudança de qualquer UF
CREATE TRIGGER trg_uf_postagem_update 
AFTER UPDATE OF uf_postagem ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.trigger_uf_postagem_update();

DROP TRIGGER IF EXISTS "trg_comissao_pedido_postado" ON public.pedidos;
CREATE TRIGGER trg_comissao_pedido_postado
  AFTER UPDATE OF status_pedido ON public.pedidos
  FOR EACH ROW
  WHEN (NEW.status_pedido = 'postado' AND OLD.status_pedido != 'postado')
  EXECUTE FUNCTION public.trg_comissao_pedido_postado();

DROP TRIGGER IF EXISTS "on_auth_user_created" ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS "trigger_update_ultima_venda" ON public.lancamentos_socios;
CREATE TRIGGER trigger_update_ultima_venda 
AFTER INSERT ON public.lancamentos_socios 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_lancamento();

DROP TRIGGER IF EXISTS "trigger_update_ultima_venda_pedido" ON public.pedidos;
CREATE TRIGGER trigger_update_ultima_venda_pedido 
AFTER INSERT ON public.pedidos 
FOR EACH ROW EXECUTE FUNCTION public.update_ultima_venda_on_pedido();

DROP TRIGGER IF EXISTS "tg_abate_estoque_pedido" ON public.pedidos;
CREATE TRIGGER tg_abate_estoque_pedido
  BEFORE INSERT ON public.pedidos
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_abate_estoque_pedido();

DROP TRIGGER IF EXISTS "trg_novo_pedido_estoque" ON public.pedidos;
CREATE TRIGGER trg_novo_pedido_estoque AFTER INSERT ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.trigger_novo_pedido_estoque();

-- 8. Post-Structure Initialization (setval, etc)
-- Backfill existing rows
DO $$
BEGIN
  EXECUTE 'UPDATE public.pedidos SET order_number = nextval(''pedidos_order_number_seq'') WHERE order_number IS NULL;';
END $$;

-- Ensure columns exist before backfill
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS cidade text;
ALTER TABLE public.contatos ADD COLUMN IF NOT EXISTS uf text;

-- Backfill cidade and uf from cidade_uf
-- Backfill cidade and uf from cidade_uf (direct update without EXECUTE)
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
      EXECUTE 'UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;';
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, observacao)
      VALUES (v_ped.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, 'Pedido #' || v_ped.id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    -- Decrementa estoque
    UPDATE produtos SET estoque_atual = estoque_atual - v_ped.quantidade WHERE id = v_ped.produto_id;

    RAISE NOTICE 'Reprocessado pedido %: produto %, quantidade %', v_ped.id, v_ped.produto_id, v_ped.quantidade;
  END LOOP;
END $$;

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
      EXECUTE 'UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;';
      INSERT INTO estoque_movimentacoes (produto_id, quantidade, tipo, posse, lote_id, uf_origem, pedido_item_id, observacao)
      VALUES (v_item.produto_id, v_deduct, 'saida', 'Venda', v_lote_rec.id, v_lote_rec.uf, v_item.id, 'Pedido #' || v_item.pedido_id::text);
      v_remaining := v_remaining - v_deduct;
    END LOOP;

    UPDATE produtos SET estoque_atual = estoque_atual - v_item.quantidade WHERE id = v_item.produto_id;
    RAISE NOTICE 'Reprocessado item %: produto %, quantidade %', v_item.id, v_item.produto_id, v_item.quantidade;
  END LOOP;
END $$;

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
      EXECUTE 'UPDATE estoque_movimentacoes 
      SET pedido_id = v_ped.id, observacao = ''Pedido #'' || v_ped.id::text
      WHERE pedido_id IS NULL AND tipo = ''saida''
        AND created_at >= v_ped.created_at - interval ''1 second''
        AND created_at <= v_ped.created_at + interval ''5 seconds'';';
      
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
            EXECUTE 'UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;';
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
            EXECUTE 'UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;';
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
            EXECUTE 'UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;';
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
            EXECUTE 'UPDATE lotes SET quantidade_atual = quantidade_atual - v_deduct WHERE id = v_lote_rec.id;';
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

  RAISE NOTICE '=== Major EXECUTE Update V2 - Fase 1 ===';
  RAISE NOTICE 'Contatos Admin criados: %', v_contatos_admin;
  RAISE NOTICE 'Pedidos vinculados a contato: %', v_pedidos_vinculados;
  RAISE NOTICE 'Contatos com instancia_id: %', v_contatos_com_instancia;
END $$;

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

-- 5. MANUTENÇÃO: Recalcular estoque_atual baseado em movimentações reais
-- Isso limpa erros de conta acumulados
DO $$
DECLARE
  v_rec record;
BEGIN
  FOR v_rec IN SELECT id FROM public.produtos LOOP
    EXECUTE 'UPDATE public.produtos p
    SET estoque_atual = (
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = ''entrada''), 0) -
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = ''saida''), 0)
    )
    WHERE p.id = v_rec.id;';
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

-- 3. REPROCESSO: Atualiza estoque_atual dos produtos e snapshot
DO $$
DECLARE
  v_rec record;
BEGIN
  FOR v_rec IN SELECT id FROM public.produtos LOOP
    EXECUTE 'UPDATE public.produtos p
    SET estoque_atual = (
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = ''entrada''), 0) -
      COALESCE((SELECT SUM(quantidade) FROM public.estoque_movimentacoes WHERE produto_id = v_rec.id AND tipo = ''saida''), 0)
    )
    WHERE p.id = v_rec.id;';
  END LOOP;
END $$;

-- Atualiza snapshot (safe check)
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_proc WHERE proname = 'atualizar_estoque_snapshot') THEN
      PERFORM public.atualizar_estoque_snapshot();
  END IF;
END $$;

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
    EXECUTE 'UPDATE public.produtos SET estoque_atual = v_entradas - v_saidas WHERE id = v_prod.id;';
  END LOOP;
END $$;

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

-- Inicia a partir do max atual
SELECT setval('public.pedidos_order_number_seq', COALESCE(MAX(order_number), 1)) FROM public.pedidos;

-- Remove agendamento anterior (se existir) para evitar duplicidade
DO $$
BEGIN
  PERFORM cron.unschedule('superfrete-sync-every-5min');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 2. Inicializa com valor atual max
SELECT setval('public.pedidos_order_number_seq', COALESCE((SELECT MAX(order_number) FROM public.pedidos), 1), false);

-- Final configuration
SET search_path = public, auth, extensions;

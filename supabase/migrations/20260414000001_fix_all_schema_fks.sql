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

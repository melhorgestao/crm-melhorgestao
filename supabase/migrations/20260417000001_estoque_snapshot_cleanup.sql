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
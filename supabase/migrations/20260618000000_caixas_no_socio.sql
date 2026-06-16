-- ============================================================================
-- Caixas — entidades de recebimento que NÃO são sócios
--
-- Recebimentos do bot em crypto (DeFlow ou outros gateways) precisam ser
-- registrados em "caixas" sem mexer com Vendedor/Administrador. Caixas:
-- - Recebem vendas e parcelas
-- - Realizam transferências (despesas, repasses)
-- - NÃO participam de divisão de lucro
-- - NÃO recebem transferência interna entre sócios
-- - Limite: até 5 caixas (codigos C1..C5)
-- ============================================================================

-- 1) Tabela caixas
CREATE TABLE IF NOT EXISTS public.caixas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      text NOT NULL UNIQUE
              CHECK (codigo ~ '^C[1-5]$'),
  apelido     text NOT NULL,
  ativo       boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.caixas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read caixas"   ON public.caixas;
DROP POLICY IF EXISTS "Authenticated manage caixas" ON public.caixas;

CREATE POLICY "Authenticated read caixas"
  ON public.caixas FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated manage caixas"
  ON public.caixas FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

COMMENT ON TABLE public.caixas IS
  'Caixas de recebimento não-sócio (ex: carteira crypto DeFlow). Não divide lucro.';

-- 2) Relaxa CHECK constraint de lancamentos_socios.socio pra aceitar C1..C5
ALTER TABLE public.lancamentos_socios
  DROP CONSTRAINT IF EXISTS lancamentos_socios_socio_check;

ALTER TABLE public.lancamentos_socios
  ADD CONSTRAINT lancamentos_socios_socio_check
  CHECK (socio IN ('V', 'A', 'P') OR socio ~ '^C[1-5]$');

-- 3) RPC criar_caixa: aloca próximo código livre (C1..C5) com apelido
CREATE OR REPLACE FUNCTION public.criar_caixa(p_apelido text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_codigo text;
  v_id     uuid;
  v_apelido text := trim(p_apelido);
BEGIN
  IF v_apelido IS NULL OR v_apelido = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apelido obrigatório');
  END IF;

  -- procura primeiro código C1..C5 que ainda não existe
  WITH candidatos(codigo) AS (VALUES ('C1'),('C2'),('C3'),('C4'),('C5'))
  SELECT c.codigo INTO v_codigo
    FROM candidatos c
   WHERE NOT EXISTS (SELECT 1 FROM public.caixas k WHERE k.codigo = c.codigo)
   ORDER BY c.codigo
   LIMIT 1;

  IF v_codigo IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error',
      'limite de 5 caixas atingido');
  END IF;

  INSERT INTO public.caixas (codigo, apelido)
  VALUES (v_codigo, v_apelido)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id,
                            'codigo', v_codigo, 'apelido', v_apelido);
END $$;

GRANT EXECUTE ON FUNCTION public.criar_caixa(text)
  TO authenticated, service_role;

-- 4) RPC listar_caixas: caixas ativas (sem inativas)
CREATE OR REPLACE FUNCTION public.listar_caixas()
RETURNS TABLE (codigo text, apelido text, ativo boolean)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT codigo, apelido, ativo
    FROM public.caixas
   WHERE ativo = true
   ORDER BY codigo;
$$;

GRANT EXECUTE ON FUNCTION public.listar_caixas()
  TO authenticated, service_role, anon;

-- 5) RPC renomear_caixa: muda apelido sem perder histórico
CREATE OR REPLACE FUNCTION public.renomear_caixa(p_codigo text, p_apelido text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_apelido text := trim(p_apelido);
BEGIN
  IF v_apelido IS NULL OR v_apelido = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apelido obrigatório');
  END IF;

  UPDATE public.caixas
     SET apelido = v_apelido, updated_at = now()
   WHERE codigo = p_codigo AND ativo = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'caixa não encontrada');
  END IF;

  RETURN jsonb_build_object('ok', true, 'codigo', p_codigo, 'apelido', v_apelido);
END $$;

GRANT EXECUTE ON FUNCTION public.renomear_caixa(text, text)
  TO authenticated, service_role;

-- 6) RPC desativar_caixa: caixa some da UI mas histórico fica preservado
CREATE OR REPLACE FUNCTION public.desativar_caixa(p_codigo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.caixas
     SET ativo = false, updated_at = now()
   WHERE codigo = p_codigo;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'caixa não encontrada');
  END IF;

  RETURN jsonb_build_object('ok', true, 'codigo', p_codigo);
END $$;

GRANT EXECUTE ON FUNCTION public.desativar_caixa(text)
  TO authenticated, service_role;

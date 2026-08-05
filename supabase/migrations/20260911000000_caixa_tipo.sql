-- ============================================================================
-- Tipo de caixa (cripto / cartao / pix) — usado só pra tema visual no
-- Financeiro (gradiente + ícone). Não afeta a lógica de saldo/lucro.
-- ============================================================================

ALTER TABLE public.caixas
  ADD COLUMN IF NOT EXISTS tipo text NOT NULL DEFAULT 'cripto';

-- caixas existentes (ex.: DeFlow) já são gateways cripto → default 'cripto' serve.

-- criar_caixa agora aceita p_tipo. Recria (drop + create) por causa da assinatura.
DROP FUNCTION IF EXISTS public.criar_caixa(text);

CREATE OR REPLACE FUNCTION public.criar_caixa(p_apelido text, p_tipo text DEFAULT 'cripto')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_codigo  text;
  v_id      uuid;
  v_apelido text := trim(p_apelido);
  v_tipo    text := lower(coalesce(p_tipo, 'cripto'));
BEGIN
  IF v_apelido IS NULL OR v_apelido = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apelido obrigatório');
  END IF;
  IF v_tipo NOT IN ('cripto', 'cartao', 'pix') THEN v_tipo := 'cripto'; END IF;

  WITH candidatos(codigo) AS (VALUES ('C1'),('C2'),('C3'),('C4'),('C5'))
  SELECT c.codigo INTO v_codigo
    FROM candidatos c
   WHERE NOT EXISTS (SELECT 1 FROM public.caixas k WHERE k.codigo = c.codigo)
   ORDER BY c.codigo
   LIMIT 1;

  IF v_codigo IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'limite de 5 caixas atingido');
  END IF;

  INSERT INTO public.caixas (codigo, apelido, tipo)
  VALUES (v_codigo, v_apelido, v_tipo)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'codigo', v_codigo, 'apelido', v_apelido, 'tipo', v_tipo);
END $$;

GRANT EXECUTE ON FUNCTION public.criar_caixa(text, text)
  TO authenticated, service_role;

-- listar_caixas passa a devolver o tipo (muda a assinatura → drop + create).
DROP FUNCTION IF EXISTS public.listar_caixas();

CREATE OR REPLACE FUNCTION public.listar_caixas()
RETURNS TABLE (codigo text, apelido text, ativo boolean, tipo text)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT codigo, apelido, ativo, tipo
    FROM public.caixas
   WHERE ativo = true
   ORDER BY codigo;
$$;

GRANT EXECUTE ON FUNCTION public.listar_caixas()
  TO authenticated, service_role, anon;

NOTIFY pgrst, 'reload schema';

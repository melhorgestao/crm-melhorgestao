-- ============================================================================
-- FIX: obter_config_frete quebrava com 'column "created_at" does not exist'.
-- Tabela remetentes_uf tem apenas updated_at — não created_at.
--
-- Resultado: consultar-frete-agent NUNCA conseguia ler from_cep do banco,
-- caía no fallback '05010000' (CEP estranho, Superfrete recusava).
--
-- Nova versão:
--  - Aceita p_uf_origem (priorizada) ou pega 1ª UF com cep_origem cadastrado
--  - Ordena por uf ASC (determinístico, sem coluna inexistente)
--  - Retorna também 'uf_origem' pra debug
-- ============================================================================

CREATE OR REPLACE FUNCTION public.obter_config_frete(
  p_to_cep    text DEFAULT NULL,
  p_uf_origem text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cep_origem text;
  v_uf_origem  text;
  v_peso_g     int;
BEGIN
  -- 1) Se passou UF, tenta direto
  IF p_uf_origem IS NOT NULL THEN
    SELECT uf, cep_origem INTO v_uf_origem, v_cep_origem
      FROM public.remetentes_uf
     WHERE uf = UPPER(p_uf_origem) AND cep_origem IS NOT NULL
     LIMIT 1;
  END IF;

  -- 2) Fallback: pega 1ª UF com cep_origem cadastrado (ordem alfabética)
  IF v_cep_origem IS NULL THEN
    SELECT uf, cep_origem INTO v_uf_origem, v_cep_origem
      FROM public.remetentes_uf
     WHERE cep_origem IS NOT NULL
     ORDER BY uf ASC
     LIMIT 1;
  END IF;

  -- 3) Último fallback (não deveria acontecer se tem cep_origem cadastrado)
  v_cep_origem := COALESCE(v_cep_origem, '92035575');
  v_uf_origem  := COALESCE(v_uf_origem, 'RS');

  -- Normaliza CEP (só dígitos)
  v_cep_origem := regexp_replace(v_cep_origem, '\D', '', 'g');

  SELECT NULLIF(valor,'')::int INTO v_peso_g
    FROM public.configuracoes WHERE chave = 'agent_peso_unitario_g';

  RETURN jsonb_build_object(
    'from_cep',         v_cep_origem,
    'uf_origem',        v_uf_origem,
    'peso_unitario_g',  COALESCE(v_peso_g, 300)
  );
END $$;

GRANT EXECUTE ON FUNCTION public.obter_config_frete(text, text)
  TO anon, authenticated, service_role;

-- Mantém compat com chamadas antigas que passam só p_to_cep
DROP FUNCTION IF EXISTS public.obter_config_frete(text);

NOTIFY pgrst, 'reload schema';

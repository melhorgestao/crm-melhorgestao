-- ============================================================================
-- Conversas por instância: período selecionável (hoje/ontem/semana/mês) e
-- semântica clara das duas setas:
--   ↓ recebidas = contatos DISTINTOS que mandaram mensagem no período
--                 (1 por conversa, mesmo respondendo — conta na de baixo).
--   ↑ abertas   = contatos DISTINTOS que a instância abriu (out SEM in no
--                 período) — disparo/proativo. Mutuamente exclusivo de recebidas.
-- ============================================================================

DROP FUNCTION IF EXISTS public.instancia_metricas(uuid);

CREATE OR REPLACE FUNCTION public.instancia_metricas(
  p_id      uuid,
  p_periodo text DEFAULT 'hoje'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_result   jsonb;
  v_clientes int;
  v_ads int;
  v_base int;
  v_rep int;
  v_conv_in int;
  v_conv_out int;
  v_hoje date;
  v_ini  date;
  v_fim  date;
BEGIN
  SELECT
    count(*) FILTER (WHERE ja_comprou),
    count(*) FILTER (WHERE canal_origem = 'ADS'),
    count(*) FILTER (WHERE canal_origem = 'BASE'),
    count(*) FILTER (WHERE canal_origem IN ('REP','C-REP'))
  INTO v_clientes, v_ads, v_base, v_rep
  FROM public.contatos
  WHERE instancia_id = p_id;

  -- Janela do período em horário de Brasília
  v_hoje := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  CASE lower(COALESCE(p_periodo, 'hoje'))
    WHEN 'ontem'  THEN v_ini := v_hoje - 1;                        v_fim := v_hoje;
    WHEN 'semana' THEN v_ini := date_trunc('week',  v_hoje)::date; v_fim := v_hoje + 1;
    WHEN 'mes'    THEN v_ini := date_trunc('month', v_hoje)::date; v_fim := v_hoje + 1;
    ELSE               v_ini := v_hoje;                            v_fim := v_hoje + 1;  -- hoje
  END CASE;

  BEGIN
    WITH agg AS (
      SELECT contato_id,
             bool_or(direcao = 'in')  AS tem_in,
             bool_or(direcao = 'out') AS tem_out
      FROM public.mensagens_buffer
      WHERE instancia_id = p_id
        AND contato_id IS NOT NULL
        AND (recebida_em AT TIME ZONE 'America/Sao_Paulo')::date >= v_ini
        AND (recebida_em AT TIME ZONE 'America/Sao_Paulo')::date <  v_fim
      GROUP BY contato_id
    )
    SELECT
      count(*) FILTER (WHERE tem_in),                    -- recebidas
      count(*) FILTER (WHERE tem_out AND NOT tem_in)     -- abertas (out sem in)
    INTO v_conv_in, v_conv_out
    FROM agg;
  EXCEPTION WHEN undefined_table THEN
    v_conv_in := 0;
    v_conv_out := 0;
  END;

  v_result := jsonb_build_object(
    'clientes',  COALESCE(v_clientes, 0),
    'ads',       COALESCE(v_ads, 0),
    'base',      COALESCE(v_base, 0),
    'rep',       COALESCE(v_rep, 0),
    'conv_in',   COALESCE(v_conv_in, 0),   -- ↓ recebidas
    'conv_out',  COALESCE(v_conv_out, 0)   -- ↑ abertas
  );

  RETURN v_result;
END; $$;

GRANT EXECUTE ON FUNCTION public.instancia_metricas(uuid, text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

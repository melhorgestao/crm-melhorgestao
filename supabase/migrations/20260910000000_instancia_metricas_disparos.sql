-- ============================================================================
-- Terceira métrica de conversas por instância: DISPAROS.
--   ↓ recebidas (conv_in)  = contatos que ESCREVERAM no período.
--   ↑ abertas   (conv_out) = contatos abertos A FRIO (out SEM in) — inalterado,
--                            mutuamente exclusivo com recebidas.
--   ✉ disparos  (disparos) = contatos que receberam disparo (campanha_envios)
--                            no período — INDEPENDENTE, pode sobrepor com as
--                            outras (é o volume real de follow-up/RMKT enviado).
-- ============================================================================

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
  v_conv_in int := 0;
  v_conv_out int := 0;
  v_disparos int := 0;
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

  v_hoje := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  CASE lower(COALESCE(p_periodo, 'hoje'))
    WHEN 'ontem'  THEN v_ini := v_hoje - 1;                        v_fim := v_hoje;
    WHEN 'semana' THEN v_ini := date_trunc('week',  v_hoje)::date; v_fim := v_hoje + 1;
    WHEN 'mes'    THEN v_ini := date_trunc('month', v_hoje)::date; v_fim := v_hoje + 1;
    ELSE               v_ini := v_hoje;                            v_fim := v_hoje + 1;  -- hoje
  END CASE;

  -- recebidas / abertas (mutuamente exclusivas)
  BEGIN
    WITH ins AS (
      SELECT DISTINCT contato_id
        FROM public.mensagens_buffer
       WHERE instancia_id = p_id AND contato_id IS NOT NULL AND direcao = 'in'
         AND (recebida_em AT TIME ZONE 'America/Sao_Paulo')::date >= v_ini
         AND (recebida_em AT TIME ZONE 'America/Sao_Paulo')::date <  v_fim
    ),
    outs AS (
      SELECT DISTINCT contato_id
        FROM public.mensagens_buffer
       WHERE instancia_id = p_id AND contato_id IS NOT NULL AND direcao = 'out'
         AND (recebida_em AT TIME ZONE 'America/Sao_Paulo')::date >= v_ini
         AND (recebida_em AT TIME ZONE 'America/Sao_Paulo')::date <  v_fim
      UNION
      SELECT DISTINCT contato_id
        FROM public.campanha_envios
       WHERE instancia_id = p_id AND contato_id IS NOT NULL
         AND (enviado_em AT TIME ZONE 'America/Sao_Paulo')::date >= v_ini
         AND (enviado_em AT TIME ZONE 'America/Sao_Paulo')::date <  v_fim
    )
    SELECT
      (SELECT count(*) FROM ins),
      (SELECT count(*) FROM outs o WHERE o.contato_id NOT IN (SELECT contato_id FROM ins))
    INTO v_conv_in, v_conv_out;
  EXCEPTION WHEN undefined_table THEN
    v_conv_in := 0; v_conv_out := 0;
  END;

  -- disparos (independente — todos os envios de campanha no período)
  BEGIN
    SELECT count(DISTINCT contato_id)
      INTO v_disparos
      FROM public.campanha_envios
     WHERE instancia_id = p_id AND contato_id IS NOT NULL
       AND (enviado_em AT TIME ZONE 'America/Sao_Paulo')::date >= v_ini
       AND (enviado_em AT TIME ZONE 'America/Sao_Paulo')::date <  v_fim;
  EXCEPTION WHEN undefined_table THEN
    v_disparos := 0;
  END;

  v_result := jsonb_build_object(
    'clientes',  COALESCE(v_clientes, 0),
    'ads',       COALESCE(v_ads, 0),
    'base',      COALESCE(v_base, 0),
    'rep',       COALESCE(v_rep, 0),
    'conv_in',   COALESCE(v_conv_in, 0),    -- ↓ recebidas
    'conv_out',  COALESCE(v_conv_out, 0),   -- ↑ abertas (frio)
    'disparos',  COALESCE(v_disparos, 0)    -- ✉ disparos (volume real)
  );

  RETURN v_result;
END; $$;

GRANT EXECUTE ON FUNCTION public.instancia_metricas(uuid, text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

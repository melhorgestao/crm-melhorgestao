-- ============================================================================
-- Sistema: visibilidade dos pg_cron jobs + execução manual + alerta em falha.
-- RPCs:
--   listar_crons_status()       — lista jobs com última execução, status, próxima
--   executar_cron_agora(jobname) — força execução imediata (re-roda o command)
--   marca_falha_cron_alertada() — controle pra não spammar alerta no mesmo run
--
-- Cron novo:
--   monitor-crons-falhas (a cada 1h) — verifica falhas nas últimas 24h e
--                                       dispara WhatsApp para alerta_admin.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Tabela de tracking de alertas (evita duplicar mensagem)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cron_alertas_enviados (
  job_run_id  bigint PRIMARY KEY,
  jobname     text NOT NULL,
  alertado_em timestamptz NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 2) RPC: lista jobs com status da última execução
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_crons_status()
RETURNS TABLE (
  jobid          bigint,
  jobname        text,
  schedule       text,
  command        text,
  active         boolean,
  last_run_id    bigint,
  last_start     timestamptz,
  last_end       timestamptz,
  last_status    text,
  last_message   text,
  duration_ms    integer,
  runs_24h       integer,
  failures_24h   integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = cron, public AS $$
BEGIN
  RETURN QUERY
  WITH last AS (
    SELECT DISTINCT ON (jrd.jobid)
      jrd.jobid, jrd.runid, jrd.start_time, jrd.end_time,
      jrd.status, jrd.return_message,
      EXTRACT(MILLISECONDS FROM (jrd.end_time - jrd.start_time))::int AS dur_ms
    FROM cron.job_run_details jrd
    ORDER BY jrd.jobid, jrd.start_time DESC
  ),
  stats AS (
    SELECT
      jobid,
      count(*)::int AS runs,
      count(*) FILTER (WHERE status = 'failed')::int AS failures
    FROM cron.job_run_details
    WHERE start_time > NOW() - INTERVAL '24 hours'
    GROUP BY jobid
  )
  SELECT
    j.jobid,
    j.jobname,
    j.schedule,
    j.command,
    j.active,
    l.runid,
    l.start_time,
    l.end_time,
    l.status,
    l.return_message,
    l.dur_ms,
    COALESCE(s.runs, 0),
    COALESCE(s.failures, 0)
  FROM cron.job j
  LEFT JOIN last  l ON l.jobid = j.jobid
  LEFT JOIN stats s ON s.jobid = j.jobid
  ORDER BY j.jobname;
END $$;

GRANT EXECUTE ON FUNCTION public.listar_crons_status() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) RPC: executa command de um cron agora
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.executar_cron_agora(p_jobname text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = cron, public AS $$
DECLARE
  v_command text;
BEGIN
  SELECT command INTO v_command FROM cron.job WHERE jobname = p_jobname;
  IF v_command IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'job não encontrado');
  END IF;

  -- Executa o command como SQL dinâmico
  BEGIN
    EXECUTE v_command;
    RETURN jsonb_build_object('ok', true, 'jobname', p_jobname, 'executed_at', NOW());
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'jobname', p_jobname, 'error', SQLERRM);
  END;
END $$;

GRANT EXECUTE ON FUNCTION public.executar_cron_agora(text) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4) RPC: lista últimas N execuções de um job
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_cron_execucoes(p_jobid bigint, p_limit int DEFAULT 20)
RETURNS TABLE (
  runid        bigint,
  start_time   timestamptz,
  end_time     timestamptz,
  status       text,
  return_message text,
  duration_ms  integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = cron, public AS $$
BEGIN
  RETURN QUERY
  SELECT
    jrd.runid,
    jrd.start_time,
    jrd.end_time,
    jrd.status,
    jrd.return_message,
    EXTRACT(MILLISECONDS FROM (jrd.end_time - jrd.start_time))::int
  FROM cron.job_run_details jrd
  WHERE jrd.jobid = p_jobid
  ORDER BY jrd.start_time DESC
  LIMIT p_limit;
END $$;

GRANT EXECUTE ON FUNCTION public.listar_cron_execucoes(bigint, int) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5) Monitor de falhas + alerta WhatsApp via pg_net
--    Roda a cada hora. Para falhas não alertadas das últimas 24h, dispara
--    POST direto pra Evolution da instância marcada alerta_admin.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.monitor_crons_falhas()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = cron, public AS $$
DECLARE
  v_fail        record;
  v_admin       record;
  v_telefone    text;
  v_msg         text;
BEGIN
  -- Pega instância admin com telefone configurado
  SELECT evolution_url, evolution_instance, evolution_apikey, alerta_telefone, nome
    INTO v_admin
    FROM public.instancias
   WHERE alerta_admin = true AND status = 'ativo' AND ativo = true
   LIMIT 1;

  IF v_admin IS NULL OR v_admin.alerta_telefone IS NULL THEN RETURN; END IF;

  v_telefone := regexp_replace(v_admin.alerta_telefone, '\D', '', 'g');
  IF length(v_telefone) < 10 THEN RETURN; END IF;
  IF NOT v_telefone LIKE '55%' THEN v_telefone := '55' || v_telefone; END IF;

  -- Para cada falha não-alertada
  FOR v_fail IN
    SELECT jrd.runid, j.jobname, jrd.start_time, jrd.return_message
      FROM cron.job_run_details jrd
      JOIN cron.job j ON j.jobid = jrd.jobid
     WHERE jrd.status = 'failed'
       AND jrd.start_time > NOW() - INTERVAL '24 hours'
       AND NOT EXISTS (
         SELECT 1 FROM public.cron_alertas_enviados a WHERE a.job_run_id = jrd.runid
       )
     ORDER BY jrd.start_time DESC
     LIMIT 10
  LOOP
    v_msg := format(
      '🚨 CRON FALHOU%s%sJob: %s%sQuando: %s%sErro: %s',
      E'\n\n',
      '',
      v_fail.jobname,
      E'\n',
      to_char(v_fail.start_time AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI'),
      E'\n',
      substring(COALESCE(v_fail.return_message, 'sem mensagem'), 1, 200)
    );

    PERFORM net.http_post(
      url     := v_admin.evolution_url || '/message/sendText/' ||
                 replace(v_admin.evolution_instance, ' ', '%20'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey',       v_admin.evolution_apikey
      ),
      body    := jsonb_build_object(
        'number', v_telefone,
        'text',   v_msg,
        'delay',  1500
      ),
      timeout_milliseconds := 5000
    );

    INSERT INTO public.cron_alertas_enviados (job_run_id, jobname)
    VALUES (v_fail.runid, v_fail.jobname);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.monitor_crons_falhas() TO authenticated, service_role;

-- Agenda o monitor a cada hora (00 minutos)
SELECT cron.schedule(
  'monitor-crons-falhas',
  '0 * * * *',
  'SELECT public.monitor_crons_falhas();'
);

NOTIFY pgrst, 'reload schema';

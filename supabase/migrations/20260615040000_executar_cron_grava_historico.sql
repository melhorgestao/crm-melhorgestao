-- ============================================================================
-- executar_cron_agora agora também GRAVA a execução em cron.job_run_details
-- pra UI refletir o status correto após "Rodar agora".
-- Sem isso, last_status fica preso na última execução automática (mesmo se
-- a manual passou ok).
-- ============================================================================

DROP FUNCTION IF EXISTS public.executar_cron_agora(text);

CREATE OR REPLACE FUNCTION public.executar_cron_agora(p_jobname text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = cron, public AS $$
DECLARE
  v_command text;
  v_jobid   bigint;
  v_start   timestamptz;
  v_end     timestamptz;
  v_status  text;
  v_message text;
BEGIN
  SELECT command, jobid INTO v_command, v_jobid
    FROM cron.job WHERE jobname = p_jobname;
  IF v_command IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'job não encontrado');
  END IF;

  v_start := NOW();

  -- Tenta executar o command
  BEGIN
    EXECUTE v_command;
    v_status  := 'succeeded';
    v_message := 'manual run via UI';
  EXCEPTION WHEN OTHERS THEN
    v_status  := 'failed';
    v_message := SQLERRM;
  END;

  v_end := NOW();

  -- Registra em cron.job_run_details (best-effort)
  BEGIN
    INSERT INTO cron.job_run_details (
      jobid, runid, job_pid, database, username, command,
      status, return_message, start_time, end_time
    )
    VALUES (
      v_jobid,
      COALESCE((SELECT MAX(runid) + 1 FROM cron.job_run_details), 1),
      pg_backend_pid(),
      current_database(),
      current_user,
      v_command,
      v_status,
      v_message,
      v_start,
      v_end
    );
  EXCEPTION WHEN OTHERS THEN
    NULL; -- sem permissão na cron.* tudo bem, segue retorno normal
  END;

  IF v_status = 'failed' THEN
    RETURN jsonb_build_object(
      'ok', false, 'jobname', p_jobname,
      'error', v_message, 'duration_ms', extract(milliseconds from (v_end - v_start))::int
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'jobname', p_jobname,
    'executed_at', v_end, 'duration_ms', extract(milliseconds from (v_end - v_start))::int
  );
END $$;

GRANT EXECUTE ON FUNCTION public.executar_cron_agora(text)
  TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

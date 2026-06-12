-- ============================================================================
-- Fix: listar_crons_status retornava 'column reference "jobid" is ambiguous'
-- porque RETURNS TABLE declara jobid e a CTE/query também o usa sem alias.
-- Reescrevo prefixando tudo com aliases inequívocos.
-- ============================================================================

DROP FUNCTION IF EXISTS public.listar_crons_status();

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
  WITH last_run AS (
    SELECT DISTINCT ON (jrd.jobid)
      jrd.jobid          AS l_jobid,
      jrd.runid          AS l_runid,
      jrd.start_time     AS l_start,
      jrd.end_time       AS l_end,
      jrd.status         AS l_status,
      jrd.return_message AS l_message,
      EXTRACT(MILLISECONDS FROM (jrd.end_time - jrd.start_time))::int AS l_dur_ms
    FROM cron.job_run_details jrd
    ORDER BY jrd.jobid, jrd.start_time DESC
  ),
  stats AS (
    SELECT
      jrd.jobid AS s_jobid,
      count(*)::int AS s_runs,
      count(*) FILTER (WHERE jrd.status = 'failed')::int AS s_failures
    FROM cron.job_run_details jrd
    WHERE jrd.start_time > NOW() - INTERVAL '24 hours'
    GROUP BY jrd.jobid
  )
  SELECT
    j.jobid::bigint,
    j.jobname::text,
    j.schedule::text,
    j.command::text,
    j.active::boolean,
    lr.l_runid,
    lr.l_start,
    lr.l_end,
    lr.l_status,
    lr.l_message,
    lr.l_dur_ms,
    COALESCE(st.s_runs, 0),
    COALESCE(st.s_failures, 0)
  FROM cron.job j
  LEFT JOIN last_run lr ON lr.l_jobid = j.jobid
  LEFT JOIN stats    st ON st.s_jobid = j.jobid
  ORDER BY j.jobname;
END $$;

GRANT EXECUTE ON FUNCTION public.listar_crons_status() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- listar_cron_execucoes também tinha potencial ambiguidade — refaço por segurança
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.listar_cron_execucoes(bigint, integer);

CREATE OR REPLACE FUNCTION public.listar_cron_execucoes(
  p_jobid bigint,
  p_limit integer DEFAULT 20
)
RETURNS TABLE (
  runid          bigint,
  start_time     timestamptz,
  end_time       timestamptz,
  status         text,
  return_message text,
  duration_ms    integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = cron, public AS $$
BEGIN
  RETURN QUERY
  SELECT
    jrd.runid::bigint,
    jrd.start_time,
    jrd.end_time,
    jrd.status::text,
    jrd.return_message::text,
    EXTRACT(MILLISECONDS FROM (jrd.end_time - jrd.start_time))::int
  FROM cron.job_run_details jrd
  WHERE jrd.jobid = p_jobid
  ORDER BY jrd.start_time DESC
  LIMIT p_limit;
END $$;

GRANT EXECUTE ON FUNCTION public.listar_cron_execucoes(bigint, integer) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

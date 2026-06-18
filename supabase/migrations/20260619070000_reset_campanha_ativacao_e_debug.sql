-- ============================================================================
-- RESET completo das campanhas + view de debug pra ver o que tá bloqueando.
--
-- O que estava barrando o disparo na campanha 'ativacao':
--   a) intervalo_minutos alto + Schedule n8n 1min → 4/5 execuções bloqueadas
--   b) ultima_execucao_em pode ter ficado num horário ruim
--   c) limite_diario_total atingido sem o usuário perceber
--   d) horário fora da janela ou coffee_break ativo
--
-- Esta migration:
--   1) Desbloqueia campanhas (ativacao + followup + rmkt):
--      - ultima_execucao_em → NULL (libera próxima execução já)
--      - intervalo_minutos = 1 pra ativacao (1 lead/min), 30 pra followup/rmkt
--      - horario_inicio = 09:00, horario_fim = 22:00 (cobre o dia)
--      - coffee_break_inicio/fim = NULL (sem pausa)
--      - skip_rate = 0
--      - pausa_global = false, ativa = true
--   2) Cria view v_debug_campanhas_status pra inspecionar tudo de uma vez
-- ============================================================================

-- 1) RESET: garante que cada campanha pode disparar JÁ
UPDATE public.campanhas
   SET ultima_execucao_em   = NULL,
       intervalo_minutos    = CASE tipo
                                WHEN 'ativacao' THEN 1
                                ELSE 30
                              END,
       horario_inicio       = COALESCE(horario_inicio, '09:00'),
       horario_fim          = CASE WHEN horario_fim IS NULL OR horario_fim < '09:00'
                                   THEN '22:00'::time ELSE horario_fim END,
       coffee_break_inicio  = NULL,
       coffee_break_fim     = NULL,
       skip_rate            = COALESCE(skip_rate, 0),
       pausa_global         = false,
       ativa                = true,
       updated_at           = NOW()
 WHERE tipo IN ('ativacao','followup','rmkt');

-- 2) View de debug: mostra QUAL filtro tá bloqueando cada campanha NESTE INSTANTE
CREATE OR REPLACE VIEW public.v_debug_campanhas_status AS
WITH agora AS (
  SELECT (NOW() AT TIME ZONE 'America/Sao_Paulo')::time AS now_time,
         (NOW() AT TIME ZONE 'America/Sao_Paulo')::date AS now_date
),
envios_hoje AS (
  SELECT ce.campanha_id, COUNT(*) AS qtd
    FROM public.campanha_envios ce, agora a
   WHERE ce.enviado_em >= a.now_date::timestamptz
     AND ce.enviado_em <  (a.now_date + 1)::timestamptz
   GROUP BY ce.campanha_id
)
SELECT
  c.tipo,
  c.nome,
  c.id            AS campanha_id,
  c.ativa,
  c.pausa_global,
  c.horario_inicio,
  c.horario_fim,
  a.now_time      AS agora_brt,
  CASE
    WHEN NOT c.ativa                              THEN 'BLOQUEIO: ativa=false'
    WHEN c.pausa_global                           THEN 'BLOQUEIO: pausa_global'
    WHEN a.now_time < c.horario_inicio
      OR a.now_time > c.horario_fim               THEN 'BLOQUEIO: fora_horario'
    WHEN c.limite_diario_total IS NOT NULL
      AND COALESCE(e.qtd, 0) >= c.limite_diario_total
                                                  THEN 'BLOQUEIO: limite_diario (' ||
                                                       COALESCE(e.qtd,0) || '/' ||
                                                       c.limite_diario_total || ')'
    WHEN c.ultima_execucao_em IS NOT NULL
      AND EXTRACT(EPOCH FROM (NOW() - c.ultima_execucao_em))/60 < c.intervalo_minutos
                                                  THEN 'BLOQUEIO: intervalo (' ||
                                                       round(EXTRACT(EPOCH FROM (NOW() - c.ultima_execucao_em))/60::numeric, 1) ||
                                                       '/' || c.intervalo_minutos || 'min)'
    WHEN c.coffee_break_inicio IS NOT NULL
      AND c.coffee_break_fim   IS NOT NULL
      AND a.now_time BETWEEN c.coffee_break_inicio AND c.coffee_break_fim
                                                  THEN 'BLOQUEIO: coffee_break'
    ELSE                                               'OK (pode disparar)'
  END AS status_agora,
  c.intervalo_minutos,
  c.ultima_execucao_em,
  c.limite_diario_total,
  COALESCE(e.qtd, 0) AS envios_hoje,
  c.coffee_break_inicio,
  c.coffee_break_fim,
  c.skip_rate,
  EXTRACT(EPOCH FROM (NOW() - c.ultima_execucao_em))/60::numeric AS minutos_desde_ultima
FROM public.campanhas c
CROSS JOIN agora a
LEFT JOIN envios_hoje e ON e.campanha_id = c.id
WHERE c.tipo IN ('ativacao','followup','rmkt');

GRANT SELECT ON public.v_debug_campanhas_status TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

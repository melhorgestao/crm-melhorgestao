-- ============================================================================
-- Backfill de financeiro.descricao a partir de lancamentos_socios.
--
-- Custos antigos gravavam a descrição só em lancamentos_socios; a linha espelho
-- em financeiro (usada nas Métricas) nascia sem descricao → o drill-down dos
-- cards mostrava "—". A partir de agora o app grava descricao no financeiro
-- também; isto recupera o histórico.
--
-- SEGURO: só preenche quando existe UM ÚNICO lançamento casando por
-- (tipo↔categoria, data, valor). Se houver ambiguidade (2+ candidatos com
-- mesmo tipo/data/valor), NÃO toca — melhor "—" do que descrição errada.
-- ============================================================================

UPDATE public.financeiro f
   SET descricao = sub.descricao
  FROM (
    SELECT lower(l.tipo)      AS categoria,
           l.data::date       AS data,
           abs(l.valor)       AS valor_abs,
           max(l.descricao)   AS descricao,
           count(*)           AS n
      FROM public.lancamentos_socios l
     WHERE l.tipo IN ('MATERIAL','ADS','ETIQUETA','LOGISTICA','INFLUENCER','INFRAESTRUTURA')
       AND l.descricao IS NOT NULL
       AND btrim(l.descricao) <> ''
     GROUP BY lower(l.tipo), l.data::date, abs(l.valor)
    HAVING count(*) = 1
  ) sub
 WHERE (f.descricao IS NULL OR btrim(f.descricao) = '')
   AND f.categoria = sub.categoria
   AND f.data::date = sub.data
   AND f.valor      = sub.valor_abs;

NOTIFY pgrst, 'reload schema';

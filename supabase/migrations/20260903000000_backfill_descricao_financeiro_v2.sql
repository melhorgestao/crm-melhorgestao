-- ============================================================================
-- Backfill de financeiro.descricao — v2 (match mais robusto).
--
-- A v1 (20260902) exigia data IGUAL entre financeiro e lancamentos_socios. Mas
-- a linha espelho em financeiro nasce com a data da INSERÇÃO, que pode diferir
-- da `data` do lançamento (ex.: custo com data retroativa) — então o "2L MCT"
-- não casava e continuava "sem descrição".
--
-- Agora o match é por (tipo↔categoria, valor), SEM depender da data, e continua
-- SEGURO: só preenche quando existe UM ÚNICO lançamento com aquele tipo+valor e
-- descrição. Se houver 2+ candidatos (ambíguo), não toca.
-- ============================================================================

UPDATE public.financeiro f
   SET descricao = sub.descricao
  FROM (
    SELECT lower(l.tipo)    AS categoria,
           abs(l.valor)     AS valor_abs,
           max(l.descricao) AS descricao,
           count(*)         AS n
      FROM public.lancamentos_socios l
     WHERE l.tipo IN ('MATERIAL','ADS','ETIQUETA','LOGISTICA','INFLUENCER','INFRAESTRUTURA')
       AND l.descricao IS NOT NULL
       AND btrim(l.descricao) <> ''
     GROUP BY lower(l.tipo), abs(l.valor)
    HAVING count(*) = 1
  ) sub
 WHERE (f.descricao IS NULL OR btrim(f.descricao) = '')
   AND f.categoria = sub.categoria
   AND f.valor     = sub.valor_abs;

NOTIFY pgrst, 'reload schema';

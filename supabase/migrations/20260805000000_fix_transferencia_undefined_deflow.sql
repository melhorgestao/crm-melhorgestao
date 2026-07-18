-- ============================================================================
-- Corrige transferências antigas com "undefined→X" na coluna Op.
--
-- BUG (corrigido no front em cc0b1cf): quando a ORIGEM da transferência era um
-- caixa (não-sócio), o label da direção só era buscado na lista de sócios →
-- virava "undefined→A". A partir do fix, resolve também nos caixas.
--
-- Este é o cleanup dos registros JÁ gravados. Só existe 1 caixa (C1 = DeFlow),
-- então toda direção com "undefined" veio dele — troca segura por "DeFlow".
-- Corrige tanto transferencia_direcao quanto descricao (usada no detalhe).
-- ============================================================================

UPDATE public.lancamentos_socios
   SET transferencia_direcao = replace(transferencia_direcao, 'undefined', 'DeFlow'),
       descricao             = replace(descricao, 'undefined', 'DeFlow')
 WHERE tipo = 'TRANSFERENCIA'
   AND (
     transferencia_direcao LIKE '%undefined%'
     OR descricao          LIKE '%undefined%'
   );

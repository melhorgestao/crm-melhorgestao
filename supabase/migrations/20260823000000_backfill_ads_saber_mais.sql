-- ============================================================================
-- Backfill: leads de anúncio salvos como BASE viram ADS.
--
-- O anúncio Meta está configurado com "Saber mais" como 1ª mensagem do lead,
-- então esse texto é assinatura de lead de anúncio. Quando o ctwa não vem no
-- payload do WhatsApp (caso comum), o contato caía como BASE.
--
-- Critério conservador: olha só a PRIMEIRA mensagem recebida do contato
-- (entrada). Se ela tem "saber mais" ou "anúncio" e o canal está BASE,
-- corrige pra ADS (origem E atual). Não toca em REP/C-REP nem em quem já é ADS.
--
-- A partir de agora o router já detecta isso no momento do salvamento
-- (router-ingest: ctwa OU texto de anúncio), então isso é só a faxina do que
-- entrou errado.
-- ============================================================================

DO $$
DECLARE v_qtd int;
BEGIN
  WITH primeira AS (
    SELECT DISTINCT ON (contato_id) contato_id, mensagem
      FROM public.mensagens_buffer
     WHERE direcao = 'in'
     ORDER BY contato_id, recebida_em ASC
  ), upd AS (
    UPDATE public.contatos c
       SET canal_origem = 'ADS',
           canal_atual  = 'ADS',
           updated_at   = now()
      FROM primeira p
     WHERE p.contato_id = c.id
       AND COALESCE(c.canal_atual, c.canal_origem) = 'BASE'
       AND (
         p.mensagem ILIKE '%saber mais%'
         OR p.mensagem ILIKE '%anúncio%'
         OR p.mensagem ILIKE '%anuncio%'
       )
    RETURNING c.id
  )
  SELECT count(*) INTO v_qtd FROM upd;

  RAISE NOTICE 'Backfill ADS: % contatos BASE corrigidos para ADS.', v_qtd;
END $$;

NOTIFY pgrst, 'reload schema';

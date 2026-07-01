-- ============================================================================
-- FIX: apresentação (5 blocos) nunca disparava pra novo lead.
--
-- CAUSA: o trigger trg_data_start_default (migration 20260701) setava
-- data_start = NOW() no INSERT de um contato com ultima_interacao='start'
-- (get_or_create_contato cria assim). Mas o edge agent-start usa
-- "data_start IS NULL" pra detectar PRIMEIRA interação. Com data_start já
-- setado na criação, o edge achava que a apresentação já tinha sido enviada
-- → pulava os blocos 1-4 e mandava só a saudação (bloco 5).
--
-- SEMÂNTICA CORRETA: data_start = quando a APRESENTAÇÃO foi enviada (o edge
-- seta após mandar os blocos). NÃO quando o contato nasceu.
--
-- FIX: trigger dispara SÓ em UPDATE OF ultima_interacao (não em INSERT).
-- Assim:
--   - Novo lead (INSERT via get_or_create, ultima_interacao='start') nasce
--     com data_start NULL → edge detecta 1ª interação → manda apresentação →
--     seta data_start=NOW().
--   - Contato que TRANSICIONA pra 'start' via UPDATE sem data_start ainda
--     recebe o default defensivo (mantém cron 24h funcionando).
-- ============================================================================

DROP TRIGGER IF EXISTS trg_data_start_default ON public.contatos;

CREATE TRIGGER trg_data_start_default
  BEFORE UPDATE OF ultima_interacao ON public.contatos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_data_start_default();

-- Corrige leads criados HOJE que ficaram presos: novo (start), sem nenhum
-- envio de mensagem out ainda, com data_start setado errado pela criação.
-- Zera data_start pra que a apresentação dispare na próxima mensagem deles.
UPDATE public.contatos c
   SET data_start = NULL, updated_at = NOW()
 WHERE c.ultima_interacao = 'start'
   AND c.ja_comprou = false
   AND c.data_start IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM public.mensagens_buffer b
      WHERE b.contato_id = c.id AND b.direcao = 'out'
   );

NOTIFY pgrst, 'reload schema';

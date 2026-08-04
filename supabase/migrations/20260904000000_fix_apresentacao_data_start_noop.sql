-- ============================================================================
-- FIX CRÍTICO: apresentação não disparava pra leads pré-existentes em 'start'.
--
-- CAUSA: trigger_data_start_default carimbava data_start=NOW() sempre que um
-- UPDATE tocava ultima_interacao e o valor final era 'start' com data_start
-- nulo. O get_or_create_contato faz um UPDATE "no-op" (ultima_interacao =
-- COALESCE(ultima_interacao,'start')) a CADA mensagem do lead. Para um lead
-- pré-salvo (ex.: /saveads cria em 'start' com data_start NULL), a PRIMEIRA
-- mensagem dele disparava esse UPDATE → o trigger carimbava data_start ANTES
-- do agent-start rodar → o edge via data_start setado e achava que já tinha
-- apresentado → mandava só a saudação genérica ("como posso ajudar?"), sem
-- apresentação + cardápio.
--
-- FIX: o trigger só carimba data_start quando o contato ESTÁ ENTRANDO em
-- 'start' (transição real: OLD != 'start'). No UPDATE no-op (start→start) do
-- get_or_create ele NÃO mexe → data_start continua NULL → o agent-start
-- detecta 1ª interação e manda a apresentação, carimbando data_start ele mesmo.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trigger_data_start_default()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Só define o default defensivo numa TRANSIÇÃO real pra 'start'
  -- (OLD != 'start'). Assim o UPDATE no-op do get_or_create (start→start)
  -- não rouba a detecção de 1ª interação do agent-start.
  IF NEW.ultima_interacao = 'start'
     AND NEW.data_start IS NULL
     AND OLD.ultima_interacao IS DISTINCT FROM 'start' THEN
    NEW.data_start := NOW();
  END IF;
  RETURN NEW;
END $$;

-- Limpeza retroativa: leads presos em 'start' (não-cliente) com data_start
-- setado mas SEM nenhuma mensagem enviada ainda → zera data_start pra que a
-- apresentação dispare na próxima mensagem deles.
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

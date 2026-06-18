-- ============================================================================
-- Controle dedicado de apresentação enviada.
--
-- Antes: agent-start usava COUNT(mensagens_buffer out) == 0 como proxy de
-- "primeira interação". Falso positivo em clientes inseridos manualmente
-- (ja_comprou=true sem nenhuma msg do bot enviada).
--
-- Agora:
--  - Coluna apresentacao_enviada_em TIMESTAMPTZ (NULL = ainda não enviou)
--  - Regra agent-start: só envia apresentação se
--      ja_comprou=false AND apresentacao_enviada_em IS NULL
--
-- Backfill: marca como apresentada quem ja_comprou=true OU tem msg out no
-- buffer (alguém já interagiu com bot).
-- ============================================================================

ALTER TABLE public.contatos
  ADD COLUMN IF NOT EXISTS apresentacao_enviada_em TIMESTAMPTZ;

COMMENT ON COLUMN public.contatos.apresentacao_enviada_em IS
  'Quando o agent-start enviou o cardápio inicial (apresentação + tabela + cardápio). NULL = ainda não recebeu.';

CREATE INDEX IF NOT EXISTS idx_contatos_apresentacao_pendente
  ON public.contatos (id)
  WHERE apresentacao_enviada_em IS NULL AND ja_comprou = false;

-- Backfill: quem já comprou ou já tem msg out no buffer não deve mais
-- receber apresentação. Marca com timestamp do created_at (estimativa).
UPDATE public.contatos c
   SET apresentacao_enviada_em = COALESCE(c.created_at, NOW())
 WHERE apresentacao_enviada_em IS NULL
   AND (
     c.ja_comprou = true
     OR EXISTS (
       SELECT 1 FROM public.mensagens_buffer mb
        WHERE mb.contato_id = c.id AND mb.direcao = 'out'
     )
   );

NOTIFY pgrst, 'reload schema';

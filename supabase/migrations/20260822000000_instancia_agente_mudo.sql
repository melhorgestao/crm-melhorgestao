-- ============================================================================
-- AGENTE MUDO por instância.
--
-- Cenário: chip restrito pelo WhatsApp. O dono precisa da instância LIGADA
-- pra escutar os comandos fromMe (/saveads, /savebase, /humano...), mas se o
-- bot responder as mensagens dos leads o WhatsApp limita ainda mais a entrega
-- e agrava a restrição.
--
-- agente_mudo = true → a instância continua RECEBENDO e SALVANDO tudo
-- (contato, buffer, data_ultima_entrada) e continua EXECUTANDO comandos do
-- dono, mas o bot NÃO responde nada. Zero envio automático por esse chip.
--
-- Desligar o toggle volta ao normal, sem perder nada do que foi capturado.
-- ============================================================================

ALTER TABLE public.instancias
  ADD COLUMN IF NOT EXISTS agente_mudo boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.instancias.agente_mudo IS
  'Modo mudo: recebe/salva mensagens e executa comandos fromMe, mas o bot não envia NADA por esta instância. Usado com o chip restrito.';

NOTIFY pgrst, 'reload schema';

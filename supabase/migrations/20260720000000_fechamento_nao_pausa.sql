-- ============================================================================
-- REGRA: bot NUNCA pode ficar pausado em em_fechamento.
--
-- Justificativa: em em_fechamento o agent-closing está ativamente atendendo
-- o cliente. Se o bot for pausado nesse estado por qualquer caminho (SQL
-- manual, /parar de 24h, comando futuro), o lead fica órfão — sem agent, sem
-- botão de finalizar venda (o carrinho só aparece em suporte).
--
-- Solução: trigger invariante path-independent. Sempre que uma escrita
-- resultar em (bot_pausado_ate > NOW() E ultima_interacao='em_fechamento'),
-- move automaticamente pra 'suporte' salvando 'em_fechamento' em
-- estado_antes_suporte. Ao clicar "Suporte Realizado" (ou /voltar), o lead
-- volta pra em_fechamento — fluxo natural.
--
-- Fluxo alvo:
--   em_fechamento → pause (por qualquer via) → suporte (auto)
--                                            ↓ ✓ Suporte Realizado
--                                            ← em_fechamento
-- ============================================================================

CREATE OR REPLACE FUNCTION public.forca_fechamento_sem_pausa()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.ultima_interacao = 'em_fechamento'
     AND NEW.bot_pausado_ate IS NOT NULL
     AND NEW.bot_pausado_ate > NOW() THEN
    -- Salva o estado que estava (em_fechamento) pra restaurar depois
    NEW.estado_antes_suporte := COALESCE(NEW.estado_antes_suporte, 'em_fechamento');
    NEW.ultima_interacao     := 'suporte';
    NEW.data_suporte         := NOW();
    NEW.suporte_motivo       := COALESCE(NEW.suporte_motivo, 'humano_atendendo');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fechamento_sem_pausa ON public.contatos;
CREATE TRIGGER trg_fechamento_sem_pausa
  BEFORE INSERT OR UPDATE OF bot_pausado_ate, ultima_interacao
  ON public.contatos
  FOR EACH ROW
  EXECUTE FUNCTION public.forca_fechamento_sem_pausa();

-- ----------------------------------------------------------------------------
-- CLEANUP: leads que estão AGORA em em_fechamento com bot pausado → suporte
-- (preserva em_fechamento em estado_antes_suporte pra restauração futura)
-- ----------------------------------------------------------------------------
UPDATE public.contatos
   SET ultima_interacao      = 'suporte',
       estado_antes_suporte  = COALESCE(estado_antes_suporte, 'em_fechamento'),
       data_suporte          = COALESCE(data_suporte, NOW()),
       suporte_motivo        = COALESCE(suporte_motivo, 'humano_atendendo'),
       updated_at            = NOW()
 WHERE ultima_interacao = 'em_fechamento'
   AND bot_pausado_ate IS NOT NULL
   AND bot_pausado_ate > NOW();

NOTIFY pgrst, 'reload schema';

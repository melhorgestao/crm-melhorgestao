-- ============================================================================
-- Campanhas: regras de elegibilidade editáveis pela UI.
-- (Sprint 3 vai conectar os workflows pra usar esses parâmetros nas RPCs claim_proximo_lead_*)
--
--   dias_inativo_min        RMKT — cliente sem compra há pelo menos X dias
--   dias_sem_envio          Ativação/RMKT — sem receber ESTA campanha em X dias
--                            (mais granular que cooldown_dias, que é cross-campanha)
--   max_tentativas_categoria Ativação — máximo de envios totais dessa campanha
--                            ao mesmo contato (corresponde à coluna ativacao_tentativas)
--
-- Followup mantém regras fixas no banco (24h/3d/7d derivadas de follow_up_tentativas).
-- ============================================================================

ALTER TABLE public.campanhas
  ADD COLUMN IF NOT EXISTS dias_inativo_min        integer,
  ADD COLUMN IF NOT EXISTS dias_sem_envio          integer,
  ADD COLUMN IF NOT EXISTS max_tentativas_categoria integer;

-- Seed: valores históricos pra não mudar comportamento dos workflows atuais
UPDATE public.campanhas
   SET dias_inativo_min  = 30,
       dias_sem_envio    = 30,
       max_tentativas_categoria = NULL  -- RMKT não tem limite explícito (controlado por rmkt_consecutive_silenciosos)
 WHERE tipo = 'rmkt';

UPDATE public.campanhas
   SET dias_sem_envio              = 30,
       max_tentativas_categoria    = 3,
       dias_inativo_min            = NULL
 WHERE tipo = 'ativacao';

-- Follow-up: regras fixas (não usa esses campos)
UPDATE public.campanhas
   SET dias_inativo_min        = NULL,
       dias_sem_envio          = NULL,
       max_tentativas_categoria = NULL
 WHERE tipo = 'followup';

NOTIFY pgrst, 'reload schema';

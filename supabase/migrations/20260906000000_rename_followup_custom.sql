-- Padroniza o nome da campanha de follow-up personalizado com o "Fechamento
-- Custom": "Follow-up Personalizado" → "Follow-up Custom".
UPDATE public.campanhas
   SET nome = 'Follow-up Custom', updated_at = NOW()
 WHERE tipo = 'followup'
   AND nome = 'Follow-up Personalizado';

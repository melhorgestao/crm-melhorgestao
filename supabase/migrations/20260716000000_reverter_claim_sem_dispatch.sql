-- ============================================================================
-- "Só migra pra follow_up/rmkt com disparo CONFIRMADO."
--
-- Problema: claim_proximo_lead_followup / _rmkt marcam o estado (follow_up /
-- rmkt) e incrementam tentativa ANTES do envio. Se o envio falha (400, instância
-- caída), o contato fica preso no novo estado sem ter recebido nada.
--
-- Solução: RPC de reversão chamada no branch de FALHA do workflow (DETECTA
-- FALHA? = true). Desfaz o claim → volta pro estado de origem, decrementa
-- tentativa. Efeito líquido: o contato só PERMANECE em follow_up/rmkt se o
-- disparo foi confirmado.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reverter_claim_lead(
  p_contato_id uuid,
  p_categoria  text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado text;
BEGIN
  IF p_categoria = 'followup' THEN
    UPDATE public.contatos
       SET ultima_interacao      = 'wait_follow_up',
           follow_up_tentativas  = GREATEST(COALESCE(follow_up_tentativas, 1) - 1, 0),
           data_ultimo_follow_up = NULL,
           updated_at            = NOW()
     WHERE id = p_contato_id
       AND ultima_interacao = 'follow_up'
     RETURNING ultima_interacao INTO v_estado;

  ELSIF p_categoria = 'rmkt' THEN
    UPDATE public.contatos
       SET ultima_interacao             = 'cliente',
           rmkt_consecutive_silenciosos = GREATEST(COALESCE(rmkt_consecutive_silenciosos, 1) - 1, 0),
           updated_at                   = NOW()
     WHERE id = p_contato_id
       AND ultima_interacao = 'rmkt'
     RETURNING ultima_interacao INTO v_estado;
  END IF;

  RETURN jsonb_build_object('ok', true, 'revertido_para', v_estado, 'categoria', p_categoria);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reverter_claim_lead(uuid, text)
  TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- CLEANUP: leads que foram movidos pra follow_up HOJE mas nunca receberam
-- envio confirmado (nenhum registro em campanha_envios). Volta pra wait.
-- ----------------------------------------------------------------------------
UPDATE public.contatos c
   SET ultima_interacao      = 'wait_follow_up',
       follow_up_tentativas  = GREATEST(COALESCE(follow_up_tentativas, 1) - 1, 0),
       data_ultimo_follow_up = NULL,
       updated_at            = NOW()
 WHERE c.ultima_interacao = 'follow_up'
   AND NOT EXISTS (
     SELECT 1 FROM public.campanha_envios ce
      WHERE ce.contato_id = c.id
   );

NOTIFY pgrst, 'reload schema';

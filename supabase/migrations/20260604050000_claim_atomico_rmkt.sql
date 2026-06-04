-- ============================================================================
-- Claim atômico de lead pra RMKT BASE — suporta 2+ chips em paralelo
--
-- Problema:
--   Com 2 workflows simultâneos (1 por chip) filtrando instancia_id IS NULL,
--   ambos podem pegar o MESMO lead → cliente recebe 2 mensagens.
--
-- Solução:
--   RPC claim_proximo_lead_rmkt(instancia_id) faz SELECT + LOCK + UPDATE
--   numa transação. FOR UPDATE SKIP LOCKED garante que se chip1 já pegou,
--   chip2 pula pro próximo automaticamente.
--
-- Uso n8n:
--   Substitui o nó GET CONTATO por chamada POST a essa RPC com o UUID
--   da instância. Se retornar vazio, não tem lead disponível agora.
--
-- Bônus: rpc release_claim_rmkt pra liberar lead caso o SEND falhe e
-- queiramos retentar de outro chip.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.claim_proximo_lead_rmkt(
  p_instancia_id UUID,
  p_dias_gap INTEGER DEFAULT 30
)
RETURNS TABLE (
  id UUID,
  nome TEXT,
  telefone TEXT,
  rem_tem_foto BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET instancia_id = p_instancia_id,
      updated_at = NOW()
  WHERE c.id = (
    SELECT c2.id
    FROM public.contatos c2
    WHERE c2.canal_atual = 'BASE'
      AND c2.rem_status = 'novo'
      AND c2.rem_aguardando_resposta = false
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND (c2.ultima_venda_em IS NULL OR c2.ultima_venda_em < CURRENT_DATE - (p_dias_gap || ' days')::INTERVAL)
    ORDER BY c2.rem_tem_foto DESC NULLS LAST, c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone, c.rem_tem_foto;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_rmkt(UUID, INTEGER)
  TO authenticated, anon, service_role;


-- RPC pra liberar claim em caso de falha do SEND.
-- Restaura instancia_id = NULL pra que outro chip possa tentar.
-- Só libera se a instância passada bate com a atual (evita race).
CREATE OR REPLACE FUNCTION public.release_claim_rmkt(
  p_contato_id UUID,
  p_instancia_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.contatos
  SET instancia_id = NULL,
      updated_at = NOW()
  WHERE id = p_contato_id
    AND instancia_id = p_instancia_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.release_claim_rmkt(UUID, UUID)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Suporte a múltiplas campanhas simultâneas
--
-- Antes: pode_disparar_hoje contava todos disparos juntos no balde
-- Agora: cada campanha tem nome próprio, limite próprio, métricas separadas
--
-- Casos de uso:
--   - "ativacao_base_2k_jun26" — campanha geral de ativação (rodando)
--   - "rmkt_40d_silenciosos" — clientes sem comprar há 40+ dias (futuro)
--   - "black_friday_2026" — sazonal (futuro)
--   - "lancamento_produto_X" — pontual (futuro)
-- ============================================================================

-- 1) Coluna pra rastrear qual campanha cada contato recebeu
ALTER TABLE contatos ADD COLUMN IF NOT EXISTS ultima_campanha TEXT;

COMMENT ON COLUMN contatos.ultima_campanha IS
  'Nome da última campanha de ativação que esse contato recebeu (ex: ativacao_base_2k_jun26, rmkt_40d). Usado pra métricas e separar limites diários por campanha.';

-- 2) claim_proximo_lead_ativacao agora aceita campanha + dias_gap
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_ativacao(
  p_instancia_id UUID,
  p_campanha TEXT DEFAULT NULL,
  p_dias_gap INTEGER DEFAULT 30
)
RETURNS TABLE (id UUID, nome TEXT, telefone TEXT, rem_tem_foto BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET ultima_interacao = 'ativacao_contatos',
      data_ultimo_ativacao = NOW(),
      ultima_campanha = COALESCE(p_campanha, 'sem_campanha'),
      instancia_id = p_instancia_id,
      updated_at = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ja_comprou = true
      AND c2.ultima_interacao = 'cliente'
      AND c2.telefone IS NOT NULL
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.ativacao_consecutive_silenciosos < 3
      AND (c2.data_ultimo_ativacao IS NULL OR c2.data_ultimo_ativacao < NOW() - (p_dias_gap || ' days')::INTERVAL)
      AND c2.data_cliente < NOW() - (p_dias_gap || ' days')::INTERVAL
    ORDER BY c2.rem_tem_foto DESC NULLS LAST, c2.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone, c.rem_tem_foto;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_ativacao(UUID, TEXT, INTEGER)
  TO authenticated, anon, service_role;

-- 3) pode_disparar_hoje filtra por campanha
CREATE OR REPLACE FUNCTION public.pode_disparar_hoje(
  p_campanha TEXT DEFAULT NULL,
  p_limite INTEGER DEFAULT 200
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT COUNT(*)
    FROM contatos
    WHERE ultima_interacao = 'ativacao_contatos'
      AND data_ultimo_ativacao >= (CURRENT_DATE::timestamp AT TIME ZONE 'America/Sao_Paulo')
      AND (p_campanha IS NULL OR ultima_campanha = p_campanha)
  ) < p_limite;
END;
$$;

GRANT EXECUTE ON FUNCTION public.pode_disparar_hoje(TEXT, INTEGER)
  TO authenticated, anon, service_role;

-- 4) Index pra queries de métrica e claim ficarem rápidas
CREATE INDEX IF NOT EXISTS idx_contatos_campanha_ativacao
  ON contatos(ultima_campanha, data_ultimo_ativacao)
  WHERE ultima_interacao = 'ativacao_contatos';

NOTIFY pgrst, 'reload schema';

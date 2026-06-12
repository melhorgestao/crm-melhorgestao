-- ============================================================================
-- CORREÇÃO ARQUITETURAL: instâncias são INDEPENDENTES — nenhum contato
-- migra de instância. Cada instância faz tudo em paralelo:
--   - Recebe ADS
--   - Faz follow-up
--   - Converte em BASE quando lead compra
--   - Faz RMKT
--   - Faz ativação
--
-- Não existe "tipo" funcional (ADS vs BASE) — todas trabalham igual.
-- O canal_origem é só do CONTATO (estado do funil), não da instância.
--
-- Por isso o midnight só muda canal_origem ADS→BASE. NUNCA toca instancia_id.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_migrated_count integer := 0;
BEGIN
  -- ÚNICA mudança: ADS → BASE quando lead comprou ontem
  -- instancia_id intocada — contato continua na mesma instância pra sempre
  WITH updated AS (
    UPDATE public.contatos
       SET canal_origem = 'BASE',
           updated_at   = NOW()
     WHERE canal_origem = 'ADS'
       AND ultima_venda_em = CURRENT_DATE - 1
     RETURNING id
  )
  SELECT count(*) INTO v_migrated_count FROM updated;

  INSERT INTO public.configuracoes (chave, valor)
       VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

  RETURN json_build_object(
    'success', true,
    'migrated_count', v_migrated_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.perform_midnight_lead_migration()
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

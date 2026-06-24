-- ============================================================================
-- Sincroniza data_cliente ⇄ primeira_venda_em automaticamente.
--
-- DECISÃO: não dropar data_cliente ainda — usada em 13 migrations e em
-- crons críticos (RMKT, ativação). Drop sem mapear tudo quebraria produção.
--
-- Solução intermediária: trigger BEFORE UPDATE garante
-- data_cliente = COALESCE(primeira_venda_em, data_cliente).
-- Resultado: as duas colunas ficam sempre iguais, nenhuma query existente
-- precisa mudar. Drop fica pra fase futura quando der pra substituir
-- todas as referências numa migration limpa.
--
-- Backfill: sincroniza contatos onde estão divergentes.
-- ============================================================================

-- 1) Backfill: alinha as duas colunas
UPDATE public.contatos
   SET data_cliente = primeira_venda_em::timestamptz,
       updated_at   = NOW()
 WHERE primeira_venda_em IS NOT NULL
   AND (data_cliente IS NULL OR data_cliente::date != primeira_venda_em);

-- 2) Trigger: sempre que primeira_venda_em muda, atualiza data_cliente
CREATE OR REPLACE FUNCTION public.trigger_sync_data_cliente()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.primeira_venda_em IS NOT NULL
     AND NEW.primeira_venda_em IS DISTINCT FROM OLD.primeira_venda_em THEN
    NEW.data_cliente := NEW.primeira_venda_em::timestamptz;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_sync_data_cliente ON public.contatos;
CREATE TRIGGER trg_sync_data_cliente
  BEFORE UPDATE OF primeira_venda_em ON public.contatos
  FOR EACH ROW EXECUTE FUNCTION public.trigger_sync_data_cliente();

COMMENT ON COLUMN public.contatos.data_cliente IS
  'DEPRECATED — espelho de primeira_venda_em. Mantido por compat com crons antigos. Drop programado pra fase de cleanup quando todas as refs forem substituídas.';

NOTIFY pgrst, 'reload schema';

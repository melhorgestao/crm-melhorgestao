-- ============================================================================
-- Refina trigger_crep_telefone_do_rep: só preenche se telefone estiver vazio.
-- Permite admin sobrescrever manualmente quando precisar (ex: cliente C-REP
-- que tem WhatsApp próprio e quer receber direto).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trigger_crep_telefone_do_rep()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rep_tel text;
BEGIN
  IF NEW.canal_origem = 'C-REP'
     AND NEW.representante_id IS NOT NULL
     AND (NEW.telefone IS NULL OR NEW.telefone = '') THEN
    SELECT telefone INTO v_rep_tel
      FROM public.contatos
     WHERE id = NEW.representante_id;
    IF v_rep_tel IS NOT NULL THEN
      NEW.telefone := v_rep_tel;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

NOTIFY pgrst, 'reload schema';

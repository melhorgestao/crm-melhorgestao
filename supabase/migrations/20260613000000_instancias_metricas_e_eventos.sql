-- ============================================================================
-- Aba Instâncias: RPC de métricas + log em eventos_contato dos pause/reativar.
-- evolution_master_apikey em configuracoes (admin preenche pra criar via Evolution API).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Slot pra master apikey da Evolution (cria/deleta instâncias)
-- ----------------------------------------------------------------------------
INSERT INTO public.configuracoes (chave, valor)
  VALUES ('evolution_master_apikey', '')
  ON CONFLICT (chave) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2) RPC métricas da instância (conversas únicas + counts de contatos)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.instancia_metricas(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_result jsonb;
  v_clientes int;
  v_ads int;
  v_base int;
  v_rep int;
  v_conv_in int;
  v_conv_out int;
BEGIN
  SELECT
    count(*) FILTER (WHERE ja_comprou),
    count(*) FILTER (WHERE canal_origem = 'ADS'),
    count(*) FILTER (WHERE canal_origem = 'BASE'),
    count(*) FILTER (WHERE canal_origem IN ('REP','C-REP'))
  INTO v_clientes, v_ads, v_base, v_rep
  FROM public.contatos
  WHERE instancia_id = p_id;

  -- conversas únicas hoje (1 contato = 1 conversa, mesmo com várias msgs)
  -- mensagens_buffer pode não existir ainda em todos os ambientes — tratar
  BEGIN
    SELECT
      count(DISTINCT contato_id) FILTER (WHERE direcao='in'),
      count(DISTINCT contato_id) FILTER (WHERE direcao='out')
    INTO v_conv_in, v_conv_out
    FROM public.mensagens_buffer
    WHERE instancia_id = p_id
      AND recebida_em >= CURRENT_DATE;
  EXCEPTION WHEN undefined_table THEN
    v_conv_in := 0;
    v_conv_out := 0;
  END;

  v_result := jsonb_build_object(
    'clientes',  COALESCE(v_clientes, 0),
    'ads',       COALESCE(v_ads, 0),
    'base',      COALESCE(v_base, 0),
    'rep',       COALESCE(v_rep, 0),
    'conv_in',   COALESCE(v_conv_in, 0),
    'conv_out',  COALESCE(v_conv_out, 0)
  );

  RETURN v_result;
END; $$;

GRANT EXECUTE ON FUNCTION public.instancia_metricas(uuid)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) Triggers que logam pausa/reativação em eventos_contato
--    (usando contato_id=NULL e instancia_id pra histórico de instância)
-- ----------------------------------------------------------------------------

-- Garante coluna nullable em contato_id se eventos_contato existir
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
              WHERE table_schema='public' AND table_name='eventos_contato') THEN
    -- contato_id pode ser NULL para eventos de instância (não atrelados a contato)
    BEGIN
      ALTER TABLE public.eventos_contato ALTER COLUMN contato_id DROP NOT NULL;
    EXCEPTION WHEN others THEN
      NULL; -- já permite null
    END;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.log_instancia_evento()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_tipo text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                  WHERE table_schema='public' AND table_name='eventos_contato') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_tipo := 'instancia_criada';
  ELSIF OLD.status = 'ativo' AND NEW.status <> 'ativo' THEN
    v_tipo := 'instancia_pausada';
  ELSIF OLD.status <> 'ativo' AND NEW.status = 'ativo' THEN
    v_tipo := 'instancia_reativada';
  ELSIF OLD.alerta_admin IS DISTINCT FROM NEW.alerta_admin AND NEW.alerta_admin = true THEN
    v_tipo := 'instancia_marcada_admin';
  ELSE
    RETURN NEW;
  END IF;

  INSERT INTO public.eventos_contato (contato_id, tipo, canal, instancia_id, metadata)
  VALUES (
    NULL,
    v_tipo,
    NEW.evolution_instance,
    NEW.id,
    jsonb_build_object(
      'status_anterior', CASE WHEN TG_OP = 'UPDATE' THEN OLD.status ELSE NULL END,
      'status_atual',    NEW.status,
      'motivo',          NEW.motivo_pausa,
      'pausado_ate',     NEW.pausado_ate,
      'nome',            NEW.nome
    )
  );
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS instancias_log_eventos ON public.instancias;
CREATE TRIGGER instancias_log_eventos
  AFTER INSERT OR UPDATE OF status, alerta_admin
  ON public.instancias
  FOR EACH ROW
  EXECUTE FUNCTION public.log_instancia_evento();

NOTIFY pgrst, 'reload schema';

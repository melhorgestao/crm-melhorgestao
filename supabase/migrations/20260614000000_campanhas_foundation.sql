-- ============================================================================
-- Sprint 1 Campanhas — Foundation
--
-- Tabelas:
--   campanhas              entidade alto-nível (nome, tipo, on/off, horário, limite, cooldown)
--   campanha_instancia     toggle + limite extra por instância (matriz N×M)
--   campanha_envios        auditoria/métricas (respondido_em, comprou_apos)
--   variaveis_globais      placeholders customizados ({{cupom_atual}})
--
-- templates_msg += campanha_id, anexo_url, anexo_tipo
-- configuracoes += campanhas_pausa_global (botão de emergência)
--
-- Auto-cria 5 campanhas iniciais a partir dos templates existentes.
-- RPCs: escolhe_template_v2 (com todas as regras) + registrar_envio_campanha
-- Storage: bucket 'campanhas-anexos' público (Evolution lê via URL).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Tabela campanhas
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campanhas (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome                text NOT NULL,
  tipo                text NOT NULL CHECK (tipo IN ('ativacao','followup','rmkt')),
  ativa               boolean NOT NULL DEFAULT true,
  pausa_global        boolean NOT NULL DEFAULT false,
  horario_inicio      time NOT NULL DEFAULT '09:00',
  horario_fim         time NOT NULL DEFAULT '20:00',
  limite_diario_total integer,            -- NULL = sem limite
  cooldown_dias       integer NOT NULL DEFAULT 0, -- 0 = sem cooldown
  observacao          text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_campanhas_tipo_ativa
  ON public.campanhas (tipo) WHERE ativa = true;

-- ----------------------------------------------------------------------------
-- 2) Toggle + limite por instância (matriz)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campanha_instancia (
  campanha_id            uuid NOT NULL REFERENCES public.campanhas(id) ON DELETE CASCADE,
  instancia_id           uuid NOT NULL REFERENCES public.instancias(id) ON DELETE CASCADE,
  ativa                  boolean NOT NULL DEFAULT true,
  limite_diario_instancia integer,  -- NULL = usa global da campanha (ou sem limite)
  created_at             timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campanha_id, instancia_id)
);

-- ----------------------------------------------------------------------------
-- 3) templates_msg ganha vínculo com campanha + anexo
-- ----------------------------------------------------------------------------
ALTER TABLE public.templates_msg
  ADD COLUMN IF NOT EXISTS campanha_id uuid REFERENCES public.campanhas(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS anexo_url   text,
  ADD COLUMN IF NOT EXISTS anexo_tipo  text
    CHECK (anexo_tipo IS NULL OR anexo_tipo IN ('image','video','audio','document'));

-- ----------------------------------------------------------------------------
-- 4) Auditoria de envios + métricas A/B
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campanha_envios (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campanha_id   uuid REFERENCES public.campanhas(id) ON DELETE SET NULL,
  template_id   uuid REFERENCES public.templates_msg(id) ON DELETE SET NULL,
  instancia_id  uuid REFERENCES public.instancias(id) ON DELETE SET NULL,
  contato_id    uuid NOT NULL REFERENCES public.contatos(id) ON DELETE CASCADE,
  enviado_em    timestamptz NOT NULL DEFAULT now(),
  respondido_em timestamptz,
  comprou_apos  boolean NOT NULL DEFAULT false,
  metadata      jsonb
);

CREATE INDEX IF NOT EXISTS idx_envios_contato_data
  ON public.campanha_envios (contato_id, enviado_em DESC);
CREATE INDEX IF NOT EXISTS idx_envios_campanha_data
  ON public.campanha_envios (campanha_id, enviado_em DESC);
CREATE INDEX IF NOT EXISTS idx_envios_instancia_data
  ON public.campanha_envios (instancia_id, enviado_em DESC);

-- ----------------------------------------------------------------------------
-- 5) Variáveis globais (placeholders customizados)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.variaveis_globais (
  chave      text PRIMARY KEY,
  valor      text,
  descricao  text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 6) Pausa global (botão de emergência)
-- ----------------------------------------------------------------------------
INSERT INTO public.configuracoes (chave, valor)
  VALUES ('campanhas_pausa_global', 'false')
  ON CONFLICT (chave) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 7) RLS — tudo admin only
-- ----------------------------------------------------------------------------
ALTER TABLE public.campanhas           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campanha_instancia  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campanha_envios     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.variaveis_globais   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS campanhas_admin ON public.campanhas;
CREATE POLICY campanhas_admin ON public.campanhas
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS campanha_instancia_admin ON public.campanha_instancia;
CREATE POLICY campanha_instancia_admin ON public.campanha_instancia
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS campanha_envios_admin ON public.campanha_envios;
CREATE POLICY campanha_envios_admin ON public.campanha_envios
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS variaveis_globais_admin ON public.variaveis_globais;
CREATE POLICY variaveis_globais_admin ON public.variaveis_globais
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------------------
-- 8) Auto-cria 5 campanhas iniciais + vincula templates existentes
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_ativacao     uuid;
  v_followup_24h uuid;
  v_followup_3d  uuid;
  v_followup_7d  uuid;
  v_rmkt         uuid;
BEGIN
  -- Cria apenas se ainda não existem (idempotência)
  SELECT id INTO v_ativacao     FROM public.campanhas WHERE tipo='ativacao' AND nome='Ativação Geral'  LIMIT 1;
  SELECT id INTO v_followup_24h FROM public.campanhas WHERE tipo='followup' AND nome='Follow-up 24h'    LIMIT 1;
  SELECT id INTO v_followup_3d  FROM public.campanhas WHERE tipo='followup' AND nome='Follow-up 3 dias' LIMIT 1;
  SELECT id INTO v_followup_7d  FROM public.campanhas WHERE tipo='followup' AND nome='Follow-up 7 dias' LIMIT 1;
  SELECT id INTO v_rmkt         FROM public.campanhas WHERE tipo='rmkt'     AND nome='RMKT 30 dias'     LIMIT 1;

  IF v_ativacao     IS NULL THEN INSERT INTO public.campanhas (nome, tipo) VALUES ('Ativação Geral','ativacao')   RETURNING id INTO v_ativacao;     END IF;
  IF v_followup_24h IS NULL THEN INSERT INTO public.campanhas (nome, tipo) VALUES ('Follow-up 24h','followup')    RETURNING id INTO v_followup_24h; END IF;
  IF v_followup_3d  IS NULL THEN INSERT INTO public.campanhas (nome, tipo) VALUES ('Follow-up 3 dias','followup') RETURNING id INTO v_followup_3d;  END IF;
  IF v_followup_7d  IS NULL THEN INSERT INTO public.campanhas (nome, tipo) VALUES ('Follow-up 7 dias','followup') RETURNING id INTO v_followup_7d;  END IF;
  IF v_rmkt         IS NULL THEN INSERT INTO public.campanhas (nome, tipo) VALUES ('RMKT 30 dias','rmkt')         RETURNING id INTO v_rmkt;         END IF;

  -- Vincula templates existentes às campanhas (só os que ainda não têm campanha_id)
  UPDATE public.templates_msg SET campanha_id = v_ativacao     WHERE categoria='ativacao' AND campanha_id IS NULL;
  UPDATE public.templates_msg SET campanha_id = v_followup_24h WHERE categoria='followup' AND subcategoria='24h' AND campanha_id IS NULL;
  UPDATE public.templates_msg SET campanha_id = v_followup_3d  WHERE categoria='followup' AND subcategoria='3d'  AND campanha_id IS NULL;
  UPDATE public.templates_msg SET campanha_id = v_followup_7d  WHERE categoria='followup' AND subcategoria='7d'  AND campanha_id IS NULL;
  UPDATE public.templates_msg SET campanha_id = v_rmkt         WHERE categoria='rmkt'     AND campanha_id IS NULL;

  -- Cria associação default (campanha × instância): tudo ON para instâncias ativas
  INSERT INTO public.campanha_instancia (campanha_id, instancia_id, ativa)
  SELECT c.id, i.id, true
    FROM public.campanhas c
    CROSS JOIN public.instancias i
   WHERE i.ativo = true
     AND i.nome <> 'Instancia ADMIN'
  ON CONFLICT (campanha_id, instancia_id) DO NOTHING;
END $$;

-- ----------------------------------------------------------------------------
-- 9) RPC escolhe_template_v2 — substitui escolhe_template antiga
--    Retorna jsonb { texto, template_id, campanha_id, anexo_url, anexo_tipo } ou NULL.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.escolhe_template_v2(
  p_categoria    text,
  p_subcategoria text,
  p_contato_id   uuid,
  p_instancia_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_pausa_global boolean;
  v_campanha     record;
  v_now_time     time;
  v_now_date     date;
  v_count        int;
  v_limite_inst  int;
  v_template     record;
  v_texto        text;
  v_contato      record;
  v_var          record;
BEGIN
  v_now_time := (NOW() AT TIME ZONE 'America/Sao_Paulo')::time;
  v_now_date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;

  -- 1. Pausa global de TODAS campanhas?
  SELECT (valor = 'true') INTO v_pausa_global FROM public.configuracoes WHERE chave = 'campanhas_pausa_global';
  IF COALESCE(v_pausa_global, false) THEN RETURN NULL; END IF;

  -- 2. Pega campanha matching: tipo + subcategoria (via templates) + ativa + sem pausa
  SELECT c.* INTO v_campanha
    FROM public.campanhas c
   WHERE c.tipo = p_categoria
     AND c.ativa = true
     AND c.pausa_global = false
     AND EXISTS (
       SELECT 1 FROM public.templates_msg t
        WHERE t.campanha_id = c.id
          AND t.ativo = true
          AND (t.subcategoria IS NOT DISTINCT FROM p_subcategoria)
     )
   ORDER BY c.created_at ASC
   LIMIT 1;
  IF v_campanha.id IS NULL THEN RETURN NULL; END IF;

  -- 3. Toggle por instância (se desativado, skip)
  IF EXISTS (
    SELECT 1 FROM public.campanha_instancia
     WHERE campanha_id = v_campanha.id
       AND instancia_id = p_instancia_id
       AND ativa = false
  ) THEN RETURN NULL; END IF;

  -- 4. Janela de horário (BRT)
  IF v_now_time < v_campanha.horario_inicio OR v_now_time > v_campanha.horario_fim THEN
    RETURN NULL;
  END IF;

  -- 5. Cooldown global do contato (qualquer campanha)
  IF v_campanha.cooldown_dias > 0 THEN
    IF EXISTS (
      SELECT 1 FROM public.campanha_envios
       WHERE contato_id = p_contato_id
         AND enviado_em > NOW() - (v_campanha.cooldown_dias || ' days')::interval
    ) THEN RETURN NULL; END IF;
  END IF;

  -- 6. Limite diário total da campanha
  IF v_campanha.limite_diario_total IS NOT NULL THEN
    SELECT count(*) INTO v_count
      FROM public.campanha_envios
     WHERE campanha_id = v_campanha.id
       AND enviado_em >= v_now_date;
    IF v_count >= v_campanha.limite_diario_total THEN RETURN NULL; END IF;
  END IF;

  -- 7. Limite diário por instância (override)
  SELECT limite_diario_instancia INTO v_limite_inst
    FROM public.campanha_instancia
   WHERE campanha_id = v_campanha.id AND instancia_id = p_instancia_id;
  IF v_limite_inst IS NOT NULL THEN
    SELECT count(*) INTO v_count
      FROM public.campanha_envios
     WHERE campanha_id = v_campanha.id
       AND instancia_id = p_instancia_id
       AND enviado_em >= v_now_date;
    IF v_count >= v_limite_inst THEN RETURN NULL; END IF;
  END IF;

  -- 8. Escolhe template (rotação determinística por hash do contato)
  SELECT t.* INTO v_template
    FROM (
      SELECT tm.*,
             count(*) OVER () AS total,
             (row_number() OVER (ORDER BY ordem, id) - 1) AS idx
        FROM public.templates_msg tm
       WHERE tm.campanha_id = v_campanha.id
         AND (tm.subcategoria IS NOT DISTINCT FROM p_subcategoria)
         AND tm.ativo = true
    ) t
   WHERE idx = abs(hashtext(p_contato_id::text)) % t.total;

  IF v_template.id IS NULL THEN RETURN NULL; END IF;

  -- 9. Substitui placeholders padrão
  v_texto := v_template.texto;
  SELECT split_part(c.nome,' ',1)  AS pri_nome,
         c.cidade,
         split_part(r.nome,' ',1)  AS rep_nome
    INTO v_contato
    FROM public.contatos c
    LEFT JOIN public.contatos r ON r.id = c.representante_id
   WHERE c.id = p_contato_id;

  v_texto := REPLACE(v_texto, '{{nome}}',     COALESCE(v_contato.pri_nome,  'amigo(a)'));
  v_texto := REPLACE(v_texto, '{{cidade}}',   COALESCE(v_contato.cidade,    ''));
  v_texto := REPLACE(v_texto, '{{rep_nome}}', COALESCE(v_contato.rep_nome,  ''));

  -- 10. Substitui variáveis globais ({{cupom_atual}}, etc)
  FOR v_var IN SELECT chave, valor FROM public.variaveis_globais LOOP
    v_texto := REPLACE(v_texto, '{{' || v_var.chave || '}}', COALESCE(v_var.valor, ''));
  END LOOP;

  -- 11. Retorna pacote pro workflow
  RETURN jsonb_build_object(
    'texto',       v_texto,
    'template_id', v_template.id,
    'campanha_id', v_campanha.id,
    'anexo_url',   v_template.anexo_url,
    'anexo_tipo',  v_template.anexo_tipo
  );
END $$;

GRANT EXECUTE ON FUNCTION public.escolhe_template_v2(text, text, uuid, uuid)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 10) RPC registrar_envio_campanha — workflows chamam após SEND ok
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_envio_campanha(
  p_campanha_id  uuid,
  p_template_id  uuid,
  p_instancia_id uuid,
  p_contato_id   uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.campanha_envios (campanha_id, template_id, instancia_id, contato_id)
  VALUES (p_campanha_id, p_template_id, p_instancia_id, p_contato_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.registrar_envio_campanha(uuid, uuid, uuid, uuid)
  TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 11) Bucket Storage para anexos
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
  VALUES ('campanhas-anexos', 'campanhas-anexos', true)
  ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public read campanhas-anexos"  ON storage.objects;
DROP POLICY IF EXISTS "Admin upload campanhas-anexos" ON storage.objects;
DROP POLICY IF EXISTS "Admin update campanhas-anexos" ON storage.objects;
DROP POLICY IF EXISTS "Admin delete campanhas-anexos" ON storage.objects;

CREATE POLICY "Public read campanhas-anexos" ON storage.objects FOR SELECT
  USING (bucket_id = 'campanhas-anexos');
CREATE POLICY "Admin upload campanhas-anexos" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'campanhas-anexos' AND public.is_admin());
CREATE POLICY "Admin update campanhas-anexos" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'campanhas-anexos' AND public.is_admin());
CREATE POLICY "Admin delete campanhas-anexos" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'campanhas-anexos' AND public.is_admin());

NOTIFY pgrst, 'reload schema';

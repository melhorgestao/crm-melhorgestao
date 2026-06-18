-- ============================================================================
-- Separa anexo de template: agora anexo é da CAMPANHA, não do template.
-- Permite N anexos rotacionados independentemente do texto.
--
-- Backward compat: templates_msg.anexo_url/anexo_tipo ficam por enquanto
-- (deprecated). escolhe_template_v2 passa a buscar anexo de campanha_anexos
-- com rotação determinística por hash(contato_id || campanha_id).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.campanha_anexos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campanha_id uuid NOT NULL REFERENCES public.campanhas(id) ON DELETE CASCADE,
  url         text NOT NULL,
  tipo        text NOT NULL CHECK (tipo IN ('image','video','audio','document')),
  ordem       int  NOT NULL DEFAULT 0,
  ativo       boolean NOT NULL DEFAULT true,
  observacao  text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_campanha_anexos_lookup
  ON public.campanha_anexos (campanha_id, ativo, ordem);

ALTER TABLE public.campanha_anexos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS campanha_anexos_admin_all ON public.campanha_anexos;
CREATE POLICY campanha_anexos_admin_all ON public.campanha_anexos
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Backfill: migra anexos atualmente presos nos templates pra campanha_anexos.
-- Deduplica por (campanha_id, url).
INSERT INTO public.campanha_anexos (campanha_id, url, tipo, ordem, ativo, observacao)
SELECT DISTINCT ON (tm.campanha_id, tm.anexo_url)
       tm.campanha_id, tm.anexo_url, tm.anexo_tipo, 0, true, 'migrado do template'
  FROM public.templates_msg tm
 WHERE tm.anexo_url IS NOT NULL
   AND tm.anexo_tipo IS NOT NULL
   AND tm.campanha_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM public.campanha_anexos ca
      WHERE ca.campanha_id = tm.campanha_id AND ca.url = tm.anexo_url
   )
ORDER BY tm.campanha_id, tm.anexo_url, tm.created_at ASC;

-- ----------------------------------------------------------------------------
-- escolhe_template_v2 atualizado: anexo agora da campanha_anexos (rotação)
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
  v_anexo        record;
  v_texto        text;
  v_contato      record;
  v_var          record;
BEGIN
  v_now_time := (NOW() AT TIME ZONE 'America/Sao_Paulo')::time;
  v_now_date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;

  SELECT (valor = 'true') INTO v_pausa_global FROM public.configuracoes WHERE chave = 'campanhas_pausa_global';
  IF COALESCE(v_pausa_global, false) THEN RETURN NULL; END IF;

  SELECT c.* INTO v_campanha
    FROM public.campanhas c
   WHERE c.tipo = p_categoria
     AND c.ativa = true
     AND c.pausa_global = false
     AND EXISTS (
       SELECT 1 FROM public.templates_msg t
        WHERE t.campanha_id = c.id AND t.ativo = true
          AND (t.subcategoria IS NOT DISTINCT FROM p_subcategoria)
     )
   ORDER BY c.created_at ASC
   LIMIT 1;
  IF v_campanha.id IS NULL THEN RETURN NULL; END IF;

  -- Toggle por instância
  IF EXISTS (
    SELECT 1 FROM public.campanha_instancia
     WHERE campanha_id = v_campanha.id AND instancia_id = p_instancia_id AND ativa = false
  ) THEN RETURN NULL; END IF;

  -- Janela horário
  IF v_now_time < v_campanha.horario_inicio OR v_now_time > v_campanha.horario_fim THEN
    RETURN NULL;
  END IF;

  -- Cooldown
  IF v_campanha.cooldown_dias > 0 THEN
    IF EXISTS (
      SELECT 1 FROM public.campanha_envios
       WHERE contato_id = p_contato_id
         AND enviado_em > NOW() - (v_campanha.cooldown_dias || ' days')::interval
    ) THEN RETURN NULL; END IF;
  END IF;

  -- Limite global
  IF v_campanha.limite_diario_total IS NOT NULL THEN
    SELECT count(*) INTO v_count FROM public.campanha_envios
     WHERE campanha_id = v_campanha.id AND enviado_em >= v_now_date;
    IF v_count >= v_campanha.limite_diario_total THEN RETURN NULL; END IF;
  END IF;

  -- Limite por instância
  SELECT limite_diario_instancia INTO v_limite_inst FROM public.campanha_instancia
   WHERE campanha_id = v_campanha.id AND instancia_id = p_instancia_id;
  IF v_limite_inst IS NOT NULL THEN
    SELECT count(*) INTO v_count FROM public.campanha_envios
     WHERE campanha_id = v_campanha.id AND instancia_id = p_instancia_id AND enviado_em >= v_now_date;
    IF v_count >= v_limite_inst THEN RETURN NULL; END IF;
  END IF;

  -- TEMPLATE (rotação por hash contato)
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

  -- ANEXO da campanha (rotação INDEPENDENTE — hash com campanha pra variar)
  SELECT a.* INTO v_anexo
    FROM (
      SELECT ca.*,
             count(*) OVER () AS total,
             (row_number() OVER (ORDER BY ordem, id) - 1) AS idx
        FROM public.campanha_anexos ca
       WHERE ca.campanha_id = v_campanha.id AND ca.ativo = true
    ) a
   WHERE idx = abs(hashtext(p_contato_id::text || v_campanha.id::text)) % a.total;

  -- Placeholders
  v_texto := v_template.texto;
  SELECT split_part(c.nome,' ',1) AS pri_nome, c.cidade, split_part(r.nome,' ',1) AS rep_nome
    INTO v_contato FROM public.contatos c
    LEFT JOIN public.contatos r ON r.id = c.representante_id
   WHERE c.id = p_contato_id;

  v_texto := REPLACE(v_texto, '{{nome}}',     COALESCE(v_contato.pri_nome,  'amigo(a)'));
  v_texto := REPLACE(v_texto, '{{cidade}}',   COALESCE(v_contato.cidade,    ''));
  v_texto := REPLACE(v_texto, '{{rep_nome}}', COALESCE(v_contato.rep_nome,  ''));

  FOR v_var IN SELECT chave, valor FROM public.variaveis_globais LOOP
    v_texto := REPLACE(v_texto, '{{' || v_var.chave || '}}', COALESCE(v_var.valor, ''));
  END LOOP;

  RETURN jsonb_build_object(
    'texto',       v_texto,
    'template_id', v_template.id,
    'campanha_id', v_campanha.id,
    'anexo_url',   v_anexo.url,
    'anexo_tipo',  v_anexo.tipo,
    'anexo_id',    v_anexo.id
  );
END $$;

GRANT EXECUTE ON FUNCTION public.escolhe_template_v2(text, text, uuid, uuid)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

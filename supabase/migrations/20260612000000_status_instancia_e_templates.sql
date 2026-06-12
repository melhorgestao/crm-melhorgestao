-- ============================================================================
-- Camada B: status de instância + tabela templates_msg + RPCs auxiliares.
-- Permite pausar/reativar instâncias dinamicamente — workflows respeitam.
-- Templates centralizados pra ativação/followup/rmkt com rotação por contato.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Status da instância
-- ----------------------------------------------------------------------------
ALTER TABLE public.instancias
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'ativo'
    CHECK (status IN ('ativo','desconectado','banido','pausado_admin')),
  ADD COLUMN IF NOT EXISTS pausado_ate timestamptz,
  ADD COLUMN IF NOT EXISTS motivo_pausa text;

CREATE INDEX IF NOT EXISTS idx_instancias_status_ativo
  ON public.instancias (status) WHERE status = 'ativo';

-- RPC pausar
CREATE OR REPLACE FUNCTION public.pausar_instancia(
  p_id uuid,
  p_motivo text,
  p_horas int DEFAULT 24
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.instancias
     SET status = CASE
                    WHEN p_motivo ILIKE '%ban%'   THEN 'banido'
                    WHEN p_motivo ILIKE '%admin%' THEN 'pausado_admin'
                    ELSE 'desconectado'
                  END,
         pausado_ate  = NOW() + (p_horas || ' hours')::interval,
         motivo_pausa = p_motivo
   WHERE id = p_id;
END; $$;

GRANT EXECUTE ON FUNCTION public.pausar_instancia(uuid, text, int)
  TO anon, authenticated, service_role;

-- RPC reativar
CREATE OR REPLACE FUNCTION public.reativar_instancia(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.instancias
     SET status='ativo', pausado_ate=NULL, motivo_pausa=NULL
   WHERE id = p_id;
END; $$;

GRANT EXECUTE ON FUNCTION public.reativar_instancia(uuid)
  TO anon, authenticated, service_role;

-- Cron de auto-reativar pausas expiradas (roda junto com os outros à meia-noite BRT = 03:00 UTC)
SELECT cron.schedule(
  'auto-reativar-instancias-pausadas',
  '0 3 * * *',
  $$
  UPDATE public.instancias
     SET status='ativo', pausado_ate=NULL, motivo_pausa=NULL
   WHERE status <> 'ativo'
     AND pausado_ate IS NOT NULL
     AND pausado_ate < NOW();
  $$
);

-- ----------------------------------------------------------------------------
-- 2) Tabela templates_msg
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.templates_msg (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  categoria    text NOT NULL CHECK (categoria IN ('ativacao','followup','rmkt')),
  subcategoria text,    -- '24h' | '3d' | '7d' (followup) | NULL (outros)
  ordem        int  NOT NULL DEFAULT 0,
  texto        text NOT NULL,
  ativo        boolean NOT NULL DEFAULT true,
  observacao   text,    -- nota interna (ex: "teste A", "tom comercial")
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_templates_lookup
  ON public.templates_msg (categoria, subcategoria, ordem)
  WHERE ativo = true;

ALTER TABLE public.templates_msg ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS templates_msg_admin_all ON public.templates_msg;
CREATE POLICY templates_msg_admin_all ON public.templates_msg
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- RPC escolhe_template: rotação determinística por contato + substitui placeholders
-- Placeholders suportados: {{nome}}, {{cidade}}, {{rep_nome}}
CREATE OR REPLACE FUNCTION public.escolhe_template(
  p_categoria text,
  p_subcategoria text,
  p_contato_id uuid
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_count int;
  v_idx int;
  v_texto text;
  v_nome text;
  v_cidade text;
  v_rep_nome text;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM public.templates_msg
   WHERE categoria = p_categoria
     AND (subcategoria IS NOT DISTINCT FROM p_subcategoria)
     AND ativo = true;

  IF v_count = 0 THEN RETURN NULL; END IF;

  -- rotação determinística — mesmo contato sempre recebe mesmo template
  v_idx := abs(hashtext(p_contato_id::text)) % v_count;

  SELECT texto INTO v_texto
    FROM public.templates_msg
   WHERE categoria = p_categoria
     AND (subcategoria IS NOT DISTINCT FROM p_subcategoria)
     AND ativo = true
   ORDER BY ordem, id
   OFFSET v_idx LIMIT 1;

  SELECT split_part(c.nome, ' ', 1), c.cidade, split_part(r.nome, ' ', 1)
    INTO v_nome, v_cidade, v_rep_nome
    FROM public.contatos c
    LEFT JOIN public.contatos r ON r.id = c.representante_id
   WHERE c.id = p_contato_id;

  v_texto := REPLACE(v_texto, '{{nome}}',     COALESCE(v_nome,     'amigo(a)'));
  v_texto := REPLACE(v_texto, '{{cidade}}',   COALESCE(v_cidade,   ''));
  v_texto := REPLACE(v_texto, '{{rep_nome}}', COALESCE(v_rep_nome, ''));

  RETURN v_texto;
END; $$;

GRANT EXECUTE ON FUNCTION public.escolhe_template(text, text, uuid)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

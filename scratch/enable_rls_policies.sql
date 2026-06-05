-- ============================================================================
-- RLS Policies — Melhor Gestão CRM
-- Roles: admin | representante | servico (atendimento | logistica)
-- Estrategia:
--   * admin: acesso total
--   * representante: linhas onde representante_id = auth.uid()
--   * atendimento: linhas onde instancia_id = perfil.instancia_id
--   * logistica:   linhas onde uf/uf_postagem/uf_origem = perfil.uf_fixa
--   * DELETE em tabelas de negocio: somente admin
--   * Lookups (produtos, instancias, ufs...): SELECT para qualquer autenticado
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. HELPER FUNCTIONS (SECURITY DEFINER -> bypassam RLS de perfis_usuario)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_tipo_usuario()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT tipo_usuario FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.current_servico_tipo()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT servico_tipo FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.current_uf_fixa()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT uf_fixa FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.current_instancia_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT instancia_id FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT tipo_usuario = 'admin' FROM public.perfis_usuario WHERE user_id = auth.uid() LIMIT 1),
    false
  )
$$;

GRANT EXECUTE ON FUNCTION public.current_tipo_usuario()  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_servico_tipo()  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_uf_fixa()       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_instancia_id()  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin()              TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. ATIVAR RLS EM TODAS AS TABELAS DE NEGOCIO
-- ---------------------------------------------------------------------------
ALTER TABLE public.perfis_usuario          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contatos                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pedidos                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pedido_itens            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lotes                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comissoes               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque_movimentacoes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque_snapshots       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque_snapshot        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financeiro              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lancamentos_socios      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follow_up               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.log_atividades          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notificacoes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metas_mensais           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.configuracoes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.config_comissao_produto ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produtos                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produtos_grupos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instancias              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remetentes_uf           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uf_regioes              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque_ufs             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.formatos_caixa          ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 3. LIMPAR POLICIES ANTIGAS (idempotencia)
-- ---------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;

-- ===========================================================================
-- 4. POLICIES
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- perfis_usuario: admin ve tudo, demais veem so o proprio perfil
-- ---------------------------------------------------------------------------
CREATE POLICY perfis_select ON public.perfis_usuario FOR SELECT TO authenticated
  USING (public.is_admin() OR user_id = auth.uid());
CREATE POLICY perfis_admin_write ON public.perfis_usuario FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- contatos
-- ---------------------------------------------------------------------------
CREATE POLICY contatos_select ON public.contatos FOR SELECT TO authenticated USING (
  public.is_admin()
  OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
  OR (public.current_servico_tipo() = 'atendimento'  AND instancia_id = public.current_instancia_id())
);
CREATE POLICY contatos_insert ON public.contatos FOR INSERT TO authenticated WITH CHECK (
  public.is_admin()
  OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
  OR (public.current_servico_tipo() = 'atendimento'  AND instancia_id = public.current_instancia_id())
);
CREATE POLICY contatos_update ON public.contatos FOR UPDATE TO authenticated
  USING (
    public.is_admin()
    OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
    OR (public.current_servico_tipo() = 'atendimento'  AND instancia_id = public.current_instancia_id())
  )
  WITH CHECK (
    public.is_admin()
    OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
    OR (public.current_servico_tipo() = 'atendimento'  AND instancia_id = public.current_instancia_id())
  );
CREATE POLICY contatos_delete ON public.contatos FOR DELETE TO authenticated
  USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- pedidos
-- ---------------------------------------------------------------------------
CREATE POLICY pedidos_select ON public.pedidos FOR SELECT TO authenticated USING (
  public.is_admin()
  OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
  OR (public.current_servico_tipo() = 'atendimento'  AND instancia_id = public.current_instancia_id())
  OR (public.current_servico_tipo() = 'logistica'    AND uf_postagem = public.current_uf_fixa())
);
CREATE POLICY pedidos_insert ON public.pedidos FOR INSERT TO authenticated WITH CHECK (
  public.is_admin()
  OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
  OR (public.current_servico_tipo() = 'atendimento'  AND instancia_id = public.current_instancia_id())
);
CREATE POLICY pedidos_update ON public.pedidos FOR UPDATE TO authenticated
  USING (
    public.is_admin()
    OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
    OR (public.current_servico_tipo() = 'atendimento'  AND instancia_id = public.current_instancia_id())
    OR (public.current_servico_tipo() = 'logistica'    AND uf_postagem = public.current_uf_fixa())
  )
  WITH CHECK (
    public.is_admin()
    OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
    OR (public.current_servico_tipo() = 'atendimento'  AND instancia_id = public.current_instancia_id())
    OR (public.current_servico_tipo() = 'logistica'    AND uf_postagem = public.current_uf_fixa())
  );
CREATE POLICY pedidos_delete ON public.pedidos FOR DELETE TO authenticated
  USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- pedido_itens (segue o acesso do pedido pai)
-- ---------------------------------------------------------------------------
CREATE POLICY pedido_itens_select ON public.pedido_itens FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.pedidos p WHERE p.id = pedido_itens.pedido_id)
);
CREATE POLICY pedido_itens_insert ON public.pedido_itens FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM public.pedidos p WHERE p.id = pedido_itens.pedido_id)
);
CREATE POLICY pedido_itens_update ON public.pedido_itens FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.pedidos p WHERE p.id = pedido_itens.pedido_id))
  WITH CHECK (EXISTS (SELECT 1 FROM public.pedidos p WHERE p.id = pedido_itens.pedido_id));
CREATE POLICY pedido_itens_delete ON public.pedido_itens FOR DELETE TO authenticated
  USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- lotes
-- ---------------------------------------------------------------------------
CREATE POLICY lotes_select ON public.lotes FOR SELECT TO authenticated USING (
  public.is_admin()
  OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
  OR (public.current_servico_tipo() = 'logistica'    AND uf = public.current_uf_fixa())
);
CREATE POLICY lotes_insert ON public.lotes FOR INSERT TO authenticated WITH CHECK (
  public.is_admin()
  OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
  OR (public.current_servico_tipo() = 'logistica'    AND uf = public.current_uf_fixa())
);
CREATE POLICY lotes_update ON public.lotes FOR UPDATE TO authenticated
  USING (
    public.is_admin()
    OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
    OR (public.current_servico_tipo() = 'logistica'    AND uf = public.current_uf_fixa())
  )
  WITH CHECK (
    public.is_admin()
    OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
    OR (public.current_servico_tipo() = 'logistica'    AND uf = public.current_uf_fixa())
  );
CREATE POLICY lotes_delete ON public.lotes FOR DELETE TO authenticated
  USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- comissoes (representante ve as suas; admin tudo)
-- ---------------------------------------------------------------------------
CREATE POLICY comissoes_select ON public.comissoes FOR SELECT TO authenticated USING (
  public.is_admin() OR representante_id = auth.uid()
);
CREATE POLICY comissoes_admin_write ON public.comissoes FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- estoque_movimentacoes (logistica filtra por uf_origem)
-- ---------------------------------------------------------------------------
CREATE POLICY estoque_mov_select ON public.estoque_movimentacoes FOR SELECT TO authenticated USING (
  public.is_admin()
  OR (public.current_servico_tipo() = 'logistica' AND uf_origem = public.current_uf_fixa())
);
CREATE POLICY estoque_mov_insert ON public.estoque_movimentacoes FOR INSERT TO authenticated WITH CHECK (
  public.is_admin()
  OR (public.current_servico_tipo() = 'logistica' AND uf_origem = public.current_uf_fixa())
);
CREATE POLICY estoque_mov_update ON public.estoque_movimentacoes FOR UPDATE TO authenticated
  USING (
    public.is_admin()
    OR (public.current_servico_tipo() = 'logistica' AND uf_origem = public.current_uf_fixa())
  )
  WITH CHECK (
    public.is_admin()
    OR (public.current_servico_tipo() = 'logistica' AND uf_origem = public.current_uf_fixa())
  );
CREATE POLICY estoque_mov_delete ON public.estoque_movimentacoes FOR DELETE TO authenticated
  USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- estoque_snapshots / estoque_snapshot (leitura por todos autenticados; escrita admin)
-- ---------------------------------------------------------------------------
CREATE POLICY estoque_snap_select ON public.estoque_snapshots FOR SELECT TO authenticated USING (true);
CREATE POLICY estoque_snap_admin  ON public.estoque_snapshots FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY estoque_snap2_select ON public.estoque_snapshot FOR SELECT TO authenticated USING (true);
CREATE POLICY estoque_snap2_admin  ON public.estoque_snapshot FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- financeiro / lancamentos_socios (admin only)
-- ---------------------------------------------------------------------------
CREATE POLICY financeiro_admin ON public.financeiro FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY lanc_socios_admin ON public.lancamentos_socios FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- follow_up (segue acesso de contatos via contato_id; admin tudo)
-- ---------------------------------------------------------------------------
CREATE POLICY follow_up_select ON public.follow_up FOR SELECT TO authenticated USING (
  public.is_admin()
  OR EXISTS (SELECT 1 FROM public.contatos c WHERE c.id = follow_up.contato_id)
);
CREATE POLICY follow_up_insert ON public.follow_up FOR INSERT TO authenticated WITH CHECK (
  public.is_admin()
  OR EXISTS (SELECT 1 FROM public.contatos c WHERE c.id = follow_up.contato_id)
);
CREATE POLICY follow_up_update ON public.follow_up FOR UPDATE TO authenticated
  USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.contatos c WHERE c.id = follow_up.contato_id))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.contatos c WHERE c.id = follow_up.contato_id));
CREATE POLICY follow_up_delete ON public.follow_up FOR DELETE TO authenticated
  USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- log_atividades (insert livre p/ autenticados; SELECT admin; sem update/delete)
-- ---------------------------------------------------------------------------
CREATE POLICY log_atividades_select ON public.log_atividades FOR SELECT TO authenticated
  USING (public.is_admin());
CREATE POLICY log_atividades_insert ON public.log_atividades FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- ---------------------------------------------------------------------------
-- notificacoes (autenticado le/escreve; delete admin)
-- ---------------------------------------------------------------------------
CREATE POLICY notif_select ON public.notificacoes FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY notif_insert ON public.notificacoes FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY notif_update ON public.notificacoes FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY notif_delete ON public.notificacoes FOR DELETE TO authenticated USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- metas_mensais / configuracoes / config_comissao_produto
-- (autenticado le; admin escreve)
-- ---------------------------------------------------------------------------
CREATE POLICY metas_select ON public.metas_mensais FOR SELECT TO authenticated USING (true);
CREATE POLICY metas_admin  ON public.metas_mensais FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY config_select ON public.configuracoes FOR SELECT TO authenticated USING (true);
CREATE POLICY config_admin  ON public.configuracoes FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY config_comissao_select ON public.config_comissao_produto FOR SELECT TO authenticated USING (true);
CREATE POLICY config_comissao_admin  ON public.config_comissao_produto FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- LOOKUPS: leitura para qualquer autenticado, escrita admin
-- ---------------------------------------------------------------------------
CREATE POLICY produtos_select ON public.produtos FOR SELECT TO authenticated USING (true);
CREATE POLICY produtos_admin  ON public.produtos FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY produtos_grupos_select ON public.produtos_grupos FOR SELECT TO authenticated USING (true);
CREATE POLICY produtos_grupos_admin  ON public.produtos_grupos FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY instancias_select ON public.instancias FOR SELECT TO authenticated USING (true);
CREATE POLICY instancias_admin  ON public.instancias FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY remetentes_uf_select ON public.remetentes_uf FOR SELECT TO authenticated USING (true);
CREATE POLICY remetentes_uf_admin  ON public.remetentes_uf FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY uf_regioes_select ON public.uf_regioes FOR SELECT TO authenticated USING (true);
CREATE POLICY uf_regioes_admin  ON public.uf_regioes FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY estoque_ufs_select ON public.estoque_ufs FOR SELECT TO authenticated USING (true);
CREATE POLICY estoque_ufs_admin  ON public.estoque_ufs FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY formatos_caixa_select ON public.formatos_caixa FOR SELECT TO authenticated USING (true);
CREATE POLICY formatos_caixa_admin  ON public.formatos_caixa FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- 5. GRANTS (mantem o que ja existia + garante service_role bypass)
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO authenticated;
GRANT SELECT                          ON ALL TABLES   IN SCHEMA public TO anon;
GRANT ALL                             ON ALL TABLES   IN SCHEMA public TO service_role;
GRANT USAGE, SELECT                   ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
GRANT EXECUTE                         ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;

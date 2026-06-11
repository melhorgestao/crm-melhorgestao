-- ============================================================================
-- Remove pedidos.instancia_id — fonte de verdade é contatos.instancia_id.
-- Coluna foi adicionada em 20260406...fase1_schema mas nunca foi consumida
-- pela UI nem workflows (exceto o rastreio multi-instância recém criado,
-- que agora lê direto de contatos.instancia_id).
-- ============================================================================

-- Drop trigger que herdava instância do contato (não faz mais sentido)
DROP TRIGGER IF EXISTS trg_pedidos_herda_instancia ON public.pedidos;
DROP FUNCTION IF EXISTS public.pedidos_herda_instancia_contato();

-- Drop policies dependentes — serão recriadas usando contato.instancia_id
DROP POLICY IF EXISTS pedidos_select ON public.pedidos;
DROP POLICY IF EXISTS pedidos_insert ON public.pedidos;
DROP POLICY IF EXISTS pedidos_update ON public.pedidos;

-- Drop FK + coluna
ALTER TABLE public.pedidos DROP CONSTRAINT IF EXISTS pedidos_instancia_id_fkey;
ALTER TABLE public.pedidos DROP COLUMN IF EXISTS instancia_id;

-- Recria policies — atendentes filtram pela instância do CONTATO via subquery
CREATE POLICY pedidos_select ON public.pedidos FOR SELECT TO authenticated USING (
  public.is_admin()
  OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
  OR (public.current_servico_tipo() = 'atendimento'  AND EXISTS (
        SELECT 1 FROM public.contatos c
         WHERE c.id = pedidos.contato_id
           AND c.instancia_id = public.current_instancia_id()))
  OR (public.current_servico_tipo() = 'logistica'    AND uf_postagem = public.current_uf_fixa())
);

CREATE POLICY pedidos_insert ON public.pedidos FOR INSERT TO authenticated WITH CHECK (
  public.is_admin()
  OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
  OR (public.current_servico_tipo() = 'atendimento'  AND EXISTS (
        SELECT 1 FROM public.contatos c
         WHERE c.id = pedidos.contato_id
           AND c.instancia_id = public.current_instancia_id()))
);

CREATE POLICY pedidos_update ON public.pedidos FOR UPDATE TO authenticated
  USING (
    public.is_admin()
    OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
    OR (public.current_servico_tipo() = 'atendimento'  AND EXISTS (
          SELECT 1 FROM public.contatos c
           WHERE c.id = pedidos.contato_id
             AND c.instancia_id = public.current_instancia_id()))
    OR (public.current_servico_tipo() = 'logistica'    AND uf_postagem = public.current_uf_fixa())
  )
  WITH CHECK (
    public.is_admin()
    OR (public.current_tipo_usuario() = 'representante' AND representante_id = auth.uid())
    OR (public.current_servico_tipo() = 'atendimento'  AND EXISTS (
          SELECT 1 FROM public.contatos c
           WHERE c.id = pedidos.contato_id
             AND c.instancia_id = public.current_instancia_id()))
    OR (public.current_servico_tipo() = 'logistica'    AND uf_postagem = public.current_uf_fixa())
  );

NOTIFY pgrst, 'reload schema';

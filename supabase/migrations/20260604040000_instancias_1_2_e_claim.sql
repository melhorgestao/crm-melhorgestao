-- ============================================================================
-- Multi-chip strategy: renomeia instâncias + corrige midnight + RPC de claim
--
-- Mudanças:
--   1) instancias.nome: 'BASE' → '1', 'ADS' → '2' (cosmético; FKs por UUID)
--   2) perform_midnight_lead_migration: COALESCE invertido pra PRESERVAR
--      instancia_id existente (lead "fica" no chip que claimou primeiro)
--   3) Nova RPC marca_enviado_rmkt: atualiza rem_status='enviado' E faz
--      claim em instancia_id se ainda NULL — chamada pelo n8n após SEND
--      MSG EVO bem-sucedido.
-- ============================================================================

-- 1) Rename
UPDATE public.instancias SET nome = '1' WHERE tipo = 'base';
UPDATE public.instancias SET nome = '2' WHERE tipo = 'ads';

-- 2) Midnight cron: preservar instancia_id existente
CREATE OR REPLACE FUNCTION public.perform_midnight_lead_migration()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_base_instance_id uuid;
BEGIN
    SELECT id INTO v_base_instance_id
    FROM public.instancias
    WHERE tipo = 'base' AND ativo = true
    ORDER BY is_default_base DESC, created_at ASC
    LIMIT 1;

    -- ADS -> BASE: cliente que pagou ontem migra pra Clientes
    -- COALESCE INVERTIDO: prioriza instancia_id existente (claim do chip dono)
    UPDATE public.contatos
    SET canal_origem = 'BASE',
        status_kanban = 'Clientes',
        instancia_id = COALESCE(instancia_id, v_base_instance_id),
        updated_at = now()
    WHERE canal_origem = 'ADS' AND ultima_venda_em = CURRENT_DATE - 1;

    -- REP: mesma lógica, preserva instancia_id se já claimado
    UPDATE public.contatos
    SET status_kanban = 'Clientes',
        instancia_id = COALESCE(instancia_id, v_base_instance_id),
        updated_at = now()
    WHERE canal_origem = 'REP'
      AND ultima_venda_em = CURRENT_DATE - 1
      AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    -- C-REP: idem
    UPDATE public.contatos
    SET status_kanban = 'Clientes',
        instancia_id = COALESCE(instancia_id, v_base_instance_id),
        updated_at = now()
    WHERE canal_origem = 'C-REP'
      AND ultima_venda_em = CURRENT_DATE - 1
      AND (status_kanban != 'Clientes' OR status_kanban IS NULL);

    INSERT INTO public.configuracoes (chave, valor)
    VALUES ('ultimo_auto_lead_migration', CURRENT_DATE::text)
    ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

    RETURN json_build_object('success', true);
END;
$$;

-- 3) RPC chamada pelo n8n RMKT BASE após dispatch bem-sucedido
-- Faz 2 coisas atomicamente:
--   a) Marca rem_status = 'enviado'
--   b) Claim: seta instancia_id = p_instancia_id SE ainda NULL
--      (lead fica permanentemente "dono" do chip que disparou primeiro)
CREATE OR REPLACE FUNCTION public.marca_enviado_rmkt(
  p_contato_id UUID,
  p_instancia_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_instancia_anterior UUID;
  v_claimed BOOLEAN;
BEGIN
  SELECT instancia_id INTO v_instancia_anterior
  FROM contatos WHERE id = p_contato_id;

  v_claimed := (v_instancia_anterior IS NULL);

  UPDATE contatos
  SET rem_status = 'enviado',
      instancia_id = COALESCE(instancia_id, p_instancia_id),
      updated_at = NOW()
  WHERE id = p_contato_id;

  RETURN jsonb_build_object(
    'contato_id', p_contato_id,
    'claimed_now', v_claimed,
    'instancia_id_final', COALESCE(v_instancia_anterior, p_instancia_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.marca_enviado_rmkt(UUID, UUID)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

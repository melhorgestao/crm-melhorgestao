-- ============================================================================
-- RPC de DIAGNÓSTICO do RMKT (leitura, sem efeito colateral).
--
-- Responde: por que a coluna RMKT do Kanban está vazia?
-- Mostra, em ordem de eliminação, quantos clientes passam em cada requisito
-- da view v_kanban_rmkt_wait — e quantos são "clientes antigos importados"
-- (ja_comprou sem venda registrada), que hoje NÃO qualificam.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.debug_rmkt_diagnostico()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_camp jsonb;
  v_out  jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'nome', nome, 'ativa', ativa, 'pausa_global', pausa_global,
           'max_envios', rmkt_max_envios, 'gap_dias', dias_sem_envio,
           'g12', rmkt_gap_1_2_dias, 'g35', rmkt_gap_3_5_dias, 'g5p', rmkt_gap_5_plus_dias
         )), '[]'::jsonb)
    INTO v_camp
    FROM public.campanhas WHERE tipo = 'rmkt';

  SELECT jsonb_build_object(
    'campanhas_rmkt', v_camp,
    'tem_campanha_ativa', EXISTS(
      SELECT 1 FROM public.campanhas
       WHERE tipo='rmkt' AND ativa = true AND pausa_global = false),
    'funil', jsonb_build_object(
      'total_contatos',        (SELECT count(*) FROM contatos),
      'ja_comprou',            (SELECT count(*) FROM contatos WHERE ja_comprou = true),
      'estado_cliente',        (SELECT count(*) FROM contatos WHERE ja_comprou = true AND ultima_interacao = 'cliente'),
      'com_telefone',          (SELECT count(*) FROM contatos WHERE ja_comprou = true AND ultima_interacao = 'cliente' AND telefone IS NOT NULL),
      'com_ultima_venda_em',   (SELECT count(*) FROM contatos WHERE ja_comprou = true AND ultima_interacao = 'cliente' AND telefone IS NOT NULL AND ultima_venda_em IS NOT NULL),
      'ciclo_nao_estourado',   (SELECT count(*) FROM contatos WHERE ja_comprou = true AND ultima_interacao = 'cliente' AND telefone IS NOT NULL AND ultima_venda_em IS NOT NULL AND COALESCE(rmkt_consecutive_silenciosos,0) < 3),
      'na_view_rmkt_wait',     (SELECT count(*) FROM v_kanban_rmkt_wait)
    ),
    'bloqueios', jsonb_build_object(
      'cliente_sem_ultima_venda_em', (
        SELECT count(*) FROM contatos
         WHERE ja_comprou = true AND ultima_interacao = 'cliente' AND ultima_venda_em IS NULL),
      'ja_comprou_sem_pedido_no_crm', (
        SELECT count(*) FROM contatos c
         WHERE c.ja_comprou = true
           AND NOT EXISTS (SELECT 1 FROM pedidos p WHERE p.contato_id = c.id AND p.status_pedido <> 'cancelado')),
      'ja_comprou_estado_diferente_de_cliente', (
        SELECT COALESCE(jsonb_object_agg(COALESCE(ultima_interacao,'(null)'), qt), '{}'::jsonb)
          FROM (SELECT ultima_interacao, count(*) qt FROM contatos
                 WHERE ja_comprou = true AND COALESCE(ultima_interacao,'x') <> 'cliente'
                 GROUP BY 1 ORDER BY 2 DESC LIMIT 10) s),
      'em_cooldown_marketing', (
        SELECT count(*) FROM contatos
         WHERE marketing_cooldown_ate IS NOT NULL AND marketing_cooldown_ate > NOW())
    )
  ) INTO v_out;

  RETURN v_out;
END $$;

GRANT EXECUTE ON FUNCTION public.debug_rmkt_diagnostico() TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

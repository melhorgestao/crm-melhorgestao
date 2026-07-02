-- ============================================================================
-- View v_kanban_rmkt_wait: clientes ELEGÍVEIS pra RMKT (fase "wait").
--
-- Espelha EXATAMENTE a elegibilidade do claim_proximo_lead_rmkt (sem o filtro
-- de instância — o Kanban filtra no front). Usada pra mostrar cards WAIT na
-- coluna RMKT, análogo ao wait_follow_up da coluna Follow-up.
--
-- Um cliente fica em WAIT enquanto:
--   - já comprou, estado 'cliente', tem telefone
--   - rmkt_consecutive_silenciosos < max (não estourou o ciclo 3x)
--   - passou o gap desde a última compra (30/45/60 por qtd do último pedido)
--   - passou o gap entre RMKTs (dias_sem_envio)
--   - sem cooldown de marketing
-- Sai da WAIT quando: dispara (vira 'rmkt') ou compra (zera contador) ou
-- estoura 3x (contador >= max) → some da view.
--
-- proxima_rmkt_em = ultima_venda_em + gap_por_qtd (pra ordenar "mais próximo
-- a disparar primeiro").
-- ============================================================================

CREATE OR REPLACE VIEW public.v_kanban_rmkt_wait AS
WITH camp AS (
  SELECT rmkt_gap_1_2_dias    AS g12,
         rmkt_gap_3_5_dias    AS g35,
         rmkt_gap_5_plus_dias AS g5p,
         rmkt_max_envios      AS maxe,
         dias_sem_envio       AS gap
  FROM public.campanhas
  WHERE tipo = 'rmkt' AND ativa = true AND pausa_global = false
  ORDER BY created_at ASC
  LIMIT 1
)
SELECT
  c.id,
  c.nome,
  c.telefone,
  c.canal_origem,
  c.canal_atual,
  c.instancia_id,
  c.created_at,
  c.updated_at,
  c.tag_kanban,
  c.tag_kanban_ate,
  c.ultima_interacao,
  c.ja_comprou,
  c.follow_up_tentativas,
  c.ativacao_tentativas,
  c.data_start,
  c.data_wait_follow_up,
  c.data_ultimo_follow_up,
  c.data_em_fechamento,
  c.data_ultimo_rmkt,
  c.data_suporte,
  c.suporte_motivo,
  c.bot_pausado_ate,
  c.ultima_venda_em,
  c.qtd_ultimo_pedido,
  c.rmkt_consecutive_silenciosos,
  i.nome   AS inst_nome,
  i.numero AS inst_numero,
  (c.ultima_venda_em + (
     CASE
       WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 1 AND 2 THEN COALESCE(camp.g12,30)
       WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 3 AND 5 THEN COALESCE(camp.g35,45)
       ELSE                                                       COALESCE(camp.g5p,60)
     END || ' days')::interval
  ) AS proxima_rmkt_em
FROM public.contatos c
CROSS JOIN camp
LEFT JOIN public.instancias i ON i.id = c.instancia_id
WHERE c.ja_comprou = true
  AND c.ultima_interacao = 'cliente'
  AND c.telefone IS NOT NULL
  AND COALESCE(c.rmkt_consecutive_silenciosos, 0) < COALESCE(camp.maxe, 3)
  AND (c.data_ultimo_rmkt IS NULL
       OR c.data_ultimo_rmkt < NOW() - (COALESCE(camp.gap,30) || ' days')::interval)
  AND c.ultima_venda_em < NOW() - (
     CASE
       WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 1 AND 2 THEN COALESCE(camp.g12,30)
       WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 3 AND 5 THEN COALESCE(camp.g35,45)
       ELSE                                                       COALESCE(camp.g5p,60)
     END || ' days')::interval
  AND (c.marketing_cooldown_ate IS NULL OR c.marketing_cooldown_ate < NOW());

GRANT SELECT ON public.v_kanban_rmkt_wait TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

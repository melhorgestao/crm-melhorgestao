-- ============================================================================
-- v_kanban_rmkt_wait v2:
--   1) Inclui clientes JÁ EM CICLO (rmkt_consecutive_silenciosos >= 1 e < max)
--      mesmo que ainda não passou o gap por qtd — pra card ficar visível
--      entre disparos até estourar 3x.
--   2) Adiciona ultimo_pedido_id e ultimo_pedido_order pro modal Detalhes.
--   3) qtd_ultimo_pedido continua vindo (pro ícone da caixa).
--
-- Efeito: coluna RMKT no Kanban SEMPRE tem noção real de quem está em ciclo.
-- Sai da view só quando: comprou (zera contador) ou estourou max (>=3).
-- ============================================================================

DROP VIEW IF EXISTS public.v_kanban_rmkt_wait;

CREATE VIEW public.v_kanban_rmkt_wait AS
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
),
ult_pedido AS (
  SELECT DISTINCT ON (p.contato_id)
         p.contato_id, p.id AS pedido_id, p.order_number
  FROM public.pedidos p
  WHERE p.status_pedido != 'cancelado'
  ORDER BY p.contato_id, p.created_at DESC
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
  up.pedido_id     AS ultimo_pedido_id,
  up.order_number  AS ultimo_pedido_order,
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
LEFT JOIN ult_pedido up       ON up.contato_id = c.id
WHERE c.ja_comprou = true
  AND c.ultima_interacao = 'cliente'
  AND c.telefone IS NOT NULL
  AND c.ultima_venda_em IS NOT NULL
  AND COALESCE(c.rmkt_consecutive_silenciosos, 0) < COALESCE(camp.maxe, 3)
  AND (
      -- Elegível AGORA (nunca disparou ou passou gap por qtd) → WAIT "pronto"
      (
        COALESCE(c.rmkt_consecutive_silenciosos, 0) = 0
        AND c.ultima_venda_em < NOW() - (
           CASE
             WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 1 AND 2 THEN COALESCE(camp.g12,30)
             WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 3 AND 5 THEN COALESCE(camp.g35,45)
             ELSE                                                       COALESCE(camp.g5p,60)
           END || ' days')::interval
        AND (c.data_ultimo_rmkt IS NULL
             OR c.data_ultimo_rmkt < NOW() - (COALESCE(camp.gap,30) || ' days')::interval)
        AND (c.marketing_cooldown_ate IS NULL OR c.marketing_cooldown_ate < NOW())
      )
      -- OU já em ciclo (disparou pelo menos 1x, contador entre 1 e max-1)
      OR (
        COALESCE(c.rmkt_consecutive_silenciosos, 0) >= 1
        AND COALESCE(c.rmkt_consecutive_silenciosos, 0) < COALESCE(camp.maxe, 3)
      )
  );

GRANT SELECT ON public.v_kanban_rmkt_wait TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

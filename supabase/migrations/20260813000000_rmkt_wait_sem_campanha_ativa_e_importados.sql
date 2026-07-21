-- ============================================================================
-- v_kanban_rmkt_wait v3 — fila de espera REAL do RMKT.
--
-- PROBLEMA 1 (coluna RMKT vazia): a v2 fazia CROSS JOIN com campanhas
-- filtrando ativa=true AND pausa_global=false. Com a campanha DESATIVADA, esse
-- lado vem vazio e o CROSS JOIN zera a view INTEIRA — nenhum qualificado
-- aparecia. Mas a coluna deve mostrar quem está na fila AGUARDANDO a campanha
-- ser ligada. FIX: config vira subquery escalar com fallback (campanha ativa →
-- qualquer campanha rmkt → defaults 30/45/60, max 3). A view nunca mais zera
-- por causa de campanha desligada.
--
-- PROBLEMA 2 (clientes antigos importados): exigia ultima_venda_em NOT NULL.
-- Cliente importado (ja_comprou=true, sem pedido no CRM) não tem essa data e
-- ficava fora pra sempre. Regra do dono: esses qualificam IMEDIATAMENTE.
-- FIX: quem tem ja_comprou=true e NÃO tem ultima_venda_em entra na hora
-- (não há gap a cumprir — não existe compra registrada pra contar a partir).
-- Também aceita ultima_interacao NULL (importado que nunca interagiu), além
-- de 'cliente'. Estados ativos (suporte, em_fechamento, start...) seguem fora.
--
-- NÃO cria estado novo em ultima_interacao — é só leitura pro Kanban.
-- ============================================================================

DROP VIEW IF EXISTS public.v_kanban_rmkt_wait;

CREATE VIEW public.v_kanban_rmkt_wait AS
WITH camp AS (
  -- Config do RMKT com FALLBACK: prioriza campanha ativa; se não houver,
  -- usa qualquer campanha rmkt (pra respeitar os gaps configurados); se não
  -- houver nenhuma, usa defaults. Sempre devolve exatamente 1 linha.
  SELECT
    COALESCE((SELECT rmkt_gap_1_2_dias    FROM public.campanhas WHERE tipo='rmkt' AND ativa AND NOT pausa_global ORDER BY created_at LIMIT 1),
             (SELECT rmkt_gap_1_2_dias    FROM public.campanhas WHERE tipo='rmkt' ORDER BY created_at LIMIT 1), 30) AS g12,
    COALESCE((SELECT rmkt_gap_3_5_dias    FROM public.campanhas WHERE tipo='rmkt' AND ativa AND NOT pausa_global ORDER BY created_at LIMIT 1),
             (SELECT rmkt_gap_3_5_dias    FROM public.campanhas WHERE tipo='rmkt' ORDER BY created_at LIMIT 1), 45) AS g35,
    COALESCE((SELECT rmkt_gap_5_plus_dias FROM public.campanhas WHERE tipo='rmkt' AND ativa AND NOT pausa_global ORDER BY created_at LIMIT 1),
             (SELECT rmkt_gap_5_plus_dias FROM public.campanhas WHERE tipo='rmkt' ORDER BY created_at LIMIT 1), 60) AS g5p,
    COALESCE((SELECT rmkt_max_envios      FROM public.campanhas WHERE tipo='rmkt' AND ativa AND NOT pausa_global ORDER BY created_at LIMIT 1),
             (SELECT rmkt_max_envios      FROM public.campanhas WHERE tipo='rmkt' ORDER BY created_at LIMIT 1), 3)  AS maxe,
    COALESCE((SELECT dias_sem_envio       FROM public.campanhas WHERE tipo='rmkt' AND ativa AND NOT pausa_global ORDER BY created_at LIMIT 1),
             (SELECT dias_sem_envio       FROM public.campanhas WHERE tipo='rmkt' ORDER BY created_at LIMIT 1), 30) AS gap
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
  -- Importado (sem venda registrada) → já está pronto: próxima = agora.
  CASE
    WHEN c.ultima_venda_em IS NULL THEN NOW()
    ELSE c.ultima_venda_em + (
      CASE
        WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 1 AND 2 THEN camp.g12
        WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 3 AND 5 THEN camp.g35
        ELSE                                                       camp.g5p
      END || ' days')::interval
  END AS proxima_rmkt_em
FROM public.contatos c
CROSS JOIN camp
LEFT JOIN public.instancias i ON i.id = c.instancia_id
LEFT JOIN ult_pedido up       ON up.contato_id = c.id
WHERE c.ja_comprou = true
  AND c.telefone IS NOT NULL
  -- 'cliente' OU importado que nunca interagiu (estado NULL).
  -- Estados ativos (suporte, em_fechamento, start, wait_follow_up, NUNCA_MAIS)
  -- continuam fora — não se faz remarketing de quem está em atendimento.
  AND (c.ultima_interacao = 'cliente' OR c.ultima_interacao IS NULL)
  AND COALESCE(c.rmkt_consecutive_silenciosos, 0) < camp.maxe
  AND (c.marketing_cooldown_ate IS NULL OR c.marketing_cooldown_ate < NOW())
  AND (
      -- (a) IMPORTADO: ja_comprou porém sem venda registrada no CRM →
      --     qualifica IMEDIATAMENTE (não há data-base pra contar gap).
      (
        c.ultima_venda_em IS NULL
        AND COALESCE(c.rmkt_consecutive_silenciosos, 0) = 0
        AND (c.data_ultimo_rmkt IS NULL
             OR c.data_ultimo_rmkt < NOW() - (camp.gap || ' days')::interval)
      )
      -- (b) Elegível pelo gap desde a última venda
      OR (
        c.ultima_venda_em IS NOT NULL
        AND COALESCE(c.rmkt_consecutive_silenciosos, 0) = 0
        AND c.ultima_venda_em < NOW() - (
           CASE
             WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 1 AND 2 THEN camp.g12
             WHEN COALESCE(c.qtd_ultimo_pedido,1) BETWEEN 3 AND 5 THEN camp.g35
             ELSE                                                       camp.g5p
           END || ' days')::interval
        AND (c.data_ultimo_rmkt IS NULL
             OR c.data_ultimo_rmkt < NOW() - (camp.gap || ' days')::interval)
      )
      -- (c) Já em ciclo (disparou 1x+, ainda não estourou o máximo)
      OR (
        COALESCE(c.rmkt_consecutive_silenciosos, 0) >= 1
        AND COALESCE(c.rmkt_consecutive_silenciosos, 0) < camp.maxe
      )
  );

GRANT SELECT ON public.v_kanban_rmkt_wait TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

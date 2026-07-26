-- ============================================================================
-- Follow-up "4h real" + timer "Sumiu há" baseado na ÚLTIMA MENSAGEM DO LEAD.
--
-- Três correções coerentes entre si:
--
-- 1) NOME DA CAMPANHA: a linha em campanhas ainda se chama 'Follow-up 24h'
--    (semeada na 20260614). O rename 20260820 trocou templates + label do
--    claim, mas não o nome da campanha — por isso o card do CRM mostra "24h".
--    A 1ª tentativa dispara em ~4h, então o nome passa a 'Follow-up 4h'.
--
-- 2) data_ultima_entrada CONFIÁVEL EM PRODUÇÃO. Esse campo (silêncio do lead)
--    só era carimbado pelo router-ingest. Mas o workflow n8n ativo NÃO usa o
--    router-ingest pra mensagem normal de lead — ele chama get_or_create_contato
--    direto. Resultado: em produção data_ultima_entrada ficava NULL/velho, e:
--       - o timer "Sumiu há X" não tinha o silêncio real (caía pra "Agora");
--       - o relógio de silêncio do start->wait degradava pra só data_start.
--    FIX: carimbar data_ultima_entrada = NOW() dentro do get_or_create_contato
--    (INSERT e UPDATE). Toda chamada dessa função é um inbound do lead, então
--    é o ponto certo. Passa a valer no fluxo de produção sem tocar no n8n.
--
-- 3) SEM DUPLO GAP. O claim da 1ª tentativa já usa INTERVAL '0' — o lead
--    qualifica no instante em que entra em wait_follow_up (não há um 2º 4h).
--    Com data_ultima_entrada carimbado, o lead CHEGA na coluna já com o
--    silêncio real (~4h) e já elegível. Aqui só reforço o claim ancorando a
--    1ª tentativa no silêncio real (GREATEST(data_ultima_entrada,
--    data_wait_follow_up)), pra o disparo nunca depender de quando o cron
--    rodou a transição, e sim de quando o lead realmente sumiu.
--
-- NÃO muda: 4h do start->wait, 3d/7d das tentativas 2/3, máx 3, RMKT, mudo.
-- ============================================================================

-- 1) Nome da campanha ---------------------------------------------------------
UPDATE public.campanhas
   SET nome = 'Follow-up 4h', updated_at = now()
 WHERE tipo = 'followup' AND nome = 'Follow-up 24h';

-- Backfill best-effort: leads sem data_ultima_entrada recebem o último inbound
-- conhecido do buffer (pra os que já estão em start/wait agora).
UPDATE public.contatos c
   SET data_ultima_entrada = sub.ult
  FROM (
    SELECT contato_id, MAX(recebida_em) AS ult
      FROM public.mensagens_buffer
     WHERE direcao = 'in'
     GROUP BY contato_id
  ) sub
 WHERE sub.contato_id = c.id
   AND c.data_ultima_entrada IS NULL;

-- 2) get_or_create_contato = versão 20260826 (mudo + nome + ADS) + carimbo de
--    data_ultima_entrada em cada inbound.
CREATE OR REPLACE FUNCTION public.get_or_create_contato(
  p_telefone     TEXT,
  p_nome         TEXT DEFAULT NULL,
  p_instancia_id UUID DEFAULT NULL,
  p_canal_origem TEXT DEFAULT 'BASE',
  p_metadata     JSONB DEFAULT NULL,
  p_mensagem     TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized  TEXT;
  v_contato_id  UUID;
  v_was_created BOOLEAN := false;
  v_result      jsonb;
  v_is_ads      BOOLEAN := false;
  v_msg         TEXT;
  v_nome_in     TEXT;
  v_mudo        BOOLEAN := false;
BEGIN
  v_normalized := public.normalize_telefone_br(p_telefone);
  IF v_normalized IS NULL OR length(v_normalized) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'telefone inválido');
  END IF;

  v_nome_in := NULLIF(TRIM(COALESCE(p_nome, '')), '');
  IF public.nome_e_placeholder(v_nome_in) THEN
    v_nome_in := NULL;
  END IF;

  SELECT c.id INTO v_contato_id
  FROM public.contatos c
  WHERE c.telefone IS NOT NULL
    AND public.telefone_br_match(c.telefone, p_telefone)
  ORDER BY c.created_at ASC
  LIMIT 1;

  v_msg := LOWER(TRIM(COALESCE(p_mensagem, '')));
  IF p_canal_origem = 'ADS'
     OR COALESCE(p_metadata->>'ctwa_source_id', '') <> ''
     OR COALESCE(p_metadata->>'ctwa_source_url', '') <> ''
     OR v_msg LIKE '%saber mais%'
     OR v_msg LIKE '%vi o an%ncio%'
     OR v_msg LIKE '%vim pelo an%ncio%'
     OR v_msg LIKE '%vi seu an%ncio%'
     OR v_msg LIKE '%vi um an%ncio%'
     OR v_msg LIKE '%pelo an%ncio%'
     OR v_msg LIKE '%do an%ncio%'
  THEN
    v_is_ads := true;
  END IF;

  IF v_contato_id IS NULL THEN
    BEGIN
      INSERT INTO public.contatos (
        nome, telefone, canal_origem, canal_atual,
        instancia_id, ultima_interacao, data_ultima_entrada, created_at, updated_at
      )
      VALUES (
        COALESCE(v_nome_in, v_normalized),
        v_normalized,
        CASE WHEN v_is_ads THEN 'ADS' ELSE p_canal_origem END,
        CASE WHEN v_is_ads THEN 'ADS' ELSE p_canal_origem END,
        p_instancia_id,
        'start',
        NOW(),        -- data_ultima_entrada: 1º inbound do lead
        NOW(),
        NOW()
      )
      RETURNING contatos.id INTO v_contato_id;
      v_was_created := true;
    EXCEPTION WHEN unique_violation THEN
      SELECT c.id INTO v_contato_id
      FROM public.contatos c
      WHERE c.telefone IS NOT NULL
        AND public.telefone_canonico_br(c.telefone) = public.telefone_canonico_br(v_normalized)
      ORDER BY c.created_at ASC
      LIMIT 1;
    END;
  END IF;

  IF NOT v_was_created AND v_contato_id IS NOT NULL THEN
    UPDATE public.contatos
    SET ultima_interacao = COALESCE(ultima_interacao, 'start'),
        canal_origem     = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_origem END,
        canal_atual      = CASE WHEN v_is_ads THEN 'ADS' ELSE canal_atual END,
        instancia_id     = COALESCE(p_instancia_id, instancia_id),
        telefone         = v_normalized,
        -- lead acabou de escrever → zera o relógio de silêncio ("Agora")
        data_ultima_entrada = NOW(),
        nome             = CASE
          WHEN v_nome_in IS NOT NULL AND public.nome_e_placeholder(nome)
          THEN v_nome_in
          ELSE nome
        END,
        updated_at       = NOW()
    WHERE id = v_contato_id;
  END IF;

  SELECT jsonb_build_object(
    'id',               c.id,
    'nome',             c.nome,
    'telefone',         c.telefone,
    'ultima_interacao', c.ultima_interacao,
    'ja_comprou',       c.ja_comprou,
    'bot_pausado_ate',  c.bot_pausado_ate,
    'canal_origem',     c.canal_origem,
    'canal_atual',      c.canal_atual,
    'instancia_id',     c.instancia_id,
    'was_created',      v_was_created
  ) INTO v_result
  FROM public.contatos c
  WHERE c.id = v_contato_id;

  -- MODO MUDO: contato salvo, mas o retorno diz "bot pausado" (sintético) pra
  -- o workflow não seguir pro agente/envio.
  v_mudo := public.instancia_esta_muda(
              COALESCE(p_instancia_id, (SELECT instancia_id FROM public.contatos WHERE id = v_contato_id))
            );
  IF v_mudo THEN
    v_result := v_result
      || jsonb_build_object(
           'agente_mudo',     true,
           'motivo',          'agente_mudo',
           'bot_pausado_ate', (NOW() + INTERVAL '100 years')
         );
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_contato(TEXT, TEXT, UUID, TEXT, JSONB, TEXT)
  TO authenticated, anon, service_role;

-- 3) Claim followup: 1ª tentativa ancorada no SILÊNCIO REAL do lead.
--    Recria o corpo *_raw (a 20260825 embrulha com a trava de modo mudo, que
--    continua chamando este _raw). Tudo igual à 20260820, exceto a âncora da
--    tent 1: em vez de data_wait_follow_up (quando o cron rodou), usa
--    GREATEST(data_ultima_entrada, data_wait_follow_up) — o disparo passa a
--    depender de quando o lead sumiu, não de quando a transição aconteceu.
CREATE OR REPLACE FUNCTION public.claim_proximo_lead_followup_raw(p_instancia_id uuid)
RETURNS TABLE (id uuid, nome text, telefone text, subcategoria text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  UPDATE public.contatos c
  SET follow_up_reservado_ate = NOW() + INTERVAL '5 minutes',
      instancia_id            = p_instancia_id,
      updated_at              = NOW()
  WHERE c.id = (
    SELECT c2.id FROM public.contatos c2
    WHERE c2.ultima_interacao = 'wait_follow_up'
      AND c2.ja_comprou = false
      AND c2.telefone IS NOT NULL
      AND COALESCE(c2.ativacao_tentativas, 0) = 0
      AND (c2.instancia_id IS NULL OR c2.instancia_id = p_instancia_id)
      AND c2.follow_up_tentativas < 3
      AND (c2.marketing_cooldown_ate IS NULL OR c2.marketing_cooldown_ate < NOW())
      -- CADÊNCIA POR TENTATIVA (sem dupla contagem):
      --   tent 1 → assim que houver 4h de silêncio real (já garantido pela
      --            transição start->wait; aqui gap 0 sobre o silêncio real)
      --   tent 2 → 3 dias após o último envio (data_ultimo_follow_up)
      --   tent 3 → 7 dias após o último envio
      AND CASE
            WHEN COALESCE(c2.follow_up_tentativas, 0) = 0 THEN
              -- 1ª tentativa: silêncio REAL do lead >= 4h. Como já está em
              -- wait_follow_up, a transição start->wait JÁ garantiu esse silêncio
              -- — então isto é TRUE assim que entra na coluna (sem 2º gap).
              -- Ancorado em data_ultima_entrada (última msg do lead), NÃO em
              -- data_wait_follow_up (quando o cron rodou). Sem entrada conhecida,
              -- confia na transição (999d atrás => dispara já).
              COALESCE(c2.data_ultima_entrada, NOW() - INTERVAL '999 days') < NOW() - INTERVAL '4 hours'
            ELSE
              COALESCE(c2.data_ultimo_follow_up, c2.data_wait_follow_up, NOW() - INTERVAL '999 days') <
                NOW() - CASE COALESCE(c2.follow_up_tentativas, 0) + 1
                          WHEN 2 THEN INTERVAL '3 days'
                          ELSE     INTERVAL '7 days'
                        END
          END
      AND (c2.follow_up_reservado_ate IS NULL OR c2.follow_up_reservado_ate < NOW())
    ORDER BY COALESCE(c2.data_ultimo_follow_up, c2.data_ultima_entrada, c2.data_wait_follow_up) ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING c.id, c.nome, c.telefone,
            CASE (c.follow_up_tentativas + 1) WHEN 1 THEN '4h' WHEN 2 THEN '3d' ELSE '7d' END;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_proximo_lead_followup_raw(uuid)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

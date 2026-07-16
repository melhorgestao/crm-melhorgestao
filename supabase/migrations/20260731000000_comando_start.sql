-- ============================================================================
-- Comando /start no executa_comando_dono.
--
-- CONTEXTO: o router n8n ATIVO (workflow grande) trata comandos "/" digitados
-- pelo dono chamando o RPC executa_comando_dono — NÃO passa pelo edge
-- router-ingest. Por isso o /start implementado no router-ingest nunca rodava
-- em produção (só /humano, /voltar, etc — que vivem aqui — funcionavam).
--
-- FIX: adiciona o case '/start' aqui. Como plpgsql não manda WhatsApp, ele
-- dispara (async, via pg_net) o edge router-ingest com um trigger direto
-- { trigger:'comando_start', contato_id, instancia_id }. O router-ingest faz
-- o reset pra 1ª interação, chama o agent-start (re-carimba data_start=NOW →
-- relógio 24h→follow-up recomeça) e envia o cardápio via Evolution.
--
-- Uso: dono abre o chat do lead que não recebeu e manda "/start".
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.executa_comando_dono(
  p_contato_id UUID,
  p_comando    TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acao TEXT;
  v_estado_para TEXT;
  v_ja_comprou BOOLEAN;
  v_estado_atual TEXT;
  v_estado_anterior TEXT;
  v_canal TEXT;
  v_instancia_id UUID;
BEGIN
  SELECT ultima_interacao, ja_comprou, estado_antes_suporte, canal_atual, instancia_id
    INTO v_estado_atual, v_ja_comprou, v_estado_anterior, v_canal, v_instancia_id
    FROM contatos WHERE id = p_contato_id;

  CASE p_comando
    WHEN '/humano' THEN
      UPDATE contatos
         SET bot_pausado_ate      = NOW() + INTERVAL '999 years',
             estado_antes_suporte = CASE
               WHEN ultima_interacao = 'suporte' THEN estado_antes_suporte
               ELSE ultima_interacao
             END,
             ultima_interacao     = 'suporte',
             data_suporte         = CASE
               WHEN ultima_interacao = 'suporte' THEN data_suporte
               ELSE NOW()
             END,
             suporte_motivo       = COALESCE(suporte_motivo, 'humano_atendendo'),
             updated_at           = NOW()
       WHERE id = p_contato_id;
      v_estado_para := 'suporte';
      v_acao := 'bot pausado + movido pra suporte (humano atendendo)';

    WHEN '/parar' THEN
      UPDATE contatos SET bot_pausado_ate = NOW() + INTERVAL '24 hours', updated_at = NOW()
        WHERE id = p_contato_id;
      v_acao := 'bot pausado por 24h';

    WHEN '/voltar' THEN
      UPDATE contatos SET bot_pausado_ate = NULL, updated_at = NOW() WHERE id = p_contato_id;
      IF v_estado_atual = 'suporte' THEN
        IF v_estado_anterior IS NOT NULL AND v_estado_anterior != 'suporte' THEN
          v_estado_para := v_estado_anterior;
        ELSIF v_ja_comprou THEN
          v_estado_para := 'cliente';
        ELSE
          v_estado_para := 'wait_follow_up';
        END IF;
        UPDATE contatos
           SET ultima_interacao    = v_estado_para,
               estado_antes_suporte = NULL,
               data_suporte         = NULL,
               suporte_motivo       = NULL,
               data_wait_follow_up = CASE WHEN v_estado_para = 'wait_follow_up' THEN NOW()
                                          ELSE data_wait_follow_up END,
               updated_at           = NOW()
         WHERE id = p_contato_id;
        v_acao := 'bot reativado + saiu de suporte → ' || v_estado_para;
      ELSE
        v_acao := 'bot reativado';
      END IF;

    WHEN '/cliente' THEN
      UPDATE contatos SET ultima_interacao = 'cliente', updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'cliente'; v_acao := 'estado forçado: cliente';

    WHEN '/sumiu' THEN
      UPDATE contatos SET ultima_interacao = 'wait_follow_up',
        data_wait_follow_up = NOW(), updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'wait_follow_up'; v_acao := 'estado forçado: wait_follow_up';

    WHEN '/banir' THEN
      UPDATE contatos SET ultima_interacao = 'NUNCA_MAIS',
        data_nunca_mais = NOW(), updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := 'NUNCA_MAIS'; v_acao := 'banido: NUNCA_MAIS';

    WHEN '/voltar_inicio' THEN
      UPDATE contatos SET ultima_interacao = NULL,
        typebot_closing_session_id = NULL, updated_at = NOW()
        WHERE id = p_contato_id;
      v_estado_para := NULL; v_acao := 'estado limpo (sessão typebot resetada)';

    WHEN '/start' THEN
      -- Dispara MANUALMENTE a apresentação/cardápio pra um lead que não recebeu
      -- (msg do lead não carregou 100%, ou chegou com o chip offline/restringido).
      -- plpgsql não manda WhatsApp: delega (async) pro edge router-ingest, que
      -- faz reset → agent-start → envio via Evolution. timeout alto porque o
      -- envio de vários blocos leva ~10s (não trava a resposta do comando).
      PERFORM net.http_post(
        url := 'https://epreaawpvxrpqqthcczu.supabase.co/functions/v1/router-ingest',
        headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMjM5MDIsImV4cCI6MjA5MjY5OTkwMn0.VEQb1fk7JRIB1KXtHZGcmLKKMWJvkpG1fINB3mdPn0E"}'::jsonb,
        body := jsonb_build_object(
          'trigger',      'comando_start',
          'contato_id',   p_contato_id,
          'instancia_id', v_instancia_id
        ),
        timeout_milliseconds := 30000
      );
      v_estado_para := 'start';
      v_acao := 'cardápio /start disparado (async via router-ingest)';

    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'comando desconhecido: ' || p_comando);
  END CASE;

  RETURN jsonb_build_object('ok', true, 'comando', p_comando, 'acao', v_acao, 'estado_para', v_estado_para);
END $$;

GRANT EXECUTE ON FUNCTION public.executa_comando_dono(UUID, TEXT)
  TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

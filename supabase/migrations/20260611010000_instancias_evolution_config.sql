-- ============================================================================
-- Adiciona colunas de configuração Evolution na tabela instancias.
-- Permite que workflows n8n disparem dinamicamente em N instâncias
-- (basta INSERT na tabela e ativar).
--
--   evolution_instance  → nome da instância no servidor Evolution (vai na URL)
--   evolution_url       → base URL da Evolution API (sem barra final)
--   evolution_apikey    → API key específica da instância
--   alerta_admin        → instância marcada como destino dos alertas de erro
--                          (apenas UMA por ambiente). Default false.
-- ============================================================================

ALTER TABLE public.instancias
  ADD COLUMN IF NOT EXISTS evolution_instance text,
  ADD COLUMN IF NOT EXISTS evolution_url      text DEFAULT 'https://evo.melhorgestao.online',
  ADD COLUMN IF NOT EXISTS evolution_apikey   text,
  ADD COLUMN IF NOT EXISTS alerta_admin       boolean NOT NULL DEFAULT false;

-- Seed: instância '1' (antigo BASE — chip recriado como "Instancia 1" no Evolution)
UPDATE public.instancias
  SET evolution_instance = COALESCE(evolution_instance, 'Instancia 1'),
      evolution_apikey   = COALESCE(evolution_apikey, 'c7ffccd59298850a7d0c108c999c37581d2128fb5e35793bc8b6f639871d71b7'),
      alerta_admin       = true
WHERE nome = '1';

-- Seed: instância '2' (ADS — chip recriado como "Instancia 2" no Evolution)
UPDATE public.instancias
  SET evolution_instance = COALESCE(evolution_instance, 'Instancia 2'),
      evolution_apikey   = COALESCE(evolution_apikey, '82800A07BAFC-4EF3-93D8-FCEF66D44AA5')
WHERE nome = '2';

-- Garante apenas 1 instância marcada como destino de alerta admin
CREATE UNIQUE INDEX IF NOT EXISTS instancias_alerta_admin_unico
  ON public.instancias ((true))
  WHERE alerta_admin = true;

NOTIFY pgrst, 'reload schema';

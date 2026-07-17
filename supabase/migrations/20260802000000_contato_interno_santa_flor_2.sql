-- ============================================================================
-- Contato INTERNO "Santa Flor 2" (2º chip).
--
-- Contato INTERNO não se cria à mão: é gerado pelo trigger
-- sync_contato_interno_instancia quando a instância tem 'numero' salvo
-- (canal_origem='INTERNO', ultima_interacao=NULL → fora do Kanban/agente,
-- e marca o chip como "nosso" pra virar fromMe). Ver
-- 20260711000000_instancias_numero_e_contato_interno.sql.
--
-- Aqui: garante o número no 2º chip (força o re-sync — o trigger cria o
-- contato se não existir) e dá o nome amigável "Santa Flor 2". O trigger
-- preserva nome existente (COALESCE), então o rename persiste.
-- ============================================================================

-- 1) Garante o número no 2º chip → dispara o trigger (cria/atualiza INTERNO).
UPDATE public.instancias
   SET numero = '45991082763'
 WHERE evolution_instance = 'Instancia 2';

-- 2) Nome amigável no contato INTERNO do 2º chip.
UPDATE public.contatos
   SET nome = 'Santa Flor 2', updated_at = NOW()
 WHERE canal_origem = 'INTERNO'
   AND telefone = '45991082763';

-- 3) Padroniza o 1º chip pra "Santa Flor 1" (só se ainda estiver "Instancia 1").
UPDATE public.contatos
   SET nome = 'Santa Flor 1', updated_at = NOW()
 WHERE canal_origem = 'INTERNO'
   AND nome = 'Instancia 1';

NOTIFY pgrst, 'reload schema';

-- Verificação (rodar à parte):
--   SELECT nome, telefone, canal_origem, ultima_interacao, instancia_id
--     FROM public.contatos WHERE canal_origem = 'INTERNO' ORDER BY nome;

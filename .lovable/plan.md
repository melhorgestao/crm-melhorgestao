

# Plano: popular `perfis_usuario` e tratar coluna `nome` como "Apelido"

## Diagnóstico

| Fonte | Estado |
|---|---|
| `auth.users` | 2 admins: `v@santaflor.com` (id `44aa68b2…`) e `a@santaflor.com` (id `61b22ba5…`) |
| `contatos` ADMIN | 2 registros: `V` e `A` |
| `perfis_usuario` | **0 registros** — trigger `handle_new_user` foi criado DEPOIS desses 2 users, então nunca disparou para eles |
| RLS de `perfis_usuario` | Sem policy de INSERT → frontend não consegue popular |

A coluna `nome` já é semanticamente o apelido (o trigger `handle_new_user` lê `raw_user_meta_data->>'apelido'` e grava em `nome`; AdminPage usa `formApelido` → `nome`). Renomear a coluna fisicamente quebraria: `useAuth.tsx`, `FinanceiroPage.tsx`, `AdminPage.tsx` (4 referências), `listar_socios()`, `criar_usuario()`, `criar_pedido_v2()`, `handle_new_user()`, e o arquivo auto-gerado `src/integrations/supabase/types.ts`. **Solução segura: manter `nome` no banco, exibir como "Apelido" no UI.**

## Mudanças (mínimas, sem quebrar fluxos)

### 1) Migration — popular os 2 admins existentes + garantir consistência futura

```sql
-- Backfill dos 2 admins já em auth.users (idempotente)
INSERT INTO public.perfis_usuario
  (user_id, nome, email, acesso_kanban, ver_menu, pode_excluir_card, tipo_usuario, socio_key)
VALUES
  ('44aa68b2-8cea-42c8-8fb0-3093926e2b35', 'V', 'v@santaflor.com',
   'todos', '["todos"]'::jsonb, true, 'admin', 'V'),
  ('61b22ba5-6df4-493f-ad6a-cd51c95bb5c4', 'A', 'a@santaflor.com',
   'todos', '["todos"]'::jsonb, true, 'admin', 'A')
ON CONFLICT (user_id) DO UPDATE SET
  tipo_usuario = 'admin', acesso_kanban = 'todos',
  ver_menu = '["todos"]'::jsonb, pode_excluir_card = true,
  socio_key = EXCLUDED.socio_key, email = EXCLUDED.email;

-- Backfill genérico: qualquer auth.user sem perfil ganha um (defensivo, não toca em quem já tem)
INSERT INTO public.perfis_usuario (user_id, nome, email, acesso_kanban, ver_menu, pode_excluir_card, tipo_usuario, socio_key)
SELECT u.id,
       COALESCE(u.raw_user_meta_data->>'apelido', split_part(u.email,'@',1)),
       u.email, 'todos', '["todos"]'::jsonb, true,
       COALESCE(u.raw_user_meta_data->>'tipo_usuario','admin'),
       COALESCE(u.raw_user_meta_data->>'socio_key', UPPER(LEFT(split_part(u.email,'@',1),1)))
FROM auth.users u
LEFT JOIN public.perfis_usuario p ON p.user_id = u.id
WHERE p.user_id IS NULL;

-- Policy de INSERT (faltando) — permite frontend autenticado criar perfil próprio,
-- mantém SECURITY DEFINER do trigger funcionando para novos signups
CREATE POLICY "Users can insert own profile"
ON public.perfis_usuario FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);
```

### 2) Frontend — apenas trocar **labels visíveis** "Nome" → "Apelido"

Arquivo: `src/pages/AdminPage.tsx` — alterar somente strings de label/header da seção Usuários:
- `<Label>Nome</Label>` → `<Label>Apelido</Label>`
- Cabeçalho de coluna `Nome` na tabela de usuários → `Apelido`
- Placeholder do input de criação → "Apelido (ex: V, A, João)"

Nenhuma chave/coluna do banco muda. Os campos do form (`formApelido`) e o `INSERT/UPDATE` continuam gravando em `nome`. `useAuth`, `FinanceiroPage`, `listar_socios` e os RPCs **não são tocados**.

## O que NÃO muda (proteção dos fluxos existentes)

- ✅ `useAuth.tsx` continua lendo `nome` (é o apelido).
- ✅ `listar_socios()` RPC e fallback de sócios em `PedidosPage` — agora retornarão V e A reais (popup de "Marcar como Pago" passa a listar sócios cadastrados).
- ✅ `handle_new_user` trigger intacto — novos signups via AdminPage continuarão criando perfil automaticamente, com `nome = apelido` informado.
- ✅ `criar_pedido_v2`, `process_venda`, `criar_usuario` RPCs intactos.
- ✅ Estoque, Kanban, Logística, Financeiro, comissões — zero alterações.

## Critérios de aceite

1. Após a migration, aba Administração → Usuários lista 2 admins (V, A) com tipo `admin`, acesso "todos", sócio V/A.
2. Popup "Marcar como Pago" (PedidosPage) lista V e A vindos do `listar_socios()` (não mais do fallback de contatos).
3. Labels do form de criação de usuário mostram "Apelido" em vez de "Nome".
4. Criar um novo usuário via UI continua funcionando normalmente (signUp → trigger → INSERT do perfil).

## Arquivos editados

- 1 nova migration (backfill + policy de INSERT)
- `src/pages/AdminPage.tsx` (apenas strings de label)


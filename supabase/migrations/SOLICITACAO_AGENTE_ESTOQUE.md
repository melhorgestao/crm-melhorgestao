# SOLICITAÇÃO PARA REPARAR ESTOQUE DO CRM SANTA FLOR

## PROBLEMA ATUAL
O sistema de estoque está retornando apenas o ÚLTIMO pedido em vez de considerar TODOS os pedidos (pagos + pendentes). O estoque deveria ser:
**Estoque = Lotes (entradas) - Todos os Pedidos (saídas)**

---

## GUIAS A SEGUIR

### 1. Dev Guide (padrão do projeto)
- **RPC via fetch** (bypass PostgREST) - não usar supabase.rpc()
- Funções no Supabase com `SECURITY DEFINER`
- snapshot para performance APÓS funcionar

### 2. Major Update V2 (histórico)
- Estoque calculado dinamicamente
- UF Postagem crucial para distribuição por estado
- Cards devem mostrar negativo quando pedidos > lotes

---

## O QUE JÁ FUNCIONA ✅

1. **UF Postagem nos Detalhes do Pedido** - Aparece corretamente no popup
2. **Coluna uf_cliente em pedidos** - Faz FK com UF do contato (via migration)
3. **Frontend** - Já configurado para chamar `get_estoque_completo()` via fetch

---

## DIAGNÓSTICO DO PROBLEMA

### O que foi tentado:

1. **Usar `pedido_itens`** - Só retornou 1-3 registros (produtos específicos)
2. **Usar coluna `produto` (JSON)** - Parsing complexo, retornou só 1 registro
3. **Usar `quantidade` da tabela pedidos** - Simplificado, mesmo assim retorna só 1
4. **Com Snapshot** - Mesmo problema, só 1 registro

### Causa raiz identificada:
A função `get_estoque_completo()` não está somando corretamente todos os pedidos. Parece haver um problema na agregação ou no JOIN entre lotes e pedidos.

---

## ARQUITETURA DO BANCO

### Tabelas envolvidas:

- **`public.pedidos`** - Pedidos do CRM
  - `id` (uuid)
  - `produto` (json/text) - produtos do pedido
  - `quantidade` (integer) - quantidade total
  - `uf_postagem` (text) - UF de postagem
  - `uf_cliente` (text) - UF do cliente (nova, faz FK com contatos.uf)
  - `status_pagamento` (text) - 'pago', 'pendente', etc
  - `contato_id` (uuid) - FK para contatos

- **`public.pedido_itens`** - Itens dos pedidos (pode estar vazio)
  - `pedido_id` (uuid)
  - `produto_id` (uuid)
  - `quantidade` (integer)

- **`public.lotes`** - Lotes de estoque
  - `produto_id` (uuid)
  - `uf` (text)
  - `quantidade_atual` (integer)

- **`public.produtos`** - Produtos ativos
  - `id` (uuid)
  - `nome_oficial` (text)
  - `ativo` (boolean)

- **`public.contatos`** - Contatos
  - `id` (uuid)
  - `uf` (text) - UF do cliente

---

## COLUNAS DO FRONTEND

O frontend espera estas colunas da função `get_estoque_completo()`:
```typescript
{
  prod_id: uuid,
  prod_nome: string,
  estado: string,      // UF (SP, RS, etc)
  entrada: number,     // quantidade dos lotes
  saida: number,       // quantidade dos pedidos
  saldo: number        // entrada - saida (pode ser negativo)
}
```

---

## O QUE FAZER

### Passo 1: Executar SQL de correção do uf_cliente
```sql
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS uf_cliente text;

UPDATE public.pedidos p
SET uf_cliente = c.uf
FROM public.contatos c
WHERE p.contato_id = c.id AND c.uf IS NOT NULL;

UPDATE public.pedidos p
SET uf_cliente = p.uf_postagem
WHERE p.uf_cliente IS NULL AND p.uf_postagem IS NOT NULL;
```

### Passo 2: Criar função CORRIGIDA para get_estoque_completo()

A função deve:
1. **Somar TODOS os lotes** por produto+UF
2. **Somar TODOS os pedidos** por produto+UF (usar uf_postagem OU uf_cliente)
3. **Calcular saldo = entrada - saida**
4. **Considerar pedidos com qualquer status_pagamento** (pago E pendente)
5. **Usar COALESCE** para evitar nulos

### Passo 3: Testar no Supabase SQL Editor
```sql
-- Ver quantos pedidos existem no total
SELECT COUNT(*) FROM pedidos WHERE status_pagamento IS NOT NULL;

-- Ver示例 de soma de pedidos
SELECT uf_postagem, SUM(quantidade) as total FROM pedidos 
WHERE status_pagamento IS NOT NULL 
GROUP BY uf_postagem;

-- Testar função
SELECT * FROM get_estoque_completo();
```

### Passo 4: Adicionar SNAPSHOT após funcionar

Depois que a função retornar TODOS os pedidos corretamente:
1. Criar tabela `estoque_snapshot`
2. Criar função `atualizar_estoque_snapshot()`
3. Frontend continua igual (já configurado)

---

## RESULTADO ESPERADO

- Cards de estoque mostrando **estoque negativo** quando há mais pedidos que lotes
- Divisão por estado (SP, RS, etc) funcionando
- Lista de movimentações mostrando entradas e saídas
- Snapshot para performance (depois que funcionar)

---

## REFERÊNCIAS

- Frontend em: `src/pages/EstoquePage.tsx`
- Fetch já configurado para chamar `get_estoque_completo()` via RPC
- Padrão: RPC via fetch (bypass PostgREST)
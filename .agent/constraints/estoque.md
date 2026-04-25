# Constraints: Estoque

> Regras e limitações para gestão de estoque, Movements e controle de inventário.

---

## estoque constraints

### est0001: peso_produto

**Descrição:** Produto deve ter peso cadastrado. Se não tiver, usa default.

**Regra:**
```
SE produto.peso NULO OU 0 → usar 300g (default)
```

**Tabela:** `produtos.peso` (em gramas)

---

### est0002: desconto_automatico

**Descrição:** Estoque é descontado automaticamente quando pedido tem UF definida.

**Regra:**
```
SE pedido.uf_postagem NÃO NULO → descontar do estoque daquela UF
SE pedido.uf_postagem NULO → NÃO descontar (ficar na fila logística)
```

**Timing:** Desconta no momento da criação do pedido.

---

### est0003: status_pagamento_desconta

**Descrição:** Pedidos pagos E pendentes descontam do estoque.

**Regra:**
```
status_pagamento = 'pago'    → desconta ✓
status_pagamento = 'pendente' → desconta ✓
status_pagamento = NULL       → NÃO desconta
```

**Importante:**both paid and pending orders count against inventory because the product is already sent to the client before payment is received.

---

### est0004: permite_negativo

**Descrição:** Estoque pode ficar negativo.

**Regra:**
```
SALDO < 0 → PERMITIDO (não trava venda)
```

**Motivação:** Sinaliza necessidade de reposição.

---

### est0005: estoque_por_uf

**Descrição:** Estoque é controlado por UF de postagem.

**Cálculo:**
```sql
ESTOQUE[produto_id, uf] = SUM(lotes.quantidade_atual) - SUM(pedido_itens.quantidade)
WHERE pedido.uf_postagem = uf
```

---

### est0006: entrada_estoque

**Descrição:** Entrada de estoque via lotes.

**Tabela:** `lotes`

**Campos:**
- produto_id
- lote_codigo
- quantidade_inicial
- quantidade_atual
- uf (estado de produção)
- data_producao

---

### est0007: movimentacao_log

**Descrição:** Toda alteração de estoque é logada.

**Tabela:** `estoque_movimentacoes`

**Tipos:**
- `entrada` - entrada de estoque
- `saida` - venda/desconto

**Campos:**
- produto_id
- lote_id (opcional)
- pedido_id (opcional)
- tipo (entrada/saida)
- quantidade
- uf_origem
- Created_by
- observacao

---

### est0008: migra UF Trocada

**Descrição:** Ao trocar UF de postagem, ajustar estoques.

**Regra:**
```
AO TROCAR uf_postagem:
1. Criar movimentacao tipo='entrada' na UF nova (+qtd)
2. Criar movimentacao tipo='saida' na UF antiga (-qtd)
3. Atualizar pedido.uf_postagem
4. Criar log_atividades
```

---

### est0009: calcular_peso_total

**Descrição:** Peso total = soma de (peso × quantidade) de cada item.

**Fórmula:**
```
peso_total = Σ(produto.peso × item.quantidade)
```

---

### est0010: faixa_peso_logistica

**Descrição:** Peso em gramas convertido para faixa em KG.

**Conversão (automática na Edge Function):**
```
≤ 300g   → 0.3kg
≤ 500g   → 0.5kg
≤ 1kg    → 1kg
≤ 2kg    → 2kg
≤ 5kg    → 5kg
≤ 10kg   → 10kg
≤ 15kg   → 15kg
≤ 20kg   → 20kg
> 20kg   → 30kg
```

---

### est0011: controle_por_regiao

**Descrição:** Estoque pode ser controlado por região dentro da UF.

**Tabela:** `uf_regioes`

**Campos:**
- uf
- tag (nome: "Zona Sul", "Alvorada")
- codigo (úERRO NICO: "SP1", "SP2")
- sequencial

---

### est0012: lotes_por_representante

**Descrição:** Lotes podem ser atribuídos a representative específico.

**Regra:**
```
lotes.representante_id = NULL → Estoque Geral (Admin)
lotes.representante_id = UUID → Estoque do Representante
```

**Trigger:**
```
Admin seeing: Todos os lotes (representante_id IS NULL OR = meu_id)
Rep: Apenas lotes WHERE representante_id = meu_id
```

---

## Tabela de Constraints

| ID | Nome | Tipo | Severidade |
|----|------|------|-----------|
| est0001 | peso_produto | DEFAULT | AUTO |
| est0002 | desconto_automatico | TRIGGER | AUTO |
| est0003 | status_pagamento_desconta | QUERY | BLOCK |
| est0004 | permite_negativo | PERMISSIVE | OK |
| est0005 | estoque_por_uf | QUERY | - |
| est0006 | entrada_estoque | INSERT | - |
| est0007 | movimentacao_log | INSERT | - |
| est0008 | migra_uf_trocada | UPDATE | AUTO |
| est0009 | calcular_peso_total | CALC | - |
| est0010 | faixa_peso_logistica | CONVERT | AUTO |
| est0011 | controle_por_regiao | QUERY | - |
| est0012 | lotes_por_representante | QUERY | - |

---

## Source of Truth (V19)

```
ESTOQUE = SUM(lotes.quantidade_atual) - SUM(pedido_itens.quantidade)
WHERE pedidos.status_pagamento IN ('pago', 'pendente')
GROUP BY produto_id, uf_postagem
```

---

## Related Files

- Workflow: `.agent/workflows/gerar_etiquetas.md`
- Constraints: `.agent/constraints/frete.md`, `.agent/constraints/etiqueta.md`
- Edge Functions: `supabase/functions/cotar-frete/`, `supabase/functions/gerar-etiqueta/`
- Database: `supabase/migrations/20260415000015_estoque_todos_pedidos_inclusive_pendentes.sql`
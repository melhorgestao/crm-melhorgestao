# Schema: Pedido

> Estrutura de dados completa para criação de pedidos.

---

## Campos da Tabela `pedidos`

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| id | uuid | ✅ | PK - UUID gerado automaticamente |
| contato_id | uuid | ✅ | FK para tabela contatos |
| produto | jsonb/text | ✅ | Produto(s) - texto ou JSON array |
| quantidade | integer | ✅ | Quantidade total de itens |
| valor | numeric | ✅ | Valor total do pedido |
| canal | text | ✅ | Canal de origem: ADS, BASE, REP |
| status_pagamento | text | ✅ | Status pagamento: pago, pendente |
| modalidade | text | ✅ | Modalidade envio: mini, pac, sedex |
| uf_postagem | text | ✅ | UF de postagem (2 letras) - pode ser diferente do cliente |
| status_pedido | text | ✅ | Status pedido: aguardando_rastreio, postado, entregue |
| created_at | timestamptz | ✅ | Data de criação (auto) |
| criado_por | text | ✅ | Apelido do sócio que criou (ver, a, etc) |
| order_number | integer | ✅ | Número sequencial do pedido |
| data | date | ✅ | Data do pedido (UTC-3/SP) |
| etiqueta_codigo | text | ❌ | Código de rastreio |
| etiqueta_url | text | ❌ | URL da etiqueta PDF |
| etiqueta_valor | numeric | ❌ | Valor do frete cotado |
| etiqueta_paga | boolean | ❌ | Se etiqueta foi paga |
| entrega_em_maos | boolean | ❌ | Entrega em mãos |
| observacao | text | ❌ | Observações do pedido |
| locked_at | timestamptz | ❌ | locked timestamp |

---

## Schema p_produtos (JSON)

```json
[
  {
    "produto": "CBD 500mg",
    "produto_id": "uuid-do-produto",
    "quantidade": 1,
    "preco": 150.00
  }
]
```

---

## Schema p_contato_id

- UUID do contato existente na tabela `contatos`
- Obrigatório para criar pedido

---

## Valores Válidos

| Campo | Valores |
|-------|----------|
| canal | ADS, BASE, REP |
| status_pagamento | pago, pendente |
| modalidade | mini, pac, sedex |
| uf_postagem | SP, RJ, MG, ... (2 letras) - pode diferente do cliente |
| status_pedido | aguardando_rastreio, postado, entregue |
| criado_por | ver, a (apelidos dos sócios) |

---

## Relacionamentos

```
pedidos (n:1) contatos
pedidos (1:n) pedido_itens
pedidos (1:n) lancamentos_socios
pedidos (1:n) estoque_movimentacoes
```

---

## RPC: criar_pedido_v2

**Parâmetros de entrada:**
```typescript
{
  p_contato_id: uuid,        // UUID do contato
  p_canal: text,             // ADS, BASE, REP
  p_valor: numeric,          // Valor total
  p_status_pagamento: text,  // pago, pendente
  p_modalidade: text,        // mini, pac, sedex
  p_uf_postagem: text,       // UF para postagem (pode diferente do cliente)
  p_criado_por: text,        // Apelido do socio (ver, a)
  p_obs: text,               // Observacoes
  p_produtos: jsonb          // Array de produtos
}
```

**Regras importantes:**
- **criado_por**: Sempre deve ser o apelido do socio que criou o pedido (ver = socio V, a = socio A)
- **uf_postagem**: Pode ser diferente da UF do cliente (escolhida no momento da venda)

**Retorno:**
```json
{
  "pedido_id": "uuid",
  "status": "criado",
  "order_number": 123
}
```
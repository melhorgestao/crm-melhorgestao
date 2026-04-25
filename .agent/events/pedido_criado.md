# Event: pedido_criado

> Disparado quando um novo pedido é criado com sucesso.

---

## Quando Ocorre

- RPC `criar_pedido_v2` executa com sucesso
- Novo registro inserido em `pedidos`

---

## Dados do Evento

```json
{
  "event": "pedido_criado",
  "pedido_id": "uuid",
  "contato_id": "uuid",
  "valor": 150.00,
  "canal": "ADS",
  "status_pagamento": "pago",
  "modalidade": "mini",
  "uf_postagem": "SP",
  "criado_por": "ver",
  "order_number": 123,
  "timestamp": "2024-01-01T10:00:00Z"
}
```

**Nota:** `criado_por` é sempre o **apelido do socio** que criou o pedido (ver, a), não o email.

---

## Ações Triggeradas

1. **Estoque** - Abater itens do estoque
2. **Lançamento Sócio** - Criar lançamento financeiro (socio = ver ou a)
3. **Log** - Criar registro em log_atividades

---

## Relacionamentos

```
pedido_criado → pedido_itenscriado
pedido_criado → lancamento_criado
```
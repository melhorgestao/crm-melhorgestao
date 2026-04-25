# Skill: pagar-etiqueta

> Interface para pagar/emitir etiqueta definitiva via SuperFrete API.

## Quando Usar

- Ao clicar em "PAGAR" ou "PAGAR TODAS"
- Após gerar etiqueta com sucesso
- Para confirmar emissão e gerar código definitivo

---

## Input

```json
{
  "order_id": "AB123456789BR",
  "api_key": "sf_live_..."
}
```

### Parâmetros

| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|------------|-----------|
| order_id | string | ✅ | Código da etiqueta (de gerar-etiqueta) |
| api_key | string | ✅ | API key SuperFrete |

---

## Output

```json
{
  "success": true,
  "status": "paid",
  "tracking": "AB123456789BR",
  "data": {
    "id": "SFT-123456",
    "status": "paid",
    "tracking": "AB123456789BR"
  }
}
```

### Response

| Campo | Tipo | Descrição |
|-------|------|-----------|
| success | boolean | Sucesso da operação |
| status | string | Status ("paid") |
| tracking | string | Código de rastreio definitivo |
| data | object | Dados completos da resposta |

---

## Errors

| Erro | HTTP | Descrição |
|------|-----|-----------|
| API key não configurada | 400 | `api_key` vazia |
| ID da etiqueta não fornecido | 400 | `order_id` vazio |
| Saldo insuficiente | 4xx | Saldo insuficiente no SuperFrete |
|Etiqueta não encontrada | 404 | Código inválido |
| SuperFrete error | 4xx/5xx | Erro da API externa |

---

## Detecção de Saldo Insuficiente

```typescript
const errorMsg = error.message || '';

if (errorMsg.toLowerCase().includes('saldo') || 
    errorMsg.toLowerCase().includes('insufficient')) {
  // ERRO: Saldo insuficiente
}
```

---

## Pagamento em Lote

Para pagar várias etiquetas:

```typescript
const eligible = pedidos.filter(p => 
  p.etiqueta_codigo && !p.etiqueta_paga
);

for (const p of eligible) {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/pagar-etiqueta`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      order_id: p.etiqueta_codigo,
      api_key: config.valor,
    }),
  });
  
  if (res.ok) {
    await supabase.from('pedidos').update({
      etiqueta_paga: true
    }).eq('id', p.id);
  }
}
```

---

## Chamada no Frontend

```typescript
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const codigo = pedido.etiqueta_codigo;

const res = await fetch(`${SUPABASE_URL}/functions/v1/pagar-etiqueta`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    order_id: codigo,
    api_key: config.valor,
  }),
});

if (!res.ok) {
  const error = await res.json();
  if (error.error?.toLowerCase().includes('saldo')) {
    throw new Error('Saldo insuficiente no Super Frete!');
  }
  throw new Error(error.error);
}

const result = await res.json();

// Atualizar banco
await supabase.from('pedidos').update({
  etiqueta_paga: true,
  etiqueta_codigo: result.tracking || codigo,
}).eq('id', pedido.id);
```

---

## Constraints Verificadas

- `etiqueta.ja_paga` - Verificar se não está paga
- `frete.api_key_obrigatoria` - API key configurada
- `etiqueta.etiqueta_obrigatoria` - Código existe
- `etiqueta.erro_saldo` - Detectar saldo insuficiente
- `etiqueta.pagamento_sucesso` - Verificar response.success

---

## Arquivo Relacionado

- Edge Function: `supabase/functions/pagar-etiqueta/index.ts`
- Workflow: `.agent/workflows/gerar_etiquetas.md`
- Constraint: `.agent/constraints/etiqueta.md`, `.agent/constraints/frete.md`
- Skills: `.agent/skills/gerar-etiqueta/SKILL.md`, `.agent/skills/cotar-frete/SKILL.md`
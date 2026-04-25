# Skill: cotar-frete

> Interface para cotar preço de envio via SuperFrete API.

## Quando Usar

- Antes de gerar etiqueta (cotarFrete no LogisticaPage)
- Para exibir valor do frete no card do pedido
- Para calcular custo de envio antes da venda

---

## Input

```json
{
  "from_cep": "01000000",
  "to_cep": "20000000",
  "peso": 300,
  "width": 11,
  "height": 2,
  "length": 16,
  "quantity": 1,
  "service": 1,
  "api_key": "sf_live_..."
}
```

###Parâmetros

| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|------------|-----------|
| from_cep | string | ✅ | CEP de origem (8 dígitos) |
| to_cep | string | ✅ | CEP de destino (8 dígitos) |
| peso | number | ✅ | Peso em gramas |
| width | number | ❌ | Largura cm (default: 11) |
| height | number | ❌ | Altura cm (default: 2) |
| length | number | ❌ | Comprimento cm (default: 16) |
| quantity | number | ❌ | Quantidade volumes (default: 1) |
| service | number | ❌ | Código serviço (default: 1 = SEDEX) |
| api_key | string | ✅ | API key SuperFrete |

---

## Output

```json
{
  "price": 15.90,
  "discount": 0,
  "original_price": 15.90,
  "source": "superfrete"
}
```

### Response

| Campo | Tipo | Descrição |
|-------|------|-----------|
| price | number | Preço final com desconto |
| discount | number | Desconto aplicado |
| original_price | number | Preço sem desconto |
| source | string | Fonte ("superfrete") |

---

## Errors

| Erro | HTTP | Descrição |
|------|-----|-----------|
| API key não configurada | 400 | `api_key` vazia ou nula |
| CEP inválido | 400 | CEP com menos de 8 dígitos |
| Nenhum preço retornado | 500 | API SuperFrete não retornou preço |
| SuperFrete API error | 4xx/5xx | Erro da API externa |

---

## Cálculo de Peso

A Edge Function converte automaticamente:

```
gramas → kg → faixa
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

## Códigos de Serviço

| Código | Serviço | Descrição |
|--------|---------|-----------|
| 1 | SEDEX | Entrega rápida (default) |
| 3 | PAC | Entrega econômica |
| 33162 | Mini | Envio pequeno |

---

## Chamada no Frontend

```typescript
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;

const res = await fetch(`${SUPABASE_URL}/functions/v1/cotar-frete`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    from_cep: remetente.cep_origem,
    to_cep: contato.cep,
    peso: pesoTotal,
    service,
    api_key: config.valor,
  }),
});

if (!res.ok) {
  const error = await res.json();
  throw new Error(error.error);
}

const data = await res.json();
return data.price; // valor do frete
```

---

## Constraints Verificadas

- `frete.uf_obrigatoria` - UF deve estar definida
- `frete.remetente_obrigatorio` - Remetente existe na UF
- `frete.api_key_obrigatoria` - API key configurada
- `frete.cep_origem_valido` - CEP origem 8 dígitos
- `frete.cep_destino_valido` - CEP destino 8 dígitos
- `frete.peso_maximo` - Não excede 30kg
- `frete.faixa_peso` - Conversion automática
- `frete.service_valido` - Código válido

---

## Arquivo Relacionado

- Edge Function: `supabase/functions/cotar-frete/index.ts`
- Workflow: `.agent/workflows/gerar_etiquetas.md`
- Constraint: `.agent/constraints/frete.md`
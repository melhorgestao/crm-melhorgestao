# Skill: gerar-etiqueta

> Interface para gerar etiqueta de envio via SuperFrete API.

## Quando Usar

- Ao clicar em "GERAR ETIQUETA" ou "GERAR TODAS"
- Após cotarfrete confirmar valor
- Para obter código de rastreio

---

## Input

```json
{
  "from_name": "Santa Flor",
  "from_document": "12345678900",
  "from_address": "Rua das Flores",
  "from_number": "100",
  "from_complement": "Loja 1",
  "from_district": "Centro",
  "from_city": "São Paulo",
  "from_state": "SP",
  "from_cep": "01000000",
  "from_phone": "11999999999",
  "to_name": "Cliente Nome",
  "to_document": "98765432100",
  "to_address": "Rua das Acácias",
  "to_district": "Botafogo",
  "to_city": "Rio de Janeiro",
  "to_state": "RJ",
  "to_cep": "20000000",
  "to_phone": "21988888888",
  "peso": 300,
  "width": 11,
  "height": 2,
  "length": 16,
  "service": 1,
  "api_key": "sf_live_...",
  "valor_frete_cotado": 15.90
}
```

### Parâmetros do Remetente (from_)

| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|------------|-----------|
| from_name | string | ✅ | Nome do remetente |
| from_document | string | ❌ | CPF/CNPJ |
| from_address | string | ✅ | Endereço |
| from_number | string | ❌ | Número |
| from_complement | string | ❌ | Complemento |
| from_district | string | ✅ | Bairro |
| from_city | string | ✅ | Cidade |
| from_state | string | ✅ | UF (2 letras) |
| from_cep | string | ✅ | CEP (8 dígitos) |
| from_phone | string | ❌ | Telefone |

### Parâmetros do Destinatário (to_)

| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|------------|-----------|
| to_name | string | ✅ | Nome do destinatário |
| to_document | string | ❌ | CPF/CNPJ |
| to_address | string | ✅ | Endereço |
| to_district | string | ✅ | Bairro |
| to_city | string | ✅ | Cidade |
| to_state | string | ✅ | UF (2 letras) |
| to_cep | string | ✅ | CEP (8 dígitos) |
| to_phone | string | ❌ | Telefone |

### Parâmetros do Volume

| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|------------|-----------|
| peso | number | ✅ | Peso em gramas |
| width | number | ❌ | Largura cm (default: 11) |
| height | number | ❌ | Altura cm (default: 2) |
| length | number | ❌ | Comprimento cm (default: 16) |
| service | number | ❌ | Código serviço (default: 1) |
| api_key | string | ✅ | API key SuperFrete |

---

## Output

```json
{
  "label_url": "https://www.superfrete.com/etiqueta/...",
  "tracking": "AB123456789BR",
  "order_id": "SFT-123456",
  "tracking_url": "https://rastreio.correios.com.br/..."
}
```

### Response

| Campo | Tipo | Descrição |
|-------|------|-----------|
| label_url | string | URL do PDF da etiqueta |
| tracking | string | Código de rastreio |
| order_id | string | ID do pedido no SuperFrete |
| tracking_url | string | URL de rastreio |

---

## Errors

| Erro | HTTP | Descrição |
|------|-----|-----------|
| API key não configurada | 400 | `api_key` vazia |
| Dados obrigatórios faltando | 400 | Campos obrigatórios nulos |
| CEP inválido | 400 | CEP com menos de 8 dígitos |
| SuperFrete error | 4xx/5xx | Erro da API externa |

---

## Conversão de Peso

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

## Opções de Entrega

```json
{
  "receipt": false,   // Recibo de entrega
  "own_hand": false  // Entrega em mãos
}
```

---

## Chamada no Frontend

```typescript
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;

const res = await fetch(`${SUPABASE_URL}/functions/v1/gerar-etiqueta`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    from_name: rem.nome_remetente,
    from_address: rem.endereco,
    from_city: rem.cidade.split('/')[0],
    from_state: pedido.uf_postagem,
    from_cep: rem.cep_origem,
    to_name: contato.nome,
    to_address: contato.endereco,
    to_city: contato.cidade_uf.replace(/\/\w+$/, ''),
    to_state: contato.cidade_uf.slice(-2),
    to_cep: contato.cep,
    peso: pesoTotal,
    service: getModalidadeService(modalidade),
    api_key: config.valor,
  }),
});

if (!res.ok) {
  const error = await res.json();
  throw new Error(error.error);
}

const result = await res.json();

// Salvar no banco
await supabase.from('pedidos').update({
  etiqueta_url: result.label,
  etiqueta_codigo: result.tracking,
  etiqueta_valor: valorFrete,
}).eq('id', pedido.id);
```

---

## Constraints Verificadas

- `frete.uf_obrigatoria` - UF definida no pedido
- `frete.remetente_obrigatorio` - Remetente existe na UF
- `frete.api_key_obrigatoria` - API key configurada
- `etiqueta.dados_destinatario` - Dados do cliente completos
- `etiqueta.etiqueta_obrigatoria` - URL e código retornados

---

## Arquivo Relacionado

- Edge Function: `supabase/functions/gerar-etiqueta/index.ts`
- Workflow: `.agent/workflows/gerar_etiquetas.md`
- Constraint: `.agent/constraints/etiqueta.md`, `.agent/constraints/frete.md`
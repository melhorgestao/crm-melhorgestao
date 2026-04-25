# Schema: Frete

> Estrutura de dados para cotação e cálculo de frete.

---

## Campos

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| from_cep | text | ✅ | CEP origem (8 dígitos) |
| to_cep | text | ✅ | CEP destino (8 dígitos) |
| peso | integer | ✅ | Peso em gramas |
| width | integer | ❌ | Largura cm (default: 11) |
| height | integer | ❌ | Altura cm (default: 2) |
| length | integer | ❌ | Comprimento cm (default: 16) |
| quantity | integer | ❌ | Quantidade volumes (default: 1) |
| service | integer | ✅ | Código serviço (1, 3, 33162) |
| api_key | text | ✅ | API key SuperFrete |

---

## Faixas de Peso

| Peso (g) | Peso (kg) | Faixa SuperFrete |
|----------|----------|-----------------|
| até 300 | ≤ 0.3 | 0.3 |
| até 500 | ≤ 0.5 | 0.5 |
| até 1000 | ≤ 1 | 1 |
| até 2000 | ≤ 2 | 2 |
| até 5000 | ≤ 5 | 5 |
| até 10000 | ≤ 10 | 10 |
| até 15000 | ≤ 15 | 15 |
| até 20000 | ≤ 20 | 20 |
| acima | > 20 | 30 |

---

## Códigos de Serviço

| Código | Serviço | Descrição |
|--------|---------|-----------|
| 1 | SEDEX | Entrega rápida |
| 3 | PAC | Entrega econômica |
| 33162 | Mini | Envio pequeno |

---

## Retorno API

```json
{
  "price": 15.90,
  "discount": 0,
  "original_price": 15.90,
  "source": "superfrete"
}
```

---

## Edge Function: cotar-frete

**Endpoint:** `POST /functions/v1/cotar-frete`

**Input:**
```json
{
  "from_cep": "01000000",
  "to_cep": "20000000",
  "peso": 300,
  "service": 1,
  "api_key": "sf_live_..."
}
```

**Output:**
```json
{
  "price": 15.90,
  "discount": 0,
  "original_price": 15.90
}
```
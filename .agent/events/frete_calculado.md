# Event:frete_calculado

> Disparado quando o frete é calculado via SuperFrete API.

---

## Quando Ocorre

- Edge Function `cotar-frete` executa com sucesso

---

## Dados do Evento

```json
{
  "event": "frete_calculado",
  "from_cep": "01000000",
  "to_cep": "20000000",
  "peso": 300,
  "service": 1,
  "price": 15.90,
  "discount": 0,
  "original_price": 15.90,
  "source": "superfrete",
  "timestamp": "2024-01-01T10:00:00Z"
}
```

---

## Erros Possíveis

| Erro | Descrição |
|-----|-----------|
| Nenhum preço retornado | API SuperFrete não retornou valor |
| CEP inválido | CEP com menos de 8 dígitos |
# Event: etiqueta_gerada

> Disparado quando uma etiqueta é gerada na SuperFrete.

---

## Quando Ocorre

- Edge Function `gerar-etiqueta` executa com sucesso

---

## Dados do Evento

```json
{
  "event": "etiqueta_gerada",
  "pedido_id": "uuid",
  "etiqueta_codigo": "AB123456789BR",
  "etiqueta_url": "https://...",
  "from_cep": "01000000",
  "to_cep": "20000000",
  "service": 1,
  "timestamp": "2024-01-01T10:00:00Z"
}
```

---

## Próximos Evento

- `etiqueta_paga` - Quando usuário confirma pagamento
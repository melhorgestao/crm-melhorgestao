# Schema: Etiqueta

> Estrutura de dados para geração e pagamento de etiqueta.

---

## Campos

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| from_name | text | ✅ | Nome do remetente |
| from_document | text | ❌ | CPF/CNPJ |
| from_address | text | ✅ | Endereço |
| from_number | text | ❌ | Número |
| from_complement | text | ❌ | Complemento |
| from_district | text | ✅ | Bairro |
| from_city | text | ✅ | Cidade |
| from_state | text | ✅ | UF (2 letras) |
| from_cep | text | ✅ | CEP (8 dígitos) |
| from_phone | text | ❌ | Telefone |
| to_name | text | ✅ | Nome destinatário |
| to_document | text | ❌ | CPF/CNPJ |
| to_address | text | ✅ | Endereço |
| to_district | text | ✅ | Bairro |
| to_city | text | ✅ | Cidade |
| to_state | text | ✅ | UF (2 letras) |
| to_cep | text | ✅ | CEP (8 dígitos) |
| to_phone | text | ❌ | Telefone |
| peso | integer | ✅ | Peso em gramas |
| width | integer | ❌ | Largura (default: 11) |
| height | integer | ❌ | Altura (default: 2) |
| length | integer | ❌ | Comprimento (default: 16) |
| service | integer | ✅ | Código serviço |
| api_key | text | ✅ | API key SuperFrete |

---

## Dimensões Default

```
width:  11cm
height: 2cm
length: 16cm
```

---

## Opções de Entrega

```json
{
  "receipt": false,
  "own_hand": false
}
```

---

## Retorno API gerar-etiqueta

```json
{
  "label_url": "https://...",
  "tracking": "AB123456789BR",
  "order_id": "SFT-123456"
}
```

---

## Retorno API pagar-etiqueta

```json
{
  "success": true,
  "status": "paid",
  "tracking": "AB123456789BR"
}
```

---

## Edge Functions

### gerar-etiqueta
**Endpoint:** `POST /functions/v1/gerar-etiqueta`

### pagar-etiqueta  
**Endpoint:** `POST /functions/v1/pagar-etiqueta`

---

## Fluxo

```
1. Gerar Etiqueta → etiqueta_url, etiqueta_codigo
2. Pagar Etiqueta → etiqueta_paga = true
3. Automação Sync → status_pedido = postado/entregue
```

---

## Observações Importantes

- **from_state** = uf_postagem do pedido (pode ser diferente da UF do cliente)
- **to_state** = UF do cliente (extraída de contatos.cidade_uf)
- Cancelamento funciona mesmo após pago (motivo: "Desistência da compra")
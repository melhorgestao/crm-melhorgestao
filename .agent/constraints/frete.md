# Constraints: Frete

> Regras e limitações para operações de frete (cotação, geração, pagamento).

---

## Freight Constraints

### fret0001: uf_obrigatoria

**Descrição:** UF de postagem é obrigatória para cotarfrete ou gerar etiqueta.

**Regra:**
```
SE uf_postagem NULO OU VAZIO → ERRO "UF de postagem não definida"
```

**Consequência:** Bloqueia operações de frete.

---

### fret0002: remetente_obrigatorio

**Descrição:** Remetente deve estar configurado na UF de postagem.

**Regra:**
```
SE remetentes_uf[uf_postagem] NÃO EXISTE → ERRO "Remetente não configurado para esta UF"
```

**Verificação:**
```sql
SELECT * FROM remetentes_uf WHERE uf = :uf_postagem;
```

**Campos obrigatórios:**
- cep_origem
- nome_remetente
- cidade (formato: "Cidade/UF")

---

### fret0003: api_key_obrigatoria

**Descrição:** API key do SuperFrete deve estar configurada.

**Regra:**
```
SE configuracoes.chave_api_superfrete VAZIO OU NULO → ERRO "Configure a chave API do Super Frete na aba Integrações"
```

---

### fret0004: cep_origem_valido

**Descrição:** CEP de origem deve ter 8 dígitos.

**Regra:**
```
SE LENGTH(cep_origem) < 8 → ERRO "CEP de origem inválido"
```

---

### fret0005: cep_destino_valido

**Descrição:** CEP de destino (cliente) deve ter 8 dígitos.

**Regra:**
```
SE contato.cep NULO OU LENGTH < 8 → ERRO "CEP do destinatário não encontrado"
```

---

### fret0006: peso_maximo

**Descrição:** Peso total não pode exceder limite da transportadora.

**Regra:**
```
SE peso_total > 30000g (30kg) → ERRO "Peso excede limite máximo de 30kg"
```

**Default:** 300g se produto não tiver peso cadastrado.

---

### fret0007: faixa_peso

**Descrição:** Peso deve ser convertido para faixa válida do SuperFrete.

**Regra (conversão automática):**
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

### fret0008: service_valido

**Descrição:** Modalidade de envio deve ter código válido.

**Regra:**
```
modalidade = "mini"    → service = 33162
modalidade = "pac"     → service = 3
modalidade = "sedex"    → service = 1
modalidade = NULL/Vazio → service = 1 (padrão SEDEX)
```

---

### fret0009: dimensoes_validas

**Descrição:** Dimensões da caixa devem estar dentro dos límites.

**Valores default (hardcoded):**
```
width:  11cm
height: 2cm
length: 16cm
```

---

### fret0010: valor_frete_cotado

**Descrição:** Frete deve ser cotado antes de gerar etiqueta.

**Regra:**
```
SE valorFrete NULO OU <= 0 → ERRO "Nenhum preço retornado pela transportadora"
```

---

### fret0011: saldo_superfrete

**Descrição:** Verificar saldo disponível antes de pagar.

**Regra:**
```
SE resposta.superfrete INCLUDES "saldo" OU "insufficient" → ERRO "Saldo insuficiente no Super Frete!"
```

---

### fret0012: modalida_cannot_change_after_gerar

**Descrição:** APÓS gerar etiqueta, NÃO é possível alterar modalidade.

**Regra:**
```
SE etiqueta_codigo EXISTE → BLOQUEAR mudança de modalidade
SE etiqueta_paga = false → Permite Cancelar (deletar) e Gerar Novamente?
→ Recomendado: Toast "Etiqueta já gerada. Deseja cancelar e gerar nova?"
```

---

### fret0013: exibir_valor_frete_no_card

**Descrição:** Após gerar, exibir valor do frete no card do pedido.

**Regra:**
```
APÓS gerar etiqueta:
→ EXIBIR etiqueta_valor no card
→ Botões mudam para "Cancelar" + "Pagar"
```

**Campos exibidos:**
- Valor do frete (R$)
- Modalidade gerada
- Código de rastreio

---

## Tabela de Constraints

| ID | Nome | Tipo | Severidade |
|----|------|------|-----------|
| fret0001 | uf_obrigatoria | PRE-CHECK | BLOCK |
| fret0002 | remetente_obrigatorio | PRE-CHECK | BLOCK |
| fret0003 | api_key_obrigatoria | PRE-CHECK | BLOCK |
| fret0004 | cep_origem_valido | PRE-CHECK | BLOCK |
| fret0005 | cep_destino_valido | PRE-CHECK | BLOCK |
| fret0006 | peso_maximo | PRE-CHECK | BLOCK |
| fret0007 | faixa_peso | CONVERSAO | AUTO |
| fret0008 | service_valido | CONVERSAO | AUTO |
| fret0009 | dimensoes_validas | CONVERSAO | AUTO |
| fret0010 | valor_frete_cotado | PRE-CHECK | BLOCK |
| fret0011 | saldo_superfrete | RUNTIME | BLOCK |
| fret0012 | modalida_cannot_change_after_gerar | UI_LOCK | WARN |
| fret0013 | exibir_valor_frete_no_card | UI_DISPLAY | INFO |

---

## Related Files

- Workflow: `.agent/workflows/gerar_etiquetas.md`
- Sync: Use useTrackingAutomation.ts (frontend) + superfrete-sync (Edge Function)
- Constraints: `.agent/constraints/etiqueta.md`
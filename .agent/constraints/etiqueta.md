# Constraints: Etiqueta

> Regras e limitações para geração e pagamento de etiquetas de envio.

---

## Etiqueta Constraints

### etq0001: dados_destinatario

**Descrição:** Dados do cliente destinatário são obrigatórios.

**Regra:**
```
SE contato.nome NULO → ERRO "Nome do destinatário não encontrado"
SE contato.cep NULO → ERRO "CEP do destinatário não encontrado"
SE contato.endereco NULO → ERRO "Endereço do destinatário não encontrado"
SE contato.cidade_uf NULO → ERRO "Cidade/UF do destinatário não encontrada"
```

---

### etq0002: etiqueta_obrigatoria

**Descrição:** Após gerar, URL e código são obrigatórios.

**Regra:**
```
SE etiqueta_url NULO → ERRO "Falha ao gerar URL da etiqueta"
SE etiqueta_codigo NULO → ERRO "Falha ao gerar código de rastreio"
```

**Campos salvos em `pedidos`:**
- etiqueta_url
- etiqueta_codigo
- etiqueta_valor (frete cotado)
- etiqueta_paga = false

---

### etq0003: ja_paga

**Descrição:** Não pode pagar novamente uma etiqueta já paga.

**Regra:**
```
SE pedido.etiqueta_paga = true → ERRO "Etiqueta já foi paga"
```

---

### etq0004: nao_gerar_se_ja_existe

**Descrição:** Se etiqueta já existe, não gerar novamente automaticamente.

**Regra:**
```
SE etiqueta_codigo EXISTS AND etiqueta_paga = false
→ Opção 1: Mostrar botão "Cancelar" + "Pagar" (FLUXO CORRETO)
→ Opção 2: Toast "Etiqueta já gerada. Deseja cancelar e gerar nova?"
→ NÃO gerar automaticamente!
```

---

### etq0005: pagamento_sucesso

**Descrição:** Após pagar, confirmar sucesso.

**Verificação:**
```
SE result.success = true AND result.status = "paid" → SUCESSO
CASO CONTRÁRIO → ERRO "Pagamento não confirmado"
```

---

### etq0006: delete_etiqueta

**Descrição:** Cancelar etiqueta do SuperFrete (pode ser antes ou DEPOIS de paga).

**Regra:**
```
1. DELETE para https://api.superfrete.com/api/v0/cart/{codigo}
2. BODY: { "reason": "Desistência da compra" }
3. UPDATE pedido SET etiqueta_url = NULL, etiqueta_codigo = NULL, etiqueta_valor = NULL, etiqueta_paga = NULL
```

**Importante:** O cancelamento funciona MESMO após a etiqueta estar paga!

---

### etq0007: dimensoes_caixa

**Descrição:** Dimensões fixas da caixa de envio.

**Valores (hardcoded):**
```
width:  11cm
height: 2cm
length: 16cm
```

---

### etq0008: service_frete

**Descrição:** Tipo de serviço de envio.

**Códigos:**
```
mini  = 33162
pac   = 3
sedex = 1 (DEFAULT)
```

---

### etq0009: options_entrega

**Descrição:** Opções adicionais de entrega.

**Valores (hardcoded):**
```json
{
  "receipt": false,
  "own_hand": false
}
```

---

### etq0010: erro_saldo

**Descrição:** Detectar erro de saldo insuficiente.

**Verificação:**
```
SE error.message INCLUDES "saldo" OR "insufficient"
→ ERRO "Saldo insuficiente no Super Frete!"
```

---

### etq0011: atualizar_codigo_rastreio

**Descrição:** Código de rastreio pode mudar após pagamento.

**Regra:**
```
APÓS pagar, salvar pedido.etiqueta_codigo = result.tracking
```

---

### etq0012: toast_mensagens

**Descrição:** Mensagens de feedback ao usuário.

**Mensagens:**
| Ação | Sucesso | Erro |
|------|---------|------|
| Gerar | "Etiqueta gerada! Agora clique em Pagar" | "Erro ao gerar etiqueta..." |
| Pagar | "Etiqueta paga e emitida com sucesso!" | "Erro ao pagar etiqueta" |
| Pagar Todas | "{n} etiqueta(s) paga(s)!" | "Erros: {lista}" |

---

### etq0013: ui_botoes_apos_gerar

**Descrição:** Estado dos botões após gerar etiqueta.

**FLUXO CORRETO:**

| Estado | Botão Imagem | Botão Ação | Info Exibida |
|--------|-------------|-----------|-------------|
| Sem etiqueta | Ícone impressora (desabilitado) | "Gerar" | - |
| Etiqueta gerada | Ícone X (cancelar) | "Pagar" | valor_frete + modalidade |
| Etiqueta paga | Ícone impressora | "Cancelar" | código_rastreio |

**Botões após pagar:**
```
[🖨️ Imprimir] [❌ Cancelar]  ← ICONE de impressora + botão Cancelar
```

---

### etq0014: NAO atualiza status via pagar

**Descrição:** **NÃO** atualizar status_pedido quando paga etiqueta.

**Motivo:** O status é atualizado automaticamente pela **Automação de Rastreio** (useTrackingAutomation).

**Regra:**
```
APÓS pagarComSucesso:
→ etiqueta_paga = true ✓
→ etiqueta_codigo = result.tracking ✓
→ NÃO atualizar status_pedido (Automação FAZ ISSO!)
```

---

### etq0015: automacao_atualiza_status

**Descrição:** Automação de rastreio atualiza status automaticamente.

**Implementação:**
```typescript
// useTrackingAutomation.ts (frontend)
// superfrete-sync (Edge Function)

1. Roda a cada 10 minutos
2. Busca pedidos WHERE etiqueta_paga = true AND status_pedido IN ('aguardando_rastreio', 'postado')
3. Chama API SuperFrete tracking
4. SE status = 'delivered' → status_pedido = 'entregue'
5. SE status = 'in_transit' → status_pedido = 'postado'
```

---

### etq0016: card_sai_logistica_quando_postado

**Descrição:** Card sai da aba logística quando status = postado.

**Regra:**
```
LogisticaPage queries: WHERE status_pedido = 'aguardando_rastreio'
Quando status vira 'postado', card SOME automaticamente da lista
```

---

### etq0017: sync_atualiza_codigo_rastreio

**Descrição:** Sync atualiza código de rastreio se mudou.

**Regra:**
```
SE tracking_api !== etiqueta_codigo
→ UPDATE codigo_rastreio = tracking_api
→ UPDATE etiqueta_codigo = tracking_api
```

---

## Tabela de Constraints

| ID | Nome | Tipo | Severidade |
|----|------|------|-----------|
| etq0001 | dados_destinatario | PRE-CHECK | BLOCK |
| etq0002 | etiqueta_obrigatoria | POST-CHECK | BLOCK |
| etq0003 | ja_paga | PRE-CHECK | BLOCK |
| etq0004 | nao_gerar_se_ja_existe | PRE-CHECK | WARN |
| etq0005 | pagamento_sucesso | POST-CHECK | BLOCK |
| etq0006 | delete_etiqueta | ACTION | - |
| etq0007 | dimensoes_caixa | DEFAULT | AUTO |
| etq0008 | service_frete | CONVERT | AUTO |
| etq0009 | options_entrega | DEFAULT | AUTO |
| etq0010 | erro_saldo | ERROR_CHECK | BLOCK |
| etq0011 | atualizar_codigo_rastreio | POST-CHECK | AUTO |
| etq0012 | toast_mensagens | FEEDBACK | - |
| etq0013 | ui_botoes_apos_gerar | UI_STATE | REQUIRED |
| etq0014 | NAO atualiza status via pagar | RULE | IMPORTANT |
| etq0015 | automacao_atualiza_status | AUTOMATION | REQUIRED |
| etq0016 | card_sai_logistica_quando_postado | UI_FILTER | REQUIRED |
| etq0017 | sync_atualiza_codigo_rastreio | SYNC | AUTO |

---

## Fluxo Completo CORRETO (CASCATA)

```
[ESTADO 1: SEM ETIQUETA]
├── UF definida ✓
├── Modalidade definida (SEDEX/PAC/mini)
└── Botão: "Gerar"

[ESTADO 2: GERAR ETL]
├── 1. Cotarfrete (valor exibido)
├── 2. Gerar-etiqueta
├── 3. Salvar: etiqueta_url, etiqueta_codigo, etiqueta_valor, etiqueta_paga = false
└── 4. UI: Botões "Cancelar" + "Pagar" + valor_exibido

[ESTADO 3: ETIQUETA GERADA]
├── Etiqueta gerada (não paga)
├── Valor do frete exibido ✓
├── Modalidade exibida ✓
├── Botão Cancelar → Habilitado ✓
├── Botão Pagar → Habilitado ✓
└── NÃO permitir regenerar

[ESTADO 4: ETIQUETA PAGA]
├── 1. Pagar-etiqueta
├── 2. Salvar etiqueta_paga = true, etiqueta_codigo = tracking
└── 3. NÃO mexe em status_pedido

[ESTADO 5: AUTOMACAO DE RASTREIO]
├── 1. useTrackingAutomation roda a cada 10 min
├── 2. Para cada pedido com etiqueta_codigo:
│   ├── Chama API SuperFrete tracking
│   ├── SE status = 'in_transit' → status_pedido = 'postado'
│   ├── SE status = 'delivered' → status_pedido = 'entregue'
│   └── SE tracking mudou → atualiza codigo_rastreio
└── 6. Card sai da logística QUANDO status = 'postado'

[ESTADO 6: PEDIDO POSTADO]
├── Card NÃO aparece mais em LogísticaPage
├── Status = 'postado' na aba Pedidos
└── Aguardando entrega

[ESTADO 7: PEDIDO ENTREGUE]
├── status_pedido = 'entregue'
└── Mostrar "Entregue" na aba Pedidos
```

---

## Related Files

- Frontend: 
  - `src/hooks/useTrackingAutomation.ts` (Automação)
  - `src/pages/LogisticaPage.tsx`
  - `src/pages/PedidosPage.tsx`
- Edge Functions:
  - `supabase/functions/superfrete-sync/index.ts`
  - `supabase/functions/cotar-frete/index.ts`
  - `supabase/functions/gerar-etiqueta/index.ts`
  - `supabase/functions/pagar-etiqueta/index.ts`
- Constraints: 
  - `.agent/constraints/frete.md`
  - `.agent/constraints/estoque.md`
- Workflow: 
  - `.agent/workflows/gerar_etiquetas.md`
- Skills: 
  - `.agent/skills/superfrete-sync/SKILL.md`
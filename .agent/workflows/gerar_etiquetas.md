# Workflow: Geração de Etiquetas

> Descrição: Workflow completo para gerar, pagar e sincronizar etiquetas via SuperFrete.

---

## FLUXO EM CASCATA (CORRETO)

### FASE 1: GERAR ETIQUETA

| Step | Ação | Constraint |
|------|------|-----------|
| 1 | Verificar UF, remetente, API key | fret0001, fret0002, fret0003 |
| 2 | Cotarfrete (obter valor) | fret0010 |
| 3 | Gerar-etiqueta (API SuperFrete) | etq0002 |
| 4 | Salvar: etiqueta_url, etiqueta_codigo, etiqueta_valor, etiqueta_paga = false | etq0002 |
| 5 | **Exibir valor no card** | fret0013 |
| 6 | Alterar botões: Cancelar + Pagar | etq0013 |

### FASE 2: PAGAR ETIQUETA

| Step | Ação | Constraint |
|------|------|-----------|
| 1 | Verificar: etiqueta_codigo existe E etiqueta_paga = false | etq0003 |
| 2 | Pagar-etiqueta (API SuperFrete) | etq0005 |
| 3 | Salvar: etiqueta_paga = true, etiqueta_codigo = tracking | etq0011 |
| 4 | **NÃO atualizar status_pedido** | etq0014 |

### FASE 3: AUTOMÇAO DE RASTREIO

**EXECUTA A CADA 10 MINUTOS (useTrackingAutomation + superfrete-sync)**

| Step | Ação | Constraint |
|------|------|-----------|
| 1 | Buscar pedidos.com etiqueta_codigo E status IN ('aguardando_rastreio', 'postado') | etq0015 |
| 2 | Para cada: chamar API SuperFrete tracking | etq0017 |
| 3 | SE status = 'in_transit' → status_pedido = 'postado' | etq0015 |
| 4 | SE status = 'delivered' → status_pedido = 'entregue' | etq0015 |
| 5 | SE tracking mudou → atualizar codigo_rastreio | etq0017 |

### FASE 4: CARD SAI DA LOGSTICA

| Quando | Ação |
|--------|------|
| status muda para 'postado' | Card **some** da LogísticaPage |
| status = 'postado' ou 'entregue' | Card não aparece em LogísticaPage |

---

## Estados do Card

### Estado 1: SEM ETIQUETA
```
┌─────────────────────────────┐
│ Cliente                  │
│ Produto: 1x CBD 500mg    │
│ UF: SP    Modalidade: SEDEX│
├─────────────────────────────┤
│ [Gerar Etiqueta]          │
└─────────────────────────────┘
```

### Estado 2: ETIQUETA GERADA
```
┌─────────────────────────────┐
│ Cliente                  │
│ Produto: 1x CBD 500mg    │
│ Frete: R$ 15,90 (SEDEX)  │  ← VALOR EXIBIDO
├─────────────────────────────┤
│ [Cancelar] [Pagar]       │  ← BOTÕES ALTERADOS
└─────────────────────────────┘
```

### Estado 3: ETIQUETA PAGA
```
┌─────────────────────────────┐
│ Cliente                  │
│ Frete: R$ 15,90 (SEDEX) │
│ Código: AB123456789BR   │
├─────────────────────────────┤
│ [Imprimir]              │
└─────────────────────────────┘
   ↓
   Card SOME da LogísticaPage
   (status = 'postado')
```

---

## Implementaes

### Frontend (existe)
- `src/hooks/useTrackingAutomation.ts` - Automação a cada 10 min
- `src/pages/LogisticaPage.tsx` - UI de logística
- `src/pages/PedidosPage.tsx` - Lista de pedidos

### Edge Functions
| Função | Descrição |
|--------|----------|
| `cotar-frete` | Cotar preo |
| `gerar-etiqueta` | Gerar etiqueta |
| `pagar-etiqueta` | Pagar etiqueta |
| `superfrete-sync` | Sync de status (servidor) |

---

## Related Files

- Constraints: `.agent/constraints/frete.md`, `.agent/constraints/etiqueta.md`, `.agent/constraints/estoque.md`
- Skills: `.agent/skills/cotar-frete/SKILL.md`, `.agent/skills/gerar-etiqueta/SKILL.md`, `.agent/skills/pagar-etiqueta/SKILL.md`, `.agent/skills/superfrete-sync/SKILL.md`
- Code: `src/hooks/useTrackingAutomation.ts`, `supabase/functions/superfrete-sync/index.ts`
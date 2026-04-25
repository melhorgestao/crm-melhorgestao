# Status: Pedido

> Status do pedido e transições válidas.

---

## Status Possíveis

| Status | Descrição | UI |
|--------|-----------|-----|
| `aguardando_rastreio` | Aguardando geração de etiqueta | Logística |
| `postado` | Etiqueta gerada e postada | Pedidos |
| `entregue` | Entregue ao cliente | Pedidos |

---

## Transições

```
aguardando_rastreio → postado (via automação sync)
postado → entregue (via automação sync)
```

---

## Regras

- Card aparece em Logística enquanto `status = aguardando_rastreio`
- Card sai de Logística quando `status = postado`
- Em PedidosPage mostra todos os status

---

## Automação (useTrackingAutomation)

```
A cada 10 minutos:
1. Buscar pedidos WHERE etiqueta_paga = true
2. Consultar API SuperFrete tracking
3. SE status = 'in_transit' → postado
4. SE status = 'delivered' → entregue
```
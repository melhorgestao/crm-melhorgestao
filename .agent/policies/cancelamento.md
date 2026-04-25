# Policy: Cancelamento

> Regras para cancelar etiqueta (antes ou depois de paga).

---

## Condições para Cancelar

```
1. Etiqueta existe (etiqueta_codigo não nulo) ✓
2. Usuário com permissão ✓
```

---

## Fluxo de Cancelamento

```
1. DELETE para api.superfrete.com/cart/{codigo}
   - BODY: { "reason": "Desistência da compra" }
2. UPDATE pedido SET:
   - etiqueta_url = NULL
   - etiqueta_codigo = NULL
   - etiqueta_valor = NULL
   - etiqueta_paga = NULL
3. Criar log_atividades
```

---

## Regras

- Funciona MESMO após pago
- Motivo obrigatório: "Desistência da compra"
- Card volta para estado "Gerar"

---

## Exceptions

| Exception | Ação |
|-----------|------|
| API SuperFrete fora | Limpar campos locais mesmo assim |
| Erro network | Retry manual |
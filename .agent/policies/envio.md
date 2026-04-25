# Policy: Envio

> Regras para permitir envio de pedido.

---

## Condições para Gerar Etiqueta

```
1. UF_postagem definida ✓
2. Remetente configurado para UF ✓
3. Dados destinatários completos ✓
4. API key SuperFrete configurada ✓
5. Modalidade selecionada ✓
```

---

## Casos especiais

### Entrega em Mãos
- Não precisa gerar etiqueta
- Modalidade = "entrega_maos"
- Estoque abatido imediatamente

### UF sem remetente
- Bloquear geração
- Exibir erro: "Configure remetente para UF {UF}"

---

## Validações

```sql
-- Verificar UF existe
SELECT * FROM remetentes_uf WHERE uf = :uf_postagem;

-- Verificar dados contato
SELECT cep, endereco, cidade_uf 
FROM contatos 
WHERE id = :contato_id;
```
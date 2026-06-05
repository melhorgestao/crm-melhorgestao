# Arquitetura — Agente Conversacional WhatsApp Santa Flor

> Documento de referência consolidado da sessão 04-05/06/2026.
> Use como guia pra construção das próximas sessões.

---

## 1. State Machine — 9 estados em `contatos.ultima_interacao`

| Estado | Significado | Quem entra | Próximo |
|---|---|---|---|
| `NULL` | Lead nunca interagiu | Default no insert | start (via AGENT_START) |
| `start` | Em apresentação inicial (cardápio sendo mostrado) | AGENT_START quando state=NULL | wait_follow_up / em_fechamento / cliente |
| `wait_follow_up` | Viu cardápio, não fechou, alvo do Follow-up | Após sumir do start | follow_up (workflow) / em_fechamento (responde) / NULL (90d) |
| `follow_up` | Recebeu campanha Follow-up | Workflow Follow-up | wait_follow_up (24h timeout) / em_fechamento / cliente |
| `ativacao_contatos` | Cliente recebeu campanha de ativação | Workflow Ativação | cliente (3d timeout) / em_fechamento |
| `rastreio` | Recebeu link rastreio | Workflow Rastreio | cliente (após resposta ou timeout) |
| `em_fechamento` | Negociando ativamente (Typebot CLOSING) | AGENT_START detecta intent | cliente (vendeu) / volta a estado anterior (48h timeout) |
| `cliente` | Cadastrado + já comprou, modo escuta | Trigger ja_comprou ou cron | ativacao_contatos / rastreio / em_fechamento |
| `NUNCA_MAIS` | Bloqueado (LGPD, xinga, 3 follow-ups esgotados) | Manual ou cron | terminal |

### Colunas auxiliares em `contatos`

```sql
ultima_interacao TEXT
ja_comprou BOOLEAN (trigger pedidos pagos)
data_apresentacao TIMESTAMPTZ
data_wait_follow_up TIMESTAMPTZ
data_em_fechamento TIMESTAMPTZ
data_cliente TIMESTAMPTZ
data_ultima_ativacao TIMESTAMPTZ
data_ultimo_follow_up TIMESTAMPTZ
data_ultimo_rastreio TIMESTAMPTZ
data_nunca_mais TIMESTAMPTZ
ativacao_respondeu_em TIMESTAMPTZ
ativacao_consecutive_silenciosos INTEGER (DROP após 3)
follow_up_tentativas INTEGER (24h, 3d, 7d → NUNCA_MAIS)
typebot_closing_session_id TEXT
typebot_closing_session_em TIMESTAMPTZ
rem_tem_foto BOOLEAN (priorização ordering — única coluna rem_* mantida)
```

---

## 2. Typebot — só CLOSING

**1 Typebot: TYPEBOT_CLOSING**

- Fluxo determinístico: CEP → produto → PIX → confirma
- Sessão persistente via `contatos.typebot_closing_session_id`
- Parametrizado por chip: recebe `{chip_apikey}` e `{chip_url}` no startChat
- 1 instância Typebot serve as 2 instâncias (chips) dinamicamente

**Por que não Typebot pra LISTENING?**
Listener stateless com LLM + DB é mais simples em n8n direto. Typebot brilharia se fosse multi-step + visual, mas listening é single-turn responder.

---

## 3. n8n Workflows — 12 totais

### Entrada (2)

**1. Router** (central)
- Recebe webhook Evolution (ambos chips)
- INSERT em `mensagens_buffer`
- Áudio? → Whisper transcribe
- WAIT 12s (debounce — absorve burst de msgs)
- Check "sou a msg mais recente?" — se não, EXIT
- Concat msgs unprocessed
- SWITCH `ultima_interacao`:
  - `em_fechamento` → forward TYPEBOT_CLOSING (startChat se sessionId null, senão continueChat)
  - outros → forward AGENT_START

**2. AGENT_START** (listener LLM)
- Carrega contato + 10 últimas msgs + estado completo + top 3 chunks RAG
- Prompt MODULAR por estado (não mega-prompt)
- Chama Llama 3.1 70B free OpenRouter (temperature 0.25)
- Retorna JSON estruturado: `{ resposta, intent, transicao_estado, confidence }`
- IF intent=`fechar` → POST Typebot /startChat, salva sessionId, SET em_fechamento
- IF intent=`escalar` ou confidence<0.7 → notifica Chatwoot humano
- ELSE → Evolution sendText resposta, atualiza estado se necessário
- INSERT msg bot em mensagens_buffer

### Disparo (6 — 3 campanhas × 2 chips)

**3-4. Disparo Ativação chip 1 / chip 2**
- Schedule 2-3 min + Code anti-ban
- POST `claim_proximo_lead_ativacao(UUID)` → estado vira `ativacao_contatos`
- SEND MSG EVO (chip correspondente)

**5-6. Disparo Follow-up chip 1 / chip 2**
- POST `claim_proximo_lead_followup(UUID)` → retorna `tentativa` (1, 2 ou 3)
- Mensagem **dinâmica** por tentativa (1ª leve, 2ª direta, 3ª última chance)
- SEND MSG EVO

**7-8. Disparo Rastreio chip 1 / chip 2** (já existem — atualizar pra marcar estado)

### Infraestrutura (4)

**9. Cron Transições**
- Schedule 1h → POST `processar_transicoes_estado_contato`
- ativacao 3d sem resp → cliente/wait_follow_up + incrementa silenciosos
- follow_up 24h sem resp → wait_follow_up
- wait_follow_up com 3 tentativas → NUNCA_MAIS
- em_fechamento 48h → cliente/wait_follow_up + limpa typebot_session_id

**10. Monitor Conexão** (proteção chip)
- Webhook Evolution (`connection.update`, `qrcode.updated`)
- + Schedule 10min checa falhas consecutivas em workflows
- Detecta restrição → Telegram alert + HTTP POST n8n API pra desativar workflow do chip
- Schedule 3 dias depois → "ok reativar"

**11. Webhook Pagamento**
- Webhook gateway PIX
- Marca pedido pago → trigger ja_comprou dispara
- Evolution sendText "✅ pago, posto hoje"
- Notifica TYPEBOT_CLOSING via continueChat (avança no flow)

**12. Midnight Lead Migration** (já existe)
- Schedule diário 00:00
- POST `perform_midnight_lead_migration`

---

## 4. AGENT_START — Lógica por estado

```
ENTRADA:
  contato_id (Router cria se não existe)
  mensagem

STEP 1: Carrega contexto
  SELECT contato (ultima_interacao, ja_comprou, nome, endereco, ultima_venda_em)
  SELECT últimas 10 msgs (mensagens_buffer)
  
STEP 2: Classifica intent rápido (Haiku ou regex) pra filtrar chunks
  → categorias: produto / entrega / pagamento / preço / objecao / outro

STEP 3: RAG retrieval
  SELECT search_knowledge(embedding_pergunta, categoria, k=3)

STEP 4: Monta prompt MODULAR por estado:
  
  IF NULL: "Cliente novo. Apresente Santa Flor. Mostre cardápio {chunks_produto}. Pergunte qual interessa."
  IF start: "Continuação apresentação. Use contexto inicial. Detecte intent."
  IF cliente: "Cliente {nome} comprou {n} vezes. Tom familiar. Sem cardápio."
  IF wait_follow_up: "Lead em dúvida. 'Posso esclarecer?' + gancho fechamento."
  IF ativacao_contatos: "Respondeu campanha ativação. Reset silenciosos. Marca respondeu_em."
  IF follow_up: "Respondeu follow-up. Agradece + esclarece + gancho."
  IF rastreio: "Detecta agradecimento vs dúvida entrega. Resolve → cliente."
  
STEP 5: LLM call (Llama 3.1 70B free, temp 0.25, JSON mode)
  Output: { resposta, intent, transicao_estado?, confidence }

STEP 6: Pre/Post guardrails
  - Pre: detecta intent perigoso (advice médica, comparação concorrente)
  - Post: checa se resposta menciona produtos/preços/prazos NÃO documentados
  - Confidence < 0.7 → escala humano

STEP 7: Aplica transição
  UPDATE contatos SET ultima_interacao = transicao_estado (se houver)

STEP 8: Envia via Evolution (chip do contato)

STEP 9: Salva resposta bot em mensagens_buffer
```

---

## 5. Anti-hallucination — 6 camadas

| # | Defesa | Como |
|---|---|---|
| 1 | **Prompt modular** | System prompt curto (~200-500 tokens) por estado, não mega-prompt |
| 2 | **RAG estrito** | Top 3 chunks filtrados por categoria (não top 10 sem filtro) |
| 3 | **JSON estruturado** | Output forçado em schema. Confidence < 0.7 → humano |
| 4 | **Temperature baixa** | 0.2-0.3 (default Llama free é 0.7+) |
| 5 | **Tiered routing** | Llama free pra 90%, Sonnet pra 10% críticos (objeção forte, médico, complaint) |
| 6 | **Pre/Post guardrails** | Pre: detecta intent perigoso. Post: checa produto/prazo inventado |

**Custo estimado:** <$30/mês em volume médio (Llama free + Sonnet pontual).

---

## 6. Recursos Supabase

### Tabelas críticas

```
contatos              -- estado + ja_comprou + Typebot sessionId + datas
pedidos               -- gera ja_comprou via trigger
mensagens_buffer      -- debounce + histórico conversa
knowledge_chunks      -- pgvector, embeddings de chunks de conhecimento
eventos_contato       -- auditoria opcional de transições
```

### RPCs

```
claim_proximo_lead_ativacao(p_instancia_id, p_dias_gap=30)
claim_proximo_lead_followup(p_instancia_id) → retorna tentativa
release_claim_rmkt(p_contato_id, p_instancia_id)
processar_transicoes_estado_contato()
perform_midnight_lead_migration()
search_knowledge(query_embedding, categoria, k=3)  -- A CRIAR
trigger_set_ja_comprou()
trigger_update_ultima_venda_on_pedido()
```

### Triggers

```
pedidos_set_ja_comprou         AFTER INSERT/UPDATE OF status_pagamento ON pedidos
update_ultima_venda_pedido     AFTER INSERT ON pedidos
update_ultima_venda_lancamento AFTER INSERT ON lancamentos_socios
```

---

## 7. Stack

| Camada | Tecnologia |
|---|---|
| Recebimento WhatsApp | Evolution v2.3 |
| Orquestração | n8n self-hosted (n8n.melhorgestao.online) |
| Estado + DB + RAG | Supabase Postgres + pgvector |
| Fluxo de venda visual | Typebot self-hosted |
| LLM principal (listening) | OpenRouter — Llama 3.1 70B free |
| LLM fallback (críticos) | Claude Sonnet via Anthropic API |
| Transcrição áudio | Whisper (OpenAI ou Faster-Whisper self-hosted) |
| Pagamento PIX | TBD: PicPay / MercadoPago / Stripe |
| Frete | SuperFrete API (já integrado) |
| CEP | ViaCEP (público gratuito) |
| Alertas operacionais | Telegram Bot |
| Atendimento humano | Chatwoot (já integrado Evolution) |

---

## 8. Ordem de construção sugerida

```
SESSÃO 1 (próxima):
1. Telegram bot + Monitor Conexão (#10) — proteção primeiro
2. Cron Transições workflow + mensagens_buffer table (#28 + #29)
3. AGENT_START skeleton no n8n (sem RAG ainda, só listener simples)

SESSÃO 2:
4. pgvector enable + knowledge_chunks table + search_knowledge RPC (#26)
5. Knowledge base inicial: produtos, FAQ entrega, FAQ pagamento, objeções
6. Embeddings via OpenAI text-embedding-3-small

SESSÃO 3:
7. Router workflow completo (debounce + transcribe áudio + switch)
8. AGENT_START com RAG ativo + tiered LLM routing
9. Testes end-to-end com 1 contato real

SESSÃO 4:
10. TYPEBOT_CLOSING — flow visual completo
11. Webhook Pagamento + integração PIX gateway
12. Teste fechamento completo

SESSÃO 5:
13. Disparo Follow-up chip 1 (RPC já existe)
14. Clone Follow-up chip 2
15. Refator Disparo Ativação chip 1 (atualmente "RMKT BASE")
16. Clone Ativação chip 2

SESSÃO 6:
17. Dashboard métricas (#19)
18. Eventos_contato + analytics
19. A/B testing infra (templates de mensagem)
```

---

## 9. Decisões abertas pra próxima sessão

1. **Gateway PIX**: PicPay, MercadoPago ou Stripe?
2. **Whisper**: OpenAI API (paid, melhor) ou self-hosted (free, requer GPU)?
3. **Typebot deployment**: Cloud paid ou self-hosted no VPS?
4. **Knowledge base inicial**: quantos chunks? quais categorias?
5. **Telegram chat_id**: pessoal ou grupo "Alertas Santa Flor"?
6. **Eventos_contato**: criar agora ou pular pra ter MVP rápido?
7. **A/B testing de templates**: vale agora ou depois?

---

## 10. Status atual ao fim da sessão 04-05/06

### Já entregue (banco prontíssimo)

- ✅ Multi-chip arquitetura (instâncias 1, 2 com claim atômico)
- ✅ State machine 9 estados aplicado
- ✅ ja_comprou trigger
- ✅ RPCs claim_ativacao + claim_followup + release_claim
- ✅ Cron processar_transicoes_estado_contato (precisa schedule no n8n)
- ✅ Coluna typebot_closing_session_id
- ✅ Cleanup colunas legacy (rem_* exceto rem_tem_foto)
- ✅ Workflow chip 2 "RMKT BASE" rodando (dispara como ativacao_contatos agora)
- ✅ Kanban refactor por instância
- ✅ Filtro 30 dias funcionando

### Pendente runtime

- ⏳ Workflow chip 1 pausado (chip restringido — aguarda recuperação)
- ⏳ Cron Transições não tem schedule ainda
- ⏳ Sem Router / AGENT_START / TYPEBOT_CLOSING ainda
- ⏳ Sem Telegram alert
- ⏳ Sem Knowledge base / RAG

### Workflows n8n já existentes

```
RMKT BASE chip 2 (publicado, rodando)     ← refatorar nome pra "Ativação chip 2"
RMKT BASE chip 1 (pausado, restrição)      ← idem chip 1
Rastreio (publicado)                       ← já marca rastreio state? VERIFICAR
Respondeu Rmkt BASE (publicado, antigo)    ← APOSENTAR quando Router subir
```

---

Documento vivo. Atualizar a cada sessão.

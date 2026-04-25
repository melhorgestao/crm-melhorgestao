# Skill: superfrete-sync

> Sincronização automática de status de pedidos via SuperFrete API.

## Quando Usar

- Job agendado (cron) rodando a cada 5-10 minutos
- Atualiza status dos pedidos: `postado` → `entregue`
- Atualiza código de rastreio se mudou
- executado automaticamente pelo Supabase Edge Functions

---

## Trigger

**Agendamento:** A cada 5-10 minutos via Supabase Cron ou Edge Function

```typescript
// API CORRIGIDA: Usar api.superfrete.com (não sandbox!)
const res = await fetch(
  `https://api.superfrete.com/api/v0/tracking/${pedido.etiqueta_codigo}`,
  // ...
);
```
```

---

## Input (EDGE FUNCTION)

```json
{
  // Sem input necessário - busca automaticamente
}
```

### Parâmetros

A Edge Function busca automaticamente:

```sql
SELECT id, etiqueta_codigo, status_pedido 
FROM pedidos 
WHERE etiqueta_paga = true 
AND status_pedido != 'entregue';
```

---

## Output

```json
{
  "success": true,
  "checked": 10,
  "updated": 2,
  "results": [
    { "pedido_id": "uuid-1", "status": "delivered", "updated": true },
    { "pedido_id": "uuid-2", "status": "in_transit", "updated": false }
  ]
}
```

---

## Status Mapping

| Status SuperFrete | Status CRM | Descrição |
|------------------|-----------|-----------|
| `awaiting_purchase` | aguardando_rastreio | Aguardando gerar |
| `paid` | aguardando_rastreio | Pago, não postado |
| `postado` | postado | Enviado |
| `in_transit` | postado | Em trânsito |
| `delivered` | **entregue** | Entregue ✓ |
| `returned` | devolvido | Devolvido |
| `canceled` | cancelado | Cancelado |

---

## API SuperFrete - Tracking

**Endpoint:** `GET https://api.superfrete.com/api/v0/tracking/{tracking_code}`

**Headers:**
```json
{
  "Authorization": "Bearer {api_key}",
  "Accept": "application/json"
}
```

---

## Fluxo de Sync

```
[1] Iniciar Edge Function
    │
[2] Buscar pedidos com etiqueta_paga = true E status != 'entregue'
    │
[3] Para cada pedido:
    │
    ├── [3.1] Chamar API SuperFrete Tracking
    │
    ├── [3.2] Mapear status
    │
    └── [3.3] SE status mudou:
        │
        ├── [3.3.1] Atualizar status_pedido
        ├── [3.3.2] Atualizar etiqueta_codigo (se mudou)
        └── [3.3.3] Criar log_atividades
    │
[4] Retornar resumo
```

---

## Constraints Verificadas

- `etiqueta.etq0015` - status_atualizar_entregue
- `etiqueta.etq0016` - sync_status_superfrete
- `frete.fret0003` - api_key_obrigatoria

---

## Exemplo de Edge Function

```typescript
// supabase/functions/superfrete-sync/index.ts
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 1. Buscar API key
    const { data: config } = await supabase
      .from('configuracoes')
      .select('valor')
      .eq('chave', 'chave_api_superfrete')
      .single();
    
    const apiKey = config?.valor;
    if (!apiKey) {
      return new Response(JSON.stringify({ error: 'API key não configurada' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // 2. Buscar pedidos para verificar
    const { data: pedidos } = await supabase
      .from('pedidos')
      .select('id, etiqueta_codigo, status_pedido')
      .eq('etiqueta_paga', true)
      .neq('status_pedido', 'entregue');
    
    const results = [];
    let updated = 0;

    // 3. Verificar cada pedido
    for (const pedido of pedidos || []) {
      if (!pedido.etiqueta_codigo) continue;
      
      // Chamar API SuperFrete tracking
      const res = await fetch(
        `https://api.superfrete.com/api/v0/tracking/${pedido.etiqueta_codigo}`,
        {
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Accept': 'application/json',
          },
        }
      );
      
      if (!res.ok) continue;
      
      const data = await res.json();
      const sfStatus = data.status || data.current_status;
      
      // Mapear status
      let newStatus = null;
      if (sfStatus === 'delivered' || sfStatus === 'delivered_to_sender') {
        newStatus = 'entregue';
      } else if (sfStatus === 'returned' || sfStatus === 'return') {
        newStatus = 'devolvido';
      }
      
      if (newStatus && newStatus !== pedido.status_pedido) {
        await supabase
          .from('pedidos')
          .update({ status_pedido: newStatus })
          .eq('id', pedido.id);
        
        // Log
        await supabase.from('log_atividades').insert({
          usuario: 'Sistema Sync',
          acao: `Status atualizado para ${newStatus}`,
          tabela_afetada: 'pedidos',
          registro_id: pedido.id,
        });
        
        updated++;
      }
      
      results.push({
        pedido_id: pedido.id,
        old_status: pedido.status_pedido,
        new_status: sfStatus,
        updated: !!newStatus,
      });
    }

    return new Response(JSON.stringify({
      success: true,
      checked: pedidos?.length || 0,
      updated,
      results,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});
```

---

## Configuração de Cron

No Supabase, configure para executar a cada 5-10 minutos:

```toml
# supabase/functions/superfrete-sync/config.toml
[lambda]
handler = "index.ts"
runtime = "deno"

# Agendamento (se suportado)
schedule = "*/5 * * * *"  # A cada 5 minutos
```

Ou configure um webhook externo (como cron-job.org) para chamar a Edge Function.

---

## Arquivo Relacionado

- Workflow: `.agent/workflows/gerar_etiquetas.md`
- Constraint: `.agent/constraints/etiqueta.md`, `.agent/constraints/frete.md`
- Edge Function: `supabase/functions/superfrete-sync/index.ts`
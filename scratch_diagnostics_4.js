const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const respProd = await fetch(`${SUPABASE_URL}/rest/v1/produtos?select=id,nome_oficial,tag`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const produtos = await respProd.json();

  const respPed = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&lt.2026-05-01&status_pedido=neq.cancelado&select=*`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await respPed.json();

  const respItens = await fetch(`${SUPABASE_URL}/rest/v1/pedido_itens?select=pedido_id,produto_id`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const itens = await respItens.json();

  const ghostOrders = [];

  for (const p of pedidos) {
    if ((p.quantidade || 0) <= 0) continue;

    let matched = false;
    
    // 1. Itens
    if (itens.some(i => i.pedido_id === p.id)) matched = true;
    
    // 2. JSON
    if (!matched && typeof p.produto === 'string' && p.produto.startsWith('[')) matched = true;

    // 3. Name/Tag match
    if (!matched) {
        for (const pr of produtos) {
            const prodStr = String(p.produto || '').toLowerCase();
            const tag = pr.tag.toLowerCase();
            const nome = pr.nome_oficial.toLowerCase();
            if (prodStr.includes(tag) || prodStr.includes(nome) || nome.includes(prodStr)) {
                matched = true;
                break;
            }
        }
    }

    if (!matched) {
        ghostOrders.push({
            id: p.id.split('-')[0],
            data: p.data,
            qty: p.quantidade,
            produto: p.produto,
            obs: p.observacao,
            canal: p.canal
        });
    }
  }

  console.log(`TOTAL ORDERS: ${pedidos.length}`);
  console.log(`GHOST ORDERS (Found in Metricas but not Stock): ${ghostOrders.length}`);
  console.table(ghostOrders);
}
run();

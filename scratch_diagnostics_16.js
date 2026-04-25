const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const respPed = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&status_pedido=neq.cancelado&select=id,order_number,produto_id,produto,quantidade`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await respPed.json();
  
  console.log("--- PEDIDOS with 10k SC (or suspiciously related) ---");
  pedidos.forEach(p => {
      const prodStr = String(p.produto || '').toLowerCase();
      if (prodStr.includes('10.000') || prodStr.includes('10k') || prodStr.includes('10 000')) {
          console.log(`Order #${p.order_number}: Prod_id: ${p.produto_id}, Content: ${p.produto}, Qty: ${p.quantidade}`);
      }
  });

  const respMov = await fetch(`${SUPABASE_URL}/rest/v1/estoque_movimentacoes?tipo=eq.saida&select=id,pedido_id,quantidade,produto_id`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const movs = await respMov.json();
  const movOrders = movs.map(m => m.pedido_id);

  console.log("\n--- ORDERS WITHOUT MOVEMENTS ---");
  pedidos.forEach(p => {
     if (!movOrders.includes(p.id)) {
         console.log(`Order #${p.order_number} (ID: ${p.id}) has NO movement. Content: ${p.produto}`);
     }
  });
}
run();

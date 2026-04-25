const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const respPed = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&status_pedido=neq.cancelado&select=id,order_number,produto,quantidade,uf_postagem`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await respPed.json();
  
  console.log("--- CHECKING ORDERS with 2x 10k SC ---");
  pedidos.forEach(p => {
      const prodStr = String(p.produto || '').toLowerCase();
      if (prodStr.includes('full 10k') || prodStr.includes('10.000')) {
          console.log(`Order #${p.order_number}: UF Postagem: ${p.uf_postagem}, Content: ${p.produto}`);
      }
  });
}
run();

const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const start = `2026-04-01`;
  const end = `2026-05-01`;

  const resp = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.${start}&data=lt.${end}&status_pedido=neq.cancelado&select=*`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await resp.json();

  const seb = pedidos.filter(p => {
    const s = JSON.stringify(p).toLowerCase();
    return s.includes('sebastiao') || s.includes('sebastião');
  });
  
  console.log("SEBASTIAO RAW DATA:");
  console.log(JSON.stringify(seb, null, 2));

  // Find why Metricas shows 32 and Stock shows 31.
  console.log("ALL ORDERS QTD:");
  const sums = pedidos.map(p => p.quantidade || 0);
  const total = sums.reduce((a, b) => a + b, 0);
  console.log("TOTAL QUANTIDADE IN METRICAS:", total);
}
run();

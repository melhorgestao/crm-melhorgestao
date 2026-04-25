const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const start = "2026-04-02";
  const end = "2026-04-03";

  // Fetch ALL orders on April 2nd, including cancelled ones to be safe
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.${start}&data=lt.${end}&select=*,contatos(nome)`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await resp.json();
  
  console.log(`TOTAL ORDERS ON APRIL 2nd: ${pedidos.length}`);
  console.table(pedidos.map(p => ({
     d: p.data,
     nome: p.contatos?.nome,
     qty: p.quantidade,
     status: p.status_pedido,
     prod: String(p.produto).substring(0,30),
     obs: (p.observacao || '').substring(0,20)
  })));
}
run();

const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  // 1. Get the exact JSON of Sebastião Porto Junior
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?order_number=eq.1&data=lte.2026-04-10&select=id,produto,quantidade`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const data = await resp.json();
  console.log("SEBASTIAO ORDER #1 FULL PRODUTO COLUMN:");
  console.log(data[0].produto);

  // 2. Search for any order with exactly 1 unit on April 2nd
  // (User said "1 cbd do Sebastiao")
  const resp2 = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=eq.2026-04-02&quantidade=eq.1&select=*,contatos(nome)`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const data2 = await resp2.json();
  console.log("\nORDERS WITH QTY 1 ON APRIL 2nd:");
  console.table(data2.map(p => ({
    id: p.id.split('-')[0], cliente: p.contatos?.nome, prod: p.produto, obs: p.observacao
  })));
}
run();

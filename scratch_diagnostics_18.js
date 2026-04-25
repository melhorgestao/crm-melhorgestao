const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?order_number=eq.13&select=quantidade,produto,uf_postagem`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const data = await resp.json();
  console.log(data);
}
run();

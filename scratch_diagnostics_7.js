const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&lt.2026-05-01&select=*,contatos(nome)`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await resp.json();
  
  const seb = pedidos.filter(p => {
    const s = JSON.stringify(p).toLowerCase();
    return s.includes('sebastiao') || s.includes('sebastião');
  });
  
  console.log("ALL SEBASTIAO RECORDS IN APRIL:");
  console.log(JSON.stringify(seb, null, 2));
}
run();

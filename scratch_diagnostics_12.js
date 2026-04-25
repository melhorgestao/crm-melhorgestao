const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const CBD_ID = '4a8c827e-8bee-42f2-bf1e-edfdb8adf288';

  const resp = await fetch(`${SUPABASE_URL}/rest/v1/estoque_movimentacoes?produto_id=eq.${CBD_ID}&tipo=eq.saida&select=*`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const movs = await resp.json();
  
  console.log(`ANALYZING THE ${movs.length} GHOST MOVEMENTS:`);
  console.table(movs.map(m => ({
      id: m.id.split('-')[0],
      ped: m.pedido_id?.split('-')[0] || 'MANUAL',
      qty: m.quantidade,
      obs: m.observacao,
      uf: m.uf_origem,
      created: m.created_at
  })));
}
run();

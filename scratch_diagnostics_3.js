const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const respLotes = await fetch(`${SUPABASE_URL}/rest/v1/lotes?select=uf`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const lotes = await respLotes.json();
  const lotesUfs = [...new Set(lotes.map(l => l.uf))];
  console.log("UFs in LOTES:", lotesUfs);

  const respPedidos = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&select=uf_postagem,uf_cliente`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await respPedidos.json();
  const postUfs = [...new Set(pedidos.map(p => p.uf_postagem))];
  const clientUfs = [...new Set(pedidos.map(p => p.uf_cliente))];
  console.log("UFs in PEDIDOS (Postagem):", postUfs);
  console.log("UFs in PEDIDOS (Cliente):", clientUfs);

  // Search for the 32nd order!
  const respAll = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&lt.2026-05-01&status_pedido=neq.cancelado&select=id,data,quantidade,produto,uf_postagem,contatos(nome)`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const all = await respAll.json();
  console.log(`TOTAL ORDERS FOUND: ${all.length}`);
  const totalQty = all.reduce((s, p) => s + (p.quantidade || 0), 0);
  console.log(`TOTAL QTY (METRICAS): ${totalQty}`);

  // Find the CBD missing one
  const cbd = all.filter(p => JSON.stringify(p).toLowerCase().includes('cbd'));
  console.log(`CBD ORDERS FOUND: ${cbd.length}`);
  console.table(cbd.map(p => ({
     id: p.id.split('-')[0],
     date: p.data,
     nome: p.contatos?.nome,
     qty: p.quantidade,
     uf: p.uf_postagem,
     prod: JSON.stringify(p.produto).substring(0,30)
  })));
}
run();

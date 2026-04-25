const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const respProd = await fetch(`${SUPABASE_URL}/rest/v1/produtos?select=id,nome_oficial`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const prods = await respProd.json();
  const prodMap = {};
  prods.forEach(p => prodMap[p.id] = p.nome_oficial);

  const respPed = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&status_pedido=neq.cancelado&select=id,produto_id,produto,quantidade`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await respPed.json();
  
  const pedCount = {};
  
  pedidos.forEach(p => {
      if (typeof p.produto === 'string' && p.produto.startsWith('[')) {
          try {
              const arr = JSON.parse(p.produto);
              arr.forEach(i => {
                 let id = i.produto_id;
                 if(id) pedCount[id] = (pedCount[id] || 0) + (parseInt(i.quantidade)||0);
              });
          } catch(e) {}
      } else {
          // Simplification for the text based products
          const nome = String(p.produto||'').toLowerCase();
          // Let's just print them to see
      }
  });

  const respMov = await fetch(`${SUPABASE_URL}/rest/v1/estoque_movimentacoes?tipo=eq.saida&select=id,quantidade,pedido_id,observacao,produto_id,uf_origem`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const movs = await respMov.json();
  const movCount = {};
  movs.forEach(m => movCount[m.produto_id] = (movCount[m.produto_id] || 0) + m.quantidade);

  console.log("---- MOVS -----");
  for(let id in movCount) {
     console.log(`${prodMap[id] || id}: ${movCount[id]}`);
  }
}
run();

const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const respPed = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&status_pedido=neq.cancelado&select=id,produto,quantidade`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await respPed.json();
  
  let pedTotal = 0;
  
  pedidos.forEach(p => {
      let q = 0;
      if (typeof p.produto === 'string' && p.produto.startsWith('[')) {
          try {
              const arr = JSON.parse(p.produto);
              q = arr.reduce((s,i) => s + (parseInt(i.quantidade)||0), 0);
          } catch(e) {}
      } else {
          q = p.quantidade || 0;
      }
      pedTotal += q;
  });

  const respMov = await fetch(`${SUPABASE_URL}/rest/v1/estoque_movimentacoes?tipo=eq.saida&select=id,quantidade,pedido_id,observacao,produto_id,uf_origem`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const movs = await respMov.json();
  const movTotal = movs.reduce((s, m) => s + m.quantidade, 0);

  console.log(`TOTAL UNITS in Pedidos: ${pedTotal}`);
  console.log(`TOTAL UNITS in Movimentacoes: ${movTotal}`);
  console.log(`Missing: ${pedTotal - movTotal}`);
}
run();

const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const CBD_ID = '4a8c827e-8bee-42f2-bf1e-edfdb8adf288';

  // 1. O que o RPC V14 deveria contar (Baseado em Pedidos)
  const respPed = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&status_pedido=neq.cancelado&select=id,produto,quantidade`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await respPed.json();
  
  let rpcCount = 0;
  const rpcDetails = [];

  pedidos.forEach(p => {
      let q = 0;
      if (typeof p.produto === 'string' && p.produto.startsWith('[')) {
          try {
              const arr = JSON.parse(p.produto);
              q = arr.filter(i => i.produto_id === CBD_ID).reduce((s,i) => s + i.quantidade, 0);
          } catch(e) {}
      } else if (String(p.produto).toLowerCase().includes('cbd')) {
          q = p.quantidade || 0;
      }
      if (q > 0) {
          rpcCount += q;
          rpcDetails.push({ id: p.id.split('-')[0], qty: q, source: 'Pedido' });
      }
  });

  // 2. O que tem na tabela de Movimentações (O histórico físico)
  const respMov = await fetch(`${SUPABASE_URL}/rest/v1/estoque_movimentacoes?produto_id=eq.${CBD_ID}&tipo=eq.saida&select=id,quantidade,pedido_id,observacao`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const movs = await respMov.json();
  const movTotal = movs.reduce((s, m) => s + m.quantidade, 0);

  console.log(`CBD SAIDAS (RPC/Pedidos): ${rpcCount}`);
  console.log(`CBD SAIDAS (Tabela Movimentações): ${movTotal}`);
  
  console.log("\nDETALHE MOVIMENTAÇÕES (Tabela):");
  console.table(movs.map(m => ({ 
      id: m.id.split('-')[0], 
      ped: m.pedido_id?.split('-')[0] || 'MANUAL', 
      qty: m.quantidade, 
      obs: m.observacao 
  })));

  console.log("\nDETALHE PEDIDOS (RPC):");
  console.table(rpcDetails);
}
run();

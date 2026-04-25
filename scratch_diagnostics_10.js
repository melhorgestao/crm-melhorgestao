const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&lt.2026-05-01&status_pedido=neq.cancelado&select=id,data,quantidade,produto,observacao,contatos(nome)`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await resp.json();
  
  console.log(`ANALYZING ${pedidos.length} ORDERS (Summing to ${pedidos.reduce((s,p) => s+(p.quantidade||0),0)} units)`);
  
  const audit = pedidos.map(p => {
      let identifiedProduct = "Unknown";
      if (typeof p.produto === 'string' && p.produto.startsWith('[')) {
          try {
              const arr = JSON.parse(p.produto);
              identifiedProduct = arr.map(i => `${i.produto || i.nome || '?'}(${i.quantidade})`).join(', ');
          } catch(e) { identifiedProduct = "Invalid JSON"; }
      } else {
          identifiedProduct = p.produto || "Empty";
      }
      
      return {
          id: p.id.split('-')[0],
          data: p.data,
          nome: p.contatos?.nome,
          qty: p.quantidade,
          ident: identifiedProduct,
          obs: p.observacao
      };
  });

  console.table(audit);
}
run();

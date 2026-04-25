const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const start = `2026-04-01`;
  const end = `2026-05-01`;

  const resp = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.${start}&data=lt.${end}&status_pedido=neq.cancelado&select=*`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await resp.json();

  const prodTotal = pedidos.reduce((s, p) => s + (p.quantidade || 0), 0);
  console.log(`METRICAS TAB COUNTS (Total Produtos): ${prodTotal}`);

  const respItens = await fetch(`${SUPABASE_URL}/rest/v1/pedido_itens?select=*`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const itens = await respItens.json();

  let cbdCount = 0;
  const cbdOrders = [];

  for (const p of pedidos) {
    let q = p.quantidade || 0;
    let isCBD = false;
    let matchType = '';
    
    const pItens = itens.filter(i => i.pedido_id === p.id);
    if (pItens.length > 0) {
      for (const item of pItens) {
        if ((item.nome_oficial || '').toLowerCase().includes('cbd')) {
          cbdCount += item.quantidade;
          isCBD = true;
          matchType = 'pedido_itens';
        }
      }
    } else if (typeof p.produto === 'string' && p.produto.startsWith('[')) {
      try {
        const arr = JSON.parse(p.produto);
        for (const item of arr) {
          if (item.produto_id === 'CBD_ID' || (item.nome_oficial || '').toLowerCase().includes('cbd')) {
            cbdCount += item.quantidade;
            isCBD = true;
            matchType = 'json_array';
          }
        }
      } catch (e) {}
    } else {
      const prodStr = typeof p.produto === 'string' ? p.produto.toLowerCase() : JSON.stringify(p.produto || {}).toLowerCase();
      const obsStr = (p.observacao || '').toLowerCase();
      if (prodStr.includes('cbd') || obsStr.includes('cbd')) {
        cbdCount += q;
        isCBD = true;
        matchType = 'direta';
      }
    }

    if (isCBD) {
      cbdOrders.push({
        data: p.data,
        id: p.id,
        produto: typeof p.produto === 'string' ? p.produto : JSON.stringify(p.produto),
        quantidade_col: p.quantidade,
        observacao: p.observacao,
        matchType
      });
    }
  }

  console.log(`ESTOQUE (Old Logic Simulation) COUNT FOR CBD: ${cbdCount}`);
  console.log(`\nOrders matching CBD:`);
  console.table(cbdOrders.map(o => ({
    id: o.id.split('-')[0],
    data: o.data,
    match: o.matchType,
    qtd: o.quantidade_col,
    produto: String(o.produto).substring(0, 40)
  })));

  // Output Sebastiao orders explicitly
  const seb = pedidos.filter(p => {
    const s = JSON.stringify(p).toLowerCase();
    return s.includes('sebastiao') || s.includes('sebastião');
  }).map(p => ({
     id: p.id.split('-')[0], date: p.data, qtd: p.quantidade, prod: JSON.stringify(p.produto).substring(0,40), obs: (p.observacao || '').substring(0,20)
  }));
  console.log("\nSEBASTIAO ORDERS:");
  console.table(seb);
}

run();

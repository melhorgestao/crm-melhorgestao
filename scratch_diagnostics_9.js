const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  const respPed = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?data=gte.2026-04-01&lt.2026-05-01&status_pedido=neq.cancelado&select=id,produto,quantidade`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const pedidos = await respPed.json();

  const respItens = await fetch(`${SUPABASE_URL}/rest/v1/pedido_itens?select=pedido_id,produto_id,quantidade`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const itens = await respItens.json();

  const CBD_ID = '4a8c827e-8bee-42f2-bf1e-edfdb8adf288';
  let totalSaida = 0;
  const analysis = [];

  for (const p of pedidos) {
    let pItens = itens.filter(i => i.pedido_id === p.id);
    let qty = 0;
    let source = '';

    if (pItens.length > 0) {
      const cbdItens = pItens.filter(i => i.produto_id === CBD_ID);
      qty = cbdItens.reduce((s, i) => s + i.quantidade, 0);
      source = 'pedido_itens';
      if (qty === 0) {
          // Check if CBD is in the JSON even if items exist
          if (typeof p.produto === 'string' && p.produto.includes(CBD_ID)) {
              source = 'IGNORED_JSON_BECAUSE_ITENS_EXIST';
          }
      }
    } else if (typeof p.produto === 'string' && p.produto.startsWith('[')) {
      try {
        const arr = JSON.parse(p.produto);
        const cbdItens = arr.filter(i => i.produto_id === CBD_ID);
        qty = cbdItens.reduce((s, i) => s + i.quantidade, 0);
        source = 'json_array';
      } catch (e) {}
    } else if (String(p.produto).toLowerCase().includes('cbd')) {
       qty = p.quantidade || 0;
       source = 'direta';
    }

    if (qty > 0 || source === 'IGNORED_JSON_BECAUSE_ITENS_EXIST') {
      totalSaida += qty;
      analysis.push({ id: p.id.split('-')[0], qty, source, p_qty: p.quantidade, p_prod: String(p.produto).substring(0,40) });
    }
  }

  console.log(`TOTAL SAIDA DETECTED FOR CBD: ${totalSaida}`);
  console.table(analysis);
}
run();

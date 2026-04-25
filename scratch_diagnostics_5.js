const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function run() {
  // 1. Search for contact "Sebastião"
  const respCont = await fetch(`${SUPABASE_URL}/rest/v1/contatos?nome=ilike.*sebastiao*&select=id,nome`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const contatos = await respCont.json();
  console.log("CONTACTS MATCHING SEBASTIAO:", contatos);

  if (contatos.length === 0) {
    console.log("No contact found with name Sebastião.");
  } else {
    const ids = contatos.map(c => c.id);
    // 2. Find orders for these contacts in April
    const respPed = await fetch(`${SUPABASE_URL}/rest/v1/pedidos?contato_id=in.(${ids.map(id => `"${id}"`).join(',')})&data=gte.2026-04-01&select=*,contatos(nome)`, {
      headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
    });
    const pedidos = await respPed.json();
    console.log("ORDERS FOR SEBASTIAO:");
    console.table(pedidos.map(p => ({
      id: p.id.split('-')[0],
      data: p.data,
      nome: p.contatos?.nome,
      qtd: p.quantidade,
      prod: String(p.produto).substring(0, 40),
      status: p.status_pedido,
      obs: p.observacao
    })));
  }

  // 3. Check for multiple CBD products
  const respProd = await fetch(`${SUPABASE_URL}/rest/v1/produtos?nome_oficial=ilike.*CBD*&select=id,nome_oficial,tag,ativo`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
  });
  const cbdProds = await respProd.json();
  console.log("\nCBD PRODUCTS IN DATABASE:");
  console.table(cbdProds);
}
run();

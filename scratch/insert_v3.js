const SUPABASE_URL = "https://epreaawpvxrpqqthcczu.supabase.co";
const KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzEyMzkwMiwiZXhwIjoyMDkyNjk5OTAyfQ.FQ-80rlCj0qp__UMoUaVa4jjvMDIPCe7emN61R_XV0Y";

async function run() {
  const instances = [
    {
      nome: "Instancia BASE",
      tipo: "base",
      numero_final: "0512",
      ativo: true,
      is_default_base: true,
      dono_tipo: "admin",
      acesso_kanban: "todos"
    },
    {
      nome: "Instancia ADS",
      tipo: "ads",
      numero_final: "2579",
      ativo: true,
      is_default_base: false,
      dono_tipo: "admin",
      acesso_kanban: "todos"
    }
  ];

  console.log("Sending request to insert with acesso_kanban...");
  const response = await fetch(`${SUPABASE_URL}/rest/v1/instancias`, {
    method: 'POST',
    headers: {
      'apikey': KEY,
      'Authorization': `Bearer ${KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation'
    },
    body: JSON.stringify(instances)
  });

  const text = await response.text();
  console.log("Status:", response.status);
  console.log("Body:", text);
}

run();

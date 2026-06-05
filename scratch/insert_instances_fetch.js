const SUPABASE_URL = "https://epreaawpvxrpqqthcczu.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzEyMzkwMiwiZXhwIjoyMDkyNjk5OTAyfQ.FQ-80rlCj0qp__UMoUaVa4jjvMDIPCe7emN61R_XV0Y";

async function run() {
  const instances = [
    {
      nome: "Instancia BASE",
      tipo: "base", // Normalizing to lowercase to match CHECK constraint
      numero_final: "0512",
      ativo: true,
      is_default_base: true,
      dono_tipo: "admin" // Normalizing to lowercase to match CHECK constraint
    },
    {
      nome: "Instancia ADS",
      tipo: "ads", // Normalizing to lowercase to match CHECK constraint
      numero_final: "2579",
      ativo: true,
      is_default_base: false,
      dono_tipo: "admin" // Normalizing to lowercase to match CHECK constraint
    }
  ];

  console.log("Sending request...");
  const response = await fetch(`${SUPABASE_URL}/rest/v1/instancias`, {
    method: 'POST',
    headers: {
      'apikey': SUPABASE_SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation'
    },
    body: JSON.stringify(instances)
  });

  const text = await response.text();
  console.log("Response status:", response.status);
  console.log("Response body:", text);
}

run();

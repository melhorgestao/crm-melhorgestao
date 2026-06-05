const SUPABASE_URL = "https://epreaawpvxrpqqthcczu.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzEyMzkwMiwiZXhwIjoyMDkyNjk5OTAyfQ.FQ-80rlCj0qp__UMoUaVa4jjvMDIPCe7emN61R_XV0Y";

async function run() {
  console.log("Checking columns of table instancias...");
  // We can't query information_schema directly via Postgrest usually, 
  // but we can try to do a select * and see the keys.
  
  const response = await fetch(`${SUPABASE_URL}/rest/v1/instancias?select=*&limit=1`, {
    method: 'GET',
    headers: {
      'apikey': SUPABASE_SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`
    }
  });

  const data = await response.json();
  console.log("Sample record:", data);
}

run();

const SUPABASE_URL = "https://epreaawpvxrpqqthcczu.supabase.co";
const KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzEyMzkwMiwiZXhwIjoyMDkyNjk5OTAyfQ.FQ-80rlCj0qp__UMoUaVa4jjvMDIPCe7emN61R_XV0Y";

async function run() {
  console.log("Fetching users from auth.users...");
  // Note: We access auth.users via the API if allowed, 
  // but usually we need to use the admin API or a direct DB query.
  // With service_role key, we can try to hit /auth/v1/admin/users
  
  const response = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: 'GET',
    headers: {
      'apikey': KEY,
      'Authorization': `Bearer ${KEY}`
    }
  });

  if (response.status !== 200) {
    console.error("Failed to fetch users:", response.status, await response.text());
    return;
  }

  const data = await response.json();
  console.log("Users found:", data.users.map(u => ({ id: u.id, email: u.email })));
}

run();

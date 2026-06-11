const URL_1 = "https://epreaawpvxrpqqthcczu.supabase.co";
const KEY_1 = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwcmVhYXdwdnhycHFxdGhjY3p1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzEyMzkwMiwiZXhwIjoyMDkyNjk5OTAyfQ.FQ-80rlCj0qp__UMoUaVa4jjvMDIPCe7emN61R_XV0Y";

const URL_2 = "https://seplijmbdrbfbtdmjubg.supabase.co";
const KEY_2 = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

async function check(url, key, label) {
  try {
    const resp = await fetch(`${url}/rest/v1/`, {
      headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
    });
    const schema = await resp.json();
    if (schema && schema.definitions && schema.definitions.contatos) {
      console.log(`[${label}] Schema properties:`);
      console.log(JSON.stringify(Object.keys(schema.definitions.contatos.properties), null, 2));
    } else {
      console.log(`[${label}] Could not fetch/find contatos: ${schema.message || 'unknown error'}`);
    }
  } catch (err) {
    console.error(`[${label}] Error:`, err.message);
  }
}

async function run() {
  await check(URL_1, KEY_1, "Env DB (epreaawpvxrpqqthcczu)");
  await check(URL_2, KEY_2, "Diagnostics DB (seplijmbdrbfbtdmjubg)");
}
run();

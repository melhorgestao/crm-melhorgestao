import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';

// Manual env parsing since we don't want to rely on dotenv
const envPath = path.join(process.cwd(), '.env');
const envContent = fs.readFileSync(envPath, 'utf8');
const env = {};
envContent.split('\n').forEach(line => {
  const trimmed = line.trim();
  const match = trimmed.match(/^([^=]+)=(?:"?)([^"\n]+)(?:"?)$/);
  if (match) {
    env[match[1]] = match[2].replace(/"/g, '');
  }
});

const supabaseUrl = env['SUPABASE_URL'];
const supabaseServiceRoleKey = env['SUPABASE_SERVICE_ROLE_KEY'];

console.log('URL:', supabaseUrl);
console.log('Key length:', supabaseServiceRoleKey ? supabaseServiceRoleKey.length : 'MISSING');

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false
  }
});

async function checkAndInsert() {
  console.log('Checking existing instances...');
  const { data: existing, error: checkError } = await supabase
    .from('instancias')
    .select('*');

  if (checkError) {
    console.error('Error checking instances:', checkError);
    return;
  }

  console.log('Current instances:', existing);

  const instances = [
    {
      nome: "Instancia BASE",
      tipo: "BASE",
      numero_final: "0512",
      ativo: true,
      is_default_base: true,
      dono_tipo: "ADMIN"
    },
    {
      nome: "Instancia ADS",
      tipo: "ADS",
      numero_final: "2579",
      ativo: true,
      is_default_base: false,
      dono_tipo: "ADMIN"
    }
  ];

  console.log('Inserting new instances...');
  const { data: inserted, error: insertError } = await supabase
    .from('instancias')
    .insert(instances)
    .select();

  if (insertError) {
    console.error('Error inserting instances:', insertError);
  } else {
    console.log('Instances inserted successfully:', inserted);
  }
}

checkAndInsert();

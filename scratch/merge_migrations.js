import fs from 'fs';
import path from 'path';

const migrationsDir = 'c:/Users/victo/santa-flor-crm/supabase/migrations';
const outputFile = 'c:/Users/victo/santa-flor-crm/full_schema.sql';

const files = fs.readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

let fullSql = '-- FULL SCHEMA EXPORT\n-- Generated on ' + new Date().toISOString() + '\n\n';

for (const file of files) {
    const content = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    fullSql += `-- MIGRATION: ${file}\n`;
    fullSql += content;
    fullSql += '\n\n';
}

fs.writeFileSync(outputFile, fullSql);
console.log(`Merged ${files.length} migrations into ${outputFile}`);

import fs from 'fs';
import path from 'path';

const migrationsDir = 'c:/Users/victo/santa-flor-crm/supabase/migrations';
const outputFile = 'c:/Users/victo/santa-flor-crm/full_schema_clean.sql';

const files = fs.readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

console.log(`Found ${files.length} migration files.`);

const components = {
    extensions: new Set(),
    sequences: new Set(),
    tables: {},
    alterations: [],
    functions: {},
    triggers: {}, // Keyed by table + name
    policies: {}, // Keyed by table + name
    rls: new Set(),
    indexes: [],
    initialization: []
};

files.forEach((file) => {
    let content = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    
    const statements = [];
    let current = '';
    let inDollarBlock = false;
    let dollarTag = '';

    const lines = content.split('\n');
    for (let line of lines) {
        current += line + '\n';
        
        const dollarMatch = line.match(/\$([a-zA-Z0-9_]*)\$/);
        if (dollarMatch) {
            if (!inDollarBlock) {
                inDollarBlock = true;
                dollarTag = dollarMatch[0];
            } else if (line.includes(dollarTag)) {
                inDollarBlock = false;
            }
        }

        if (!inDollarBlock && line.replace(/--.*$/, '').trim().endsWith(';')) {
            statements.push(current.trim());
            current = '';
        }
    }
    if (current.trim()) statements.push(current.trim());

    statements.forEach(stmt => {
        let cleanStmt = stmt.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '').trim();
        const lower = cleanStmt.toLowerCase();
        
        if (lower.startsWith('create extension')) {
            components.extensions.add(stmt);
        } else if (lower.startsWith('create sequence')) {
            components.sequences.add(stmt);
        } else if (lower.startsWith('create table')) {
            const match = cleanStmt.match(/create table (?:if not exists )?(?:public\.)?([a-z0-9_]+)/i);
            if (match) components.tables[match[1]] = stmt;
        } else if (lower.startsWith('create index') || lower.startsWith('create unique index')) {
            components.indexes.push(stmt);
        } else if (lower.startsWith('alter table')) {
            if (lower.includes('enable row level security')) {
                components.rls.add(stmt);
            } else if (/\b(add|drop|alter|owner)\b/i.test(cleanStmt)) {
                components.alterations.push(stmt);
            } else if (lower.includes('rename column')) {
                const match = cleanStmt.match(/alter\s+table\s+(?:public\.)?([a-z0-9_]+)\s+rename\s+column\s+([a-z0-9_]+)\s+to\s+([a-z0-9_]+)/i);
                if (match) {
                    const [_, table, oldCol, newCol] = match;
                    const safeRename = `DO $$ BEGIN IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = '${table}' AND column_name = '${oldCol}') AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = '${table}' AND column_name = '${newCol}') THEN ALTER TABLE public.${table} RENAME COLUMN ${oldCol} TO ${newCol}; END IF; END $$;`;
                    components.alterations.push(safeRename);
                } else {
                    components.alterations.push(stmt);
                }
            }
        } else if (lower.startsWith('create trigger')) {
            const match = cleanStmt.match(/create trigger\s+([a-z0-9_]+)\s+[\s\S]+?on\s+((?:[a-z0-9_]+\.)?[a-z0-9_]+)/i);
            if (match) {
                const name = match[1];
                let table = match[2];
                if (!table.includes('.')) table = `public.${table}`;
                components.triggers[`${table}:${name}`] = { name, table, stmt };
            }
        } else if (lower.startsWith('create policy')) {
            const match = cleanStmt.match(/create policy\s+"?([^"]+)"?\s+on\s+((?:[a-z0-9_]+\.)?[a-z0-9_]+)/i);
            if (match) {
                const name = match[1];
                let table = match[2];
                if (!table.includes('.')) table = `public.${table}`;
                components.policies[`${table}:${name}`] = { name, table, stmt };
            }
        } else if (lower.includes('create') && lower.includes('function')) {
            const match = cleanStmt.match(/function\s+(?:public\.)?([a-z0-9_]+)/i);
            if (match) {
                components.functions[match[1]] = stmt;
            }
        } else if (lower.startsWith('do $$') || lower.startsWith('do $body$')) {
            // Capture DO blocks and PATCH them if they contain unsafe RENAME
            let patchedStmt = stmt;
            const renameMatch = cleanStmt.match(/rename\s+column\s+([a-z0-9_]+)\s+to\s+([a-z0-9_]+)/i);
            const tableMatch = cleanStmt.match(/table_name\s*=\s*'([a-z0-9_]+)'/i) || cleanStmt.match(/alter\s+table\s+(?:public\.)?([a-z0-9_]+)/i);
            
            if (renameMatch && tableMatch) {
                const [_, oldCol, newCol] = renameMatch;
                const table = tableMatch[1];
                // Injetar a verificação de não existência da nova coluna se não houver
                if (!lower.includes(`not exists`) || !lower.includes(newCol)) {
                    patchedStmt = stmt.replace(
                        new RegExp(`IF\\s+EXISTS\\s*\\(SELECT\\s+1\\s+FROM\\s+information_schema\\.columns\\s+WHERE\\s+table_name\\s*=\\s*'${table}'\\s+AND\\s+column_name\\s*=\\s*'${oldCol}'\\)\\s+THEN`, 'i'),
                        `IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = '${table}' AND column_name = '${oldCol}') AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = '${table}' AND column_name = '${newCol}') THEN`
                    );
                }
            }
            
            // PATCH: If DO block contains UPDATE, use dynamic SQL EXECUTE to avoid compilation errors
            if (lower.includes('update ') && !lower.includes('execute')) {
                // Find the UPDATE statement part
                const updateRegex = /UPDATE\s+[\s\S]+?;/i;
                const updatePart = patchedStmt.match(updateRegex);
                if (updatePart) {
                    const originalUpdate = updatePart[0];
                    // Escape single quotes for EXECUTE
                    const escapedUpdate = originalUpdate.replace(/'/g, "''");
                    patchedStmt = patchedStmt.replace(originalUpdate, `EXECUTE '${escapedUpdate}';`);
                }
            }
            
            if (lower.includes('alter table')) {
                components.alterations.push(patchedStmt);
            } else {
                components.initialization.push(patchedStmt);
            }
        } else if (lower.startsWith('select setval')) {
            // FIX: value 0 is out of bounds for sequence
            // Replace COALESCE(..., 0) with COALESCE(..., 1), false to be safe
            let patchedStmt = stmt;
            if (stmt.includes('0')) {
                patchedStmt = stmt.replace(/COALESCE\(([^,]+),\s*0\)/gi, "COALESCE($1, 1)");
                if (!patchedStmt.toLowerCase().includes('false')) {
                   patchedStmt = patchedStmt.replace(/\);$/, ", false);");
                }
            }
            components.initialization.push(patchedStmt);
        }
    });
});

// Sort alterations: ADD COLUMN statements first
const sortedAlterations = [...components.alterations].sort((a, b) => {
    const aAdd = a.toLowerCase().includes('add column') ? 0 : 1;
    const bAdd = b.toLowerCase().includes('add column') ? 0 : 1;
    return aAdd - bAdd;
});

const policySql = Object.values(components.policies).map(p => {
    return `DROP POLICY IF EXISTS "${p.name}" ON ${p.table};\n${p.stmt}`;
}).join('\n\n');

const triggerSql = Object.values(components.triggers).map(t => {
    return `DROP TRIGGER IF EXISTS "${t.name}" ON ${t.table};\n${t.stmt}`;
}).join('\n\n');

const finalSql = `-- CLEAN SCHEMA EXPORT (Option B)
-- Generated on ${new Date().toISOString()}

-- 0. Cleanup & Environment
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
SET search_path = public, auth, extensions;

-- 1. Extensions & Sequences
${Array.from(components.extensions).join('\n')}
${Array.from(components.sequences).join('\n')}

-- 2. Tables
${Object.values(components.tables).join('\n\n')}

-- 3. Alterations (Columns & Constraints)
${sortedAlterations.join('\n\n')}

-- 4. Indexes
${components.indexes.join('\n\n')}

-- 5. Functions & RPCs
${Object.values(components.functions).join('\n\n')}

-- 6. RLS & Policies
${Array.from(components.rls).join('\n')}

${policySql}

-- 7. Triggers
${triggerSql}

-- 8. Post-Structure Initialization (setval, etc)
${components.initialization.join('\n\n')}

-- Final configuration
SET search_path = public, auth, extensions;
`;

fs.writeFileSync(outputFile, finalSql);
console.log(`Generated ${outputFile}`);
console.log(`Summary:
- Extensions: ${components.extensions.size}
- Sequences: ${components.sequences.size}
- Tables: ${Object.keys(components.tables).length}
- Alterations: ${components.alterations.length}
- Functions: ${Object.keys(components.functions).length}
- Triggers: ${Object.keys(components.triggers).length}
- Policies: ${Object.keys(components.policies).length}
`);

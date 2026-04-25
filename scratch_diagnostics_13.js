const SUPABASE_URL = "https://seplijmbdrbfbtdmjubg.supabase.co";
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcGxpam1iZHJiZmJ0ZG1qdWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3NTYyNDksImV4cCI6MjA5MDMzMjI0OX0.g3tbIEoTLAehBp98Oq33C_ud0OSe7bH_6P1tJluN644";

const query = `
-- 1. GARANTIR A PERFORMANCE (Snapshot)
CREATE OR REPLACE FUNCTION public.atualizar_estoque_snapshot()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM public.estoque_snapshot;
    INSERT INTO public.estoque_snapshot (produto_id, uf, entrada, saida, saldo, last_updated)
    SELECT 
        m.produto_id,
        LEFT(UPPER(TRIM(COALESCE(m.uf_origem, 'SP'))), 2) as uff,
        SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END)::int as qtd_ent,
        SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END)::int as qtd_sai,
        (SUM(CASE WHEN m.tipo = 'entrada' THEN m.quantidade ELSE 0 END) - SUM(CASE WHEN m.tipo = 'saida' THEN m.quantidade ELSE 0 END))::int as saldo_final,
        NOW()
    FROM public.estoque_movimentacoes m
    GROUP BY m.produto_id, uff;
END;
$$;

-- 2. UNIFICAR CARDS COM A LISTA
CREATE OR REPLACE FUNCTION public.get_estoque_completo()
RETURNS TABLE(prod_id uuid, prod_nome text, estado text, entrada int, saida int, saldo int)
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.nome_oficial, m.uf, m.entrada::int, m.saida::int, m.saldo::int
  FROM public.estoque_snapshot m
  JOIN public.produtos p ON p.id = m.produto_id
  ORDER BY p.nome_oficial, m.uf;
END;
$$;

SELECT public.atualizar_estoque_snapshot();
`;

async function run() {
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/`, {
    method: 'POST',
    headers: {
      'apikey': SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'params=single-object'
    },
    body: JSON.stringify({ query })
  });
  console.log('SQL Execution Status:', resp.status);
  if (!resp.ok) console.log(await resp.text());
}
run();

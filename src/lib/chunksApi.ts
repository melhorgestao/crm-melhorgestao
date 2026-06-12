/**
 * Helpers pra knowledge_chunks — chamada das edge functions:
 *  - upsert-knowledge-chunk (gera embedding + INSERT/UPDATE)
 *  - buscar-conhecimento-agent (preview RAG)
 */
import { supabase } from '@/integrations/supabase/client';

export type ChunkCategoria = 'tabela' | 'sobre_produtos' | 'bonus' | 'argumentos_venda' | 'faq';

export const CATEGORIAS: Array<{ key: ChunkCategoria; label: string; emoji: string; descricao: string }> = [
  { key: 'tabela',           emoji: '📋', label: 'Tabela',           descricao: 'Nome oficial do produto + preço atual' },
  { key: 'sobre_produtos',   emoji: '🌿', label: 'Sobre Produtos',   descricao: 'Descrição ampla, modo de uso, características' },
  { key: 'bonus',            emoji: '🎁', label: 'Bônus',            descricao: 'Regras de bônus (ex: 4 produtos = +1 grátis)' },
  { key: 'argumentos_venda', emoji: '💪', label: 'Argumentos',       descricao: 'Benefícios, custo-benefício, diferenciais' },
  { key: 'faq',              emoji: '❓', label: 'FAQ',              descricao: 'Interações, golpes, efeitos colaterais, dúvidas comuns' },
];

export interface ChunkRow {
  id: string;
  titulo: string;
  categoria: ChunkCategoria;
  conteudo: string;
  embedding: number[] | null;
  ativo: boolean;
  observacao: string | null;
  created_at: string;
  updated_at: string;
}

export async function upsertChunk(payload: {
  id?: string;
  titulo: string;
  categoria: ChunkCategoria;
  conteudo: string;
  observacao?: string | null;
  ativo?: boolean;
}): Promise<{ ok: boolean; id?: string; error?: string }> {
  const { data, error } = await supabase.functions.invoke('upsert-knowledge-chunk', {
    body: payload,
  });
  if (error) return { ok: false, error: error.message };
  if ((data as any)?.error) return { ok: false, error: (data as any).error };
  return { ok: true, id: (data as any).id };
}

export interface BuscaResult {
  titulo: string;
  categoria: string;
  conteudo: string;
  similaridade: number;
}

export async function buscarPreview(pergunta: string, categoria?: ChunkCategoria | null, limit = 5): Promise<{
  ok: boolean;
  chunks?: BuscaResult[];
  error?: string;
}> {
  const { data, error } = await supabase.functions.invoke('buscar-conhecimento-agent', {
    body: { pergunta, categoria: categoria ?? null, limit },
  });
  if (error) return { ok: false, error: error.message };
  if ((data as any)?.error) return { ok: false, error: (data as any).error };
  return { ok: true, chunks: ((data as any)?.chunks || []) as BuscaResult[] };
}

export async function toggleChunkAtivo(id: string, ativo: boolean): Promise<boolean> {
  const { error } = await supabase.from('knowledge_chunks').update({ ativo, updated_at: new Date().toISOString() }).eq('id', id);
  return !error;
}

export async function deleteChunk(id: string): Promise<boolean> {
  const { error } = await supabase.from('knowledge_chunks').delete().eq('id', id);
  return !error;
}

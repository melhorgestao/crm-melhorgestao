import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { Plus, Pencil, Trash2, FlaskConical, AlertTriangle, RefreshCw } from 'lucide-react';
import { CATEGORIAS, deleteChunk, toggleChunkAtivo, type ChunkCategoria, type ChunkRow } from '@/lib/chunksApi';
import { ChunkEditorModal } from '@/components/dados-agents/ChunkEditorModal';
import { TestarBuscaModal } from '@/components/dados-agents/TestarBuscaModal';

export default function DadosAgentsPage() {
  const { isAdmin } = useAuth();
  const qc = useQueryClient();
  const [tab, setTab] = useState<ChunkCategoria>('tabela');
  const [search, setSearch] = useState('');
  const [editorOpen, setEditorOpen] = useState(false);
  const [editorChunk, setEditorChunk] = useState<ChunkRow | null>(null);
  const [testarOpen, setTestarOpen] = useState(false);
  const [regenerando, setRegenerando] = useState(false);
  const [novoCategoriaOpen, setNovoCategoriaOpen] = useState(false);
  const [novoCategoria, setNovoCategoria] = useState<ChunkCategoria>('sobre_produtos');

  const regenerarChunksTabela = async () => {
    if (!confirm('Regenerar chunks da Tabela a partir de produtos?\n\n• 1 chunk por produto ativo (com slug+emoji)\n• Atualiza embedding de todos\n• Custo: ~$0.001 OpenAI\n\nProsseguir?')) return;
    setRegenerando(true);
    const { data, error } = await supabase.functions.invoke('regenerar-chunks-tabela', { body: {} });
    setRegenerando(false);
    if (error) { toast.error(`Erro: ${error.message}`); return; }
    const d = data as any;
    if (d?.error) { toast.error(`Erro: ${d.error}`); return; }
    toast.success(`✅ ${d.criados} criados · ${d.atualizados} atualizados · ${d.desativados} desativados (sem produto)`);
    qc.invalidateQueries({ queryKey: ['chunks_categoria'] });
    qc.invalidateQueries({ queryKey: ['chunks_count'] });
  };

  // Contagem por categoria
  const { data: counts } = useQuery({
    queryKey: ['chunks_count'],
    enabled: isAdmin,
    queryFn: async () => {
      const { data } = await supabase
        .from('knowledge_chunks')
        .select('categoria', { count: 'exact' });
      const map: Record<string, number> = {};
      (data || []).forEach((r: any) => {
        map[r.categoria] = (map[r.categoria] || 0) + 1;
      });
      return map;
    },
    refetchInterval: 60_000,
  });

  // Chunks da categoria ativa
  const { data: chunks, isLoading } = useQuery({
    queryKey: ['chunks_categoria', tab, search],
    enabled: isAdmin,
    queryFn: async () => {
      let q = supabase
        .from('knowledge_chunks')
        .select('id, titulo, categoria, conteudo, embedding, ativo, observacao, created_at, updated_at')
        .eq('categoria', tab)
        .order('updated_at', { ascending: false });
      if (search.trim()) {
        const s = `%${search.trim()}%`;
        q = q.or(`titulo.ilike.${s},conteudo.ilike.${s}`);
      }
      const { data, error } = await q;
      if (error) throw error;
      return (data || []) as any[] as ChunkRow[];
    },
  });

  if (!isAdmin) {
    return <div className="text-center py-12 text-muted-foreground">Acesso restrito a administradores.</div>;
  }

  // FAB sempre abre dropdown de categoria (exceto Catálogo, que é auto-gerado)
  const openNew = () => {
    const def = (CATEGORIAS.find(c => c.key === tab && !c.systemManaged)?.key) || 'sobre_produtos';
    setNovoCategoria(def);
    setNovoCategoriaOpen(true);
  };
  const confirmarNovoChunk = () => {
    setNovoCategoriaOpen(false);
    setEditorChunk(null);
    // troca a tab pra refletir onde o chunk vai aparecer depois
    if (tab !== novoCategoria) setTab(novoCategoria);
    setEditorOpen(true);
  };
  const openEdit = (c: ChunkRow) => { setEditorChunk(c); setEditorOpen(true); };

  const handleDelete = async (c: ChunkRow) => {
    if (!confirm(`Excluir "${c.titulo}"? Não pode desfazer.`)) return;
    const ok = await deleteChunk(c.id);
    if (!ok) { toast.error('Erro ao excluir'); return; }
    toast.success('Excluído');
    qc.invalidateQueries({ queryKey: ['chunks_categoria'] });
    qc.invalidateQueries({ queryKey: ['chunks_count'] });
  };

  const handleToggle = async (c: ChunkRow, novoAtivo: boolean) => {
    const ok = await toggleChunkAtivo(c.id, novoAtivo);
    if (!ok) { toast.error('Erro ao alternar'); return; }
    qc.invalidateQueries({ queryKey: ['chunks_categoria'] });
  };

  const totalChunks = Object.values(counts || {}).reduce((a, b) => a + b, 0);

  return (
    <div className="space-y-4 pb-24">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div>
          <h1 className="text-2xl font-bold">🤖 Dados dos Agents</h1>
          <p className="text-xs text-muted-foreground">
            {totalChunks} chunk{totalChunks !== 1 ? 's' : ''} no total · agentes consultam via busca semântica
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={() => setTestarOpen(true)}>
          <FlaskConical className="w-4 h-4 mr-1" /> Testar busca
        </Button>
      </div>

      {/* Tabs */}
      <Tabs value={tab} onValueChange={(v) => setTab(v as ChunkCategoria)}>
        <TabsList className="grid grid-cols-5 w-full">
          {CATEGORIAS.map(c => (
            <TabsTrigger key={c.key} value={c.key} className="text-xs">
              {c.emoji} {c.label}
              {!!counts?.[c.key] && (
                <Badge variant="outline" className="text-[9px] ml-1.5 px-1">{counts[c.key]}</Badge>
              )}
            </TabsTrigger>
          ))}
        </TabsList>

        {CATEGORIAS.map(c => (
          <TabsContent key={c.key} value={c.key} className="space-y-3 mt-4">
            <div className="text-xs text-muted-foreground border-l-2 border-muted pl-3">
              {c.descricao}
            </div>

            {c.key === 'tabela' && (
              <div className="border rounded-xl bg-amber-50 dark:bg-amber-950/20 p-3 flex items-center justify-between gap-3 flex-wrap">
                <p className="text-[11px] text-amber-800 dark:text-amber-200 leading-snug">
                  ⚙️ Catálogo é gerenciado em <strong>Estoque → Cadastro</strong>. Ao mudar preço/nome, clique pra regerar embeddings.
                </p>
                <Button
                  variant="outline" size="sm"
                  className="bg-white dark:bg-background shrink-0"
                  onClick={regenerarChunksTabela}
                  disabled={regenerando}
                >
                  <RefreshCw className={`w-3.5 h-3.5 mr-1.5 ${regenerando ? 'animate-spin' : ''}`} />
                  {regenerando ? 'Sincronizando…' : 'Sincronizar'}
                </Button>
              </div>
            )}

            <Input
              placeholder="Buscar por título ou conteúdo..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="max-w-sm"
            />

            {isLoading ? (
              <div className="space-y-2">
                {Array(3).fill(0).map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)}
              </div>
            ) : (chunks?.length || 0) === 0 ? (
              <div className="text-center py-12 bg-muted/20 rounded-2xl border-2 border-dashed text-muted-foreground">
                <p>Nenhum chunk em <strong>{c.emoji} {c.label}</strong></p>
                <Button variant="link" onClick={openNew}>+ Criar primeiro</Button>
              </div>
            ) : (
              <div className="space-y-2">
                {chunks!.map(chunk => (
                  <div key={chunk.id} className={`border rounded-xl p-3 ${!chunk.ativo ? 'opacity-50' : ''}`}>
                    <div className="flex items-start justify-between gap-2 mb-1">
                      <div className="flex items-center gap-2 min-w-0 flex-1">
                        <span className="font-semibold truncate">{chunk.titulo}</span>
                        {!chunk.embedding && (
                          <span title="Sem embedding — RAG não vai retornar este chunk">
                            <AlertTriangle className="w-3.5 h-3.5 text-amber-500" />
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-1 shrink-0">
                        <Switch checked={chunk.ativo} onCheckedChange={(v) => handleToggle(chunk, v)} />
                        {!c.systemManaged && (
                          <>
                            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openEdit(chunk)}>
                              <Pencil className="w-3.5 h-3.5" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleDelete(chunk)}>
                              <Trash2 className="w-3.5 h-3.5" />
                            </Button>
                          </>
                        )}
                      </div>
                    </div>
                    <p className="text-xs whitespace-pre-wrap text-muted-foreground line-clamp-3 font-mono">{chunk.conteudo}</p>
                    {chunk.observacao && (
                      <p className="text-[10px] text-amber-700 dark:text-amber-400 mt-1">📌 {chunk.observacao}</p>
                    )}
                  </div>
                ))}
              </div>
            )}
          </TabsContent>
        ))}
      </Tabs>

      {/* FAB */}
      <Button
        onClick={openNew}
        className="fixed bottom-6 right-6 rounded-full h-14 w-14 shadow-lg bg-sf-green hover:bg-sf-green/90 text-primary-foreground z-50"
        size="icon"
      >
        <Plus className="w-6 h-6" />
      </Button>

      {/* Dropdown de categoria ao clicar no FAB */}
      <Dialog open={novoCategoriaOpen} onOpenChange={setNovoCategoriaOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Novo chunk</DialogTitle>
            <DialogDescription>Em qual seção?</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 pt-2">
            <Select value={novoCategoria} onValueChange={(v) => setNovoCategoria(v as ChunkCategoria)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {CATEGORIAS.filter(c => !c.systemManaged).map(c => (
                  <SelectItem key={c.key} value={c.key}>
                    {c.emoji} {c.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-[11px] text-muted-foreground">
              📋 Catálogo não aparece — é gerenciado em Estoque → Cadastro.
            </p>
            <div className="flex gap-2 pt-1">
              <Button variant="outline" className="flex-1" onClick={() => setNovoCategoriaOpen(false)}>Cancelar</Button>
              <Button className="flex-1 bg-sf-green hover:bg-sf-green/90" onClick={confirmarNovoChunk}>Continuar</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ChunkEditorModal
        open={editorOpen}
        onClose={() => setEditorOpen(false)}
        categoria={tab}
        chunk={editorChunk}
      />
      <TestarBuscaModal
        open={testarOpen}
        onClose={() => setTestarOpen(false)}
        categoriaPadrao={tab}
      />
    </div>
  );
}

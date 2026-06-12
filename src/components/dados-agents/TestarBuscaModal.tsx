import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { Loader2, Search, Sparkles } from 'lucide-react';
import { buscarPreview, CATEGORIAS, type ChunkCategoria, type BuscaResult } from '@/lib/chunksApi';

interface Props {
  open: boolean;
  onClose: () => void;
  categoriaPadrao?: ChunkCategoria | null;
}

export function TestarBuscaModal({ open, onClose, categoriaPadrao }: Props) {
  const [pergunta, setPergunta] = useState('');
  const [categoria, setCategoria] = useState<string>(categoriaPadrao || 'todas');
  const [searching, setSearching] = useState(false);
  const [resultados, setResultados] = useState<BuscaResult[]>([]);

  const handleSearch = async () => {
    if (!pergunta.trim()) { toast.info('Digite uma pergunta pra testar'); return; }
    setSearching(true);
    setResultados([]);
    const cat = categoria === 'todas' ? null : (categoria as ChunkCategoria);
    const r = await buscarPreview(pergunta, cat, 5);
    setSearching(false);
    if (!r.ok) { toast.error(r.error || 'Falhou'); return; }
    setResultados(r.chunks || []);
    if ((r.chunks || []).length === 0) toast.info('Nenhum chunk relevante encontrado');
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>🧪 Testar busca RAG</DialogTitle>
          <DialogDescription>
            Simula o que o agente faria quando consultar um chunk. Mesma RPC, mesma similaridade cosine.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1">
            <Label className="text-xs">Pergunta (como o cliente perguntaria)</Label>
            <Input
              value={pergunta}
              onChange={e => setPergunta(e.target.value)}
              placeholder="ex: quanto custa a calêndula?"
              onKeyDown={(e) => { if (e.key === 'Enter') handleSearch(); }}
            />
          </div>

          <div className="space-y-1">
            <Label className="text-xs">Categoria (opcional)</Label>
            <Select value={categoria} onValueChange={setCategoria}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="todas">Todas categorias</SelectItem>
                {CATEGORIAS.map(c => (
                  <SelectItem key={c.key} value={c.key}>{c.emoji} {c.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <Button
            onClick={handleSearch}
            disabled={searching}
            className="w-full bg-sf-green hover:bg-sf-green/90"
          >
            {searching ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Search className="w-4 h-4 mr-2" />}
            Buscar
          </Button>

          {resultados.length > 0 && (
            <section className="space-y-2">
              <p className="text-xs uppercase text-muted-foreground tracking-wide flex items-center gap-1.5">
                <Sparkles className="w-3 h-3" /> Top {resultados.length} resultados (mais relevantes primeiro)
              </p>
              {resultados.map((r, idx) => {
                const meta = CATEGORIAS.find(c => c.key === r.categoria);
                const simPct = (r.similaridade * 100).toFixed(0);
                const simColor = r.similaridade > 0.75 ? 'bg-sf-green text-white' : r.similaridade > 0.5 ? 'bg-amber-500 text-white' : 'bg-muted text-muted-foreground';
                return (
                  <div key={idx} className="border rounded-lg p-3 space-y-1.5">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-[10px] text-muted-foreground font-mono">#{idx + 1}</span>
                        <Badge variant="outline" className="text-[10px]">
                          {meta?.emoji} {meta?.label}
                        </Badge>
                        <span className="font-semibold text-sm">{r.titulo}</span>
                      </div>
                      <Badge className={`text-[10px] ${simColor}`}>{simPct}% match</Badge>
                    </div>
                    <p className="text-xs whitespace-pre-wrap text-muted-foreground">{r.conteudo}</p>
                  </div>
                );
              })}
            </section>
          )}

          <Button variant="outline" className="w-full" onClick={onClose}>Fechar</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

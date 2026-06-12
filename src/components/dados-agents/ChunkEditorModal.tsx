import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { toast } from 'sonner';
import { Loader2, Sparkles } from 'lucide-react';
import { upsertChunk, type ChunkRow, type ChunkCategoria, CATEGORIAS } from '@/lib/chunksApi';

interface Props {
  open: boolean;
  onClose: () => void;
  categoria: ChunkCategoria;
  chunk: ChunkRow | null;
}

export function ChunkEditorModal({ open, onClose, categoria, chunk }: Props) {
  const qc = useQueryClient();
  const [titulo, setTitulo] = useState('');
  const [conteudo, setConteudo] = useState('');
  const [observacao, setObservacao] = useState('');
  const [ativo, setAtivo] = useState(true);
  const [saving, setSaving] = useState(false);

  const meta = CATEGORIAS.find(c => c.key === categoria)!;

  useEffect(() => {
    if (!open) return;
    if (chunk) {
      setTitulo(chunk.titulo);
      setConteudo(chunk.conteudo);
      setObservacao(chunk.observacao || '');
      setAtivo(chunk.ativo);
    } else {
      setTitulo('');
      setConteudo('');
      setObservacao('');
      setAtivo(true);
    }
  }, [open, chunk]);

  const handleSave = async () => {
    if (!titulo.trim() || !conteudo.trim()) {
      toast.error('Título e conteúdo obrigatórios');
      return;
    }
    setSaving(true);
    const r = await upsertChunk({
      id: chunk?.id,
      titulo,
      categoria,
      conteudo,
      observacao,
      ativo,
    });
    setSaving(false);
    if (!r.ok) { toast.error(r.error || 'Erro ao salvar'); return; }
    toast.success(chunk ? 'Chunk atualizado + embedding regenerado' : 'Chunk criado + embedding gerado');
    qc.invalidateQueries({ queryKey: ['chunks_categoria'] });
    qc.invalidateQueries({ queryKey: ['chunks_count'] });
    onClose();
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{chunk ? 'Editar chunk' : 'Novo chunk'} — {meta.emoji} {meta.label}</DialogTitle>
          <DialogDescription>{meta.descricao}</DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1">
            <Label className="text-xs">Título</Label>
            <Input
              value={titulo}
              onChange={e => setTitulo(e.target.value)}
              placeholder={
                categoria === 'tabela' ? 'ex: Cápsula Calêndula 60' :
                categoria === 'sobre_produtos' ? 'ex: Como tomar Calêndula' :
                categoria === 'bonus' ? 'ex: 4 produtos = +1 grátis' :
                categoria === 'argumentos_venda' ? 'ex: Por que escolher Santa Flor' :
                'ex: Interações medicamentosas'
              }
            />
          </div>

          <div className="space-y-1">
            <div className="flex items-center justify-between">
              <Label className="text-xs">Conteúdo</Label>
              <span className="text-[10px] text-muted-foreground tabular-nums">{conteudo.length} chars</span>
            </div>
            <Textarea
              value={conteudo}
              onChange={e => setConteudo(e.target.value)}
              rows={10}
              placeholder="Texto que o agente vai consultar quando o cliente perguntar..."
              className="text-sm"
            />
            <p className="text-[10px] text-muted-foreground">
              Tenta ser direto e completo — quanto mais natural, melhor a busca semântica.
            </p>
          </div>

          <div className="space-y-1">
            <Label className="text-xs">Observação interna (opcional)</Label>
            <Input
              value={observacao}
              onChange={e => setObservacao(e.target.value)}
              placeholder="ex: revisar até dia 30; preço promocional"
            />
          </div>

          <label className="flex items-center gap-2 text-sm cursor-pointer">
            <Checkbox checked={ativo} onCheckedChange={v => setAtivo(!!v)} />
            <span>Ativo (entra no RAG)</span>
          </label>

          <div className="flex items-center gap-1.5 text-xs text-muted-foreground bg-muted/40 p-2 rounded">
            <Sparkles className="w-3.5 h-3.5 shrink-0" />
            <span>Ao salvar, o embedding é regenerado automaticamente via OpenAI.</span>
          </div>

          <div className="flex gap-2 pt-2">
            <Button variant="outline" className="flex-1" onClick={onClose}>Cancelar</Button>
            <Button className="flex-1 bg-sf-green hover:bg-sf-green/90" onClick={handleSave} disabled={saving}>
              {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
              {chunk ? 'Salvar' : 'Criar'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

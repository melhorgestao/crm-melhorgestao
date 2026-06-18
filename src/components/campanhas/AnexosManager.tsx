/**
 * Gerencia anexos da campanha (1..N).
 * - Lista anexos ativos/inativos
 * - Upload novo (vai pro bucket TabelaOferta via storageUpload)
 * - Toggle ativo/inativo
 * - Remover
 * Workflow n8n: escolhe_template_v2 rotaciona anexo independente do template.
 */
import { useState, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { toast } from 'sonner';
import { Loader2, Upload, X, Image as ImageIcon, FileText, Video, AudioLines } from 'lucide-react';
import { uploadAnexo, removeAnexo, type AnexoTipo } from '@/lib/storageUpload';

interface AnexoRow {
  id: string;
  campanha_id: string;
  url: string;
  tipo: AnexoTipo;
  ordem: number;
  ativo: boolean;
  observacao: string | null;
}

const ICON: Record<AnexoTipo, any> = {
  image: ImageIcon, video: Video, audio: AudioLines, document: FileText,
};

interface Props {
  campanhaId: string;
}

export function AnexosManager({ campanhaId }: Props) {
  const [uploading, setUploading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const { data: anexos = [], refetch } = useQuery({
    queryKey: ['campanha_anexos', campanhaId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('campanha_anexos')
        .select('id, campanha_id, url, tipo, ordem, ativo, observacao')
        .eq('campanha_id', campanhaId)
        .order('ordem', { ascending: true });
      if (error) throw error;
      return (data || []) as AnexoRow[];
    },
    enabled: !!campanhaId,
  });

  const handleFile = async (file: File) => {
    if (file.size > 16 * 1024 * 1024) { toast.error('Máx 16 MB'); return; }
    setUploading(true);
    const r = await uploadAnexo(file);
    if (!r.ok) { setUploading(false); toast.error('Upload falhou: ' + r.error); return; }
    const { error } = await supabase.from('campanha_anexos').insert({
      campanha_id: campanhaId,
      url: r.url!,
      tipo: r.tipo!,
      ordem: anexos.length,
      ativo: true,
    });
    setUploading(false);
    if (error) { toast.error('Salvar falhou: ' + error.message); return; }
    toast.success('Anexo adicionado');
    refetch();
  };

  const toggleAtivo = async (a: AnexoRow) => {
    await supabase.from('campanha_anexos').update({ ativo: !a.ativo }).eq('id', a.id);
    refetch();
  };

  const updateOrdem = async (a: AnexoRow, ordem: number) => {
    await supabase.from('campanha_anexos').update({ ordem }).eq('id', a.id);
    refetch();
  };

  const handleRemove = async (a: AnexoRow) => {
    if (!confirm('Remover este anexo da campanha?')) return;
    await removeAnexo(a.url);
    await supabase.from('campanha_anexos').delete().eq('id', a.id);
    toast.success('Anexo removido');
    refetch();
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs font-medium uppercase text-muted-foreground tracking-wide">Anexos</p>
          <p className="text-[10px] text-muted-foreground">
            {anexos.length === 0
              ? 'Sem anexos — envios saem só com texto.'
              : `${anexos.filter(a => a.ativo).length}/${anexos.length} ativos — rotação determinística por contato.`}
          </p>
        </div>
        <Button
          size="sm" variant="outline" type="button"
          disabled={uploading}
          onClick={() => inputRef.current?.click()}
        >
          {uploading ? <Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" /> : <Upload className="w-3.5 h-3.5 mr-1" />}
          {uploading ? 'Enviando…' : '+ Novo anexo'}
        </Button>
        <input
          ref={inputRef} type="file" className="hidden"
          accept="image/*,video/*,audio/*,application/pdf"
          onChange={(e) => { const f = e.target.files?.[0]; if (f) handleFile(f); e.target.value = ''; }}
        />
      </div>

      <div className="space-y-2">
        {anexos.length === 0 && (
          <p className="text-xs text-muted-foreground italic px-2 py-3 text-center border border-dashed rounded">
            Nenhum anexo cadastrado. Clique em "+ Novo anexo" pra adicionar.
          </p>
        )}
        {anexos.map(a => {
          const Icon = ICON[a.tipo];
          return (
            <div key={a.id} className="border rounded-lg p-2 bg-muted/30 flex items-center gap-2">
              {a.tipo === 'image' ? (
                <img src={a.url} alt="anexo" className="w-14 h-14 object-cover rounded" />
              ) : (
                <div className="w-14 h-14 rounded bg-background border flex items-center justify-center">
                  <Icon className="w-5 h-5 text-muted-foreground" />
                </div>
              )}
              <div className="flex-1 min-w-0">
                <p className="text-xs font-medium capitalize">{a.tipo}</p>
                <a href={a.url} target="_blank" rel="noopener noreferrer" className="text-[10px] text-muted-foreground hover:underline truncate block">
                  {a.url.split('/').pop()}
                </a>
              </div>
              <div className="flex items-center gap-1">
                <Input
                  type="number" value={a.ordem}
                  onChange={(e) => updateOrdem(a, parseInt(e.target.value) || 0)}
                  className="w-14 h-8 text-xs"
                  title="ordem"
                />
                <Switch checked={a.ativo} onCheckedChange={() => toggleAtivo(a)} />
                <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleRemove(a)}>
                  <X className="w-4 h-4" />
                </Button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

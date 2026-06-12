import { useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { Loader2, Upload, X, Image as ImageIcon, FileText, Video, AudioLines } from 'lucide-react';
import { uploadAnexo, removeAnexo, type AnexoTipo } from '@/lib/storageUpload';
import { toast } from 'sonner';

interface Props {
  url: string | null;
  tipo: AnexoTipo | null;
  onChange: (url: string | null, tipo: AnexoTipo | null) => void;
}

const ICON: Record<AnexoTipo, any> = {
  image: ImageIcon,
  video: Video,
  audio: AudioLines,
  document: FileText,
};

export function AnexoUpload({ url, tipo, onChange }: Props) {
  const [uploading, setUploading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleFile = async (file: File) => {
    if (file.size > 16 * 1024 * 1024) {
      toast.error('Anexo deve ter no máximo 16 MB');
      return;
    }
    setUploading(true);
    const r = await uploadAnexo(file);
    setUploading(false);
    if (!r.ok) { toast.error('Upload falhou: ' + r.error); return; }
    if (url) await removeAnexo(url); // descarta anexo antigo
    onChange(r.url!, r.tipo!);
    toast.success('Anexo enviado');
  };

  const handleRemove = async () => {
    if (!url) return;
    if (!confirm('Remover anexo deste template?')) return;
    await removeAnexo(url);
    onChange(null, null);
  };

  if (url && tipo) {
    const Icon = ICON[tipo];
    return (
      <div className="border rounded-lg p-3 bg-muted/30">
        <div className="flex items-start gap-3">
          {tipo === 'image' ? (
            <img src={url} alt="anexo" className="w-16 h-16 object-cover rounded" />
          ) : (
            <div className="w-16 h-16 rounded bg-background border flex items-center justify-center">
              <Icon className="w-6 h-6 text-muted-foreground" />
            </div>
          )}
          <div className="flex-1 min-w-0">
            <p className="text-xs font-medium capitalize">{tipo}</p>
            <a href={url} target="_blank" rel="noopener noreferrer" className="text-[10px] text-muted-foreground hover:underline truncate block">
              {url.split('/').pop()}
            </a>
          </div>
          <Button variant="ghost" size="icon" className="h-7 w-7 shrink-0" onClick={handleRemove} type="button">
            <X className="w-4 h-4" />
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="border-2 border-dashed rounded-lg p-4 text-center">
      <input
        ref={inputRef}
        type="file"
        className="hidden"
        accept="image/*,video/*,audio/*,application/pdf"
        onChange={(e) => { const f = e.target.files?.[0]; if (f) handleFile(f); e.target.value = ''; }}
      />
      <Button
        variant="ghost"
        size="sm"
        type="button"
        onClick={() => inputRef.current?.click()}
        disabled={uploading}
        className="w-full"
      >
        {uploading ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Upload className="w-4 h-4 mr-2" />}
        {uploading ? 'Enviando…' : 'Adicionar anexo (imagem/vídeo/áudio/PDF)'}
      </Button>
      <p className="text-[10px] text-muted-foreground mt-1">Máx 16 MB · enviado quando template for selecionado</p>
    </div>
  );
}

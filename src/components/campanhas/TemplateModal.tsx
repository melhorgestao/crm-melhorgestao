import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { Loader2, Eye } from 'lucide-react';
import type { AnexoTipo } from '@/lib/storageUpload';

export interface TemplateRow {
  id: string;
  campanha_id: string;
  categoria: string;
  subcategoria: string | null;
  ordem: number;
  texto: string;
  ativo: boolean;
  anexo_url: string | null;
  anexo_tipo: AnexoTipo | null;
  observacao: string | null;
}

interface Props {
  open: boolean;
  onClose: () => void;
  campanhaId: string;
  campanhaTipo: 'ativacao' | 'followup' | 'rmkt';
  campanhaSubcategoria: string | null; // null pra ativacao/rmkt, '24h'/'3d'/'7d' pra followup
  template: TemplateRow | null; // null = criar novo
}

const FOLLOWUP_SUBS = ['24h', '3d', '7d'] as const;

export function TemplateModal({ open, onClose, campanhaId, campanhaTipo, campanhaSubcategoria, template }: Props) {
  const [texto, setTexto] = useState('');
  const [ordem, setOrdem] = useState(0);
  const [subcat, setSubcat] = useState<string | null>(null);
  const [anexoUrl, setAnexoUrl] = useState<string | null>(null);
  const [anexoTipo, setAnexoTipo] = useState<AnexoTipo | null>(null);
  const [observacao, setObservacao] = useState('');
  const [ativo, setAtivo] = useState(true);
  const [saving, setSaving] = useState(false);
  const [previewContatoId, setPreviewContatoId] = useState<string>('');
  const [previewTexto, setPreviewTexto] = useState<string>('');
  const [contatos, setContatos] = useState<Array<{ id: string; nome: string }>>([]);

  useEffect(() => {
    if (!open) return;
    if (template) {
      setTexto(template.texto);
      setOrdem(template.ordem);
      setSubcat(template.subcategoria);
      setAnexoUrl(template.anexo_url);
      setAnexoTipo(template.anexo_tipo);
      setObservacao(template.observacao || '');
      setAtivo(template.ativo);
    } else {
      setTexto('');
      setOrdem(0);
      setSubcat(campanhaSubcategoria);
      setAnexoUrl(null);
      setAnexoTipo(null);
      setObservacao('');
      setAtivo(true);
    }
    setPreviewTexto('');
    // busca 10 contatos pra preview
    supabase.from('contatos').select('id, nome').not('nome', 'is', null).limit(10).order('updated_at', { ascending: false })
      .then(({ data }) => setContatos((data || []) as any));
  }, [open, template, campanhaSubcategoria]);

  const handleSave = async () => {
    if (!texto.trim()) { toast.error('Texto é obrigatório'); return; }
    setSaving(true);
    const payload = {
      campanha_id: campanhaId,
      categoria: campanhaTipo,
      subcategoria: subcat,
      ordem,
      texto: texto.trim(),
      ativo,
      anexo_url: anexoUrl,
      anexo_tipo: anexoTipo,
      observacao: observacao.trim() || null,
    };
    if (template?.id) {
      const { error } = await supabase.from('templates_msg').update(payload).eq('id', template.id);
      setSaving(false);
      if (error) { toast.error('Erro: ' + error.message); return; }
      toast.success('Template atualizado');
    } else {
      const { error } = await supabase.from('templates_msg').insert(payload);
      setSaving(false);
      if (error) { toast.error('Erro: ' + error.message); return; }
      toast.success('Template criado');
    }
    onClose();
  };

  const handlePreview = async () => {
    if (!previewContatoId) { toast.info('Escolha um contato pra preview'); return; }
    const { data, error } = await supabase.rpc('escolhe_template_v2', {
      p_categoria: campanhaTipo,
      p_subcategoria: subcat,
      p_contato_id: previewContatoId,
      p_instancia_id: '00000000-0000-0000-0000-000000000000', // dummy: bypassa toggle/limite, preview puro
    });
    if (error) { toast.error('Preview falhou: ' + error.message); return; }
    if (!data) {
      // se RPC retornou null por causa de regra (horário, limite…), faz substituição manual local
      let t = texto;
      const { data: c } = await supabase.from('contatos').select('nome, cidade').eq('id', previewContatoId).maybeSingle();
      if (c) {
        t = t.replace(/\{\{nome\}\}/g, (c.nome || 'amigo(a)').split(' ')[0]);
        t = t.replace(/\{\{cidade\}\}/g, c.cidade || '');
      }
      setPreviewTexto(t + '\n\n[preview local — pode haver placeholders globais não substituídos]');
      return;
    }
    setPreviewTexto((data as any)?.texto || '');
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{template ? 'Editar template' : 'Novo template'}</DialogTitle>
          <DialogDescription>
            Use <code className="font-mono text-xs">{'{{nome}}'}</code>, <code className="font-mono text-xs">{'{{cidade}}'}</code>, <code className="font-mono text-xs">{'{{rep_nome}}'}</code> ou variáveis globais.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          {campanhaTipo === 'followup' && (
            <div className="space-y-1">
              <Label className="text-xs">Subcategoria</Label>
              <Select value={subcat || '24h'} onValueChange={(v) => setSubcat(v)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {FOLLOWUP_SUBS.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="space-y-1">
            <div className="flex items-center justify-between">
              <Label className="text-xs">Texto</Label>
              <span className="text-[10px] text-muted-foreground tabular-nums">{texto.length} caracteres</span>
            </div>
            <Textarea
              value={texto}
              onChange={e => setTexto(e.target.value)}
              rows={6}
              placeholder="Olá {{nome}}! ..."
              className="font-mono text-sm"
            />
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1">
              <Label className="text-xs">Ordem (rotação)</Label>
              <Input type="number" value={ordem} onChange={e => setOrdem(parseInt(e.target.value) || 0)} />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Observação</Label>
              <Input value={observacao} onChange={e => setObservacao(e.target.value)} placeholder="ex: tom comercial" />
            </div>
          </div>

          <p className="text-[11px] text-muted-foreground italic">
            Anexos agora são gerenciados no nível da campanha (seção "Anexos" abaixo). Cada envio combina UM template + UM anexo (rotação independente).
          </p>

          <label className="flex items-center gap-2 text-sm cursor-pointer">
            <input type="checkbox" checked={ativo} onChange={e => setAtivo(e.target.checked)} />
            <span>Ativo (entra na rotação)</span>
          </label>

          {/* Preview */}
          <details className="border rounded-lg p-2">
            <summary className="text-xs cursor-pointer text-muted-foreground hover:text-foreground select-none">
              👁 Preview com contato real
            </summary>
            <div className="mt-2 space-y-2">
              <div className="flex gap-2">
                <Select value={previewContatoId} onValueChange={setPreviewContatoId}>
                  <SelectTrigger><SelectValue placeholder="Selecionar contato…" /></SelectTrigger>
                  <SelectContent>
                    {contatos.map(c => <SelectItem key={c.id} value={c.id}>{c.nome}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Button size="sm" variant="outline" onClick={handlePreview} type="button">
                  <Eye className="w-3.5 h-3.5 mr-1" /> Ver
                </Button>
              </div>
              {previewTexto && (
                <div className="bg-muted/40 rounded p-2 text-sm whitespace-pre-wrap font-mono text-xs">
                  {previewTexto}
                </div>
              )}
            </div>
          </details>

          <div className="flex gap-2 pt-2">
            <Button variant="outline" className="flex-1" onClick={onClose}>Cancelar</Button>
            <Button className="flex-1 bg-sf-green hover:bg-sf-green/90" onClick={handleSave} disabled={saving}>
              {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
              {template ? 'Salvar' : 'Criar'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/**
 * 1ª Apresentação — 3 blocos + reapresentação.
 * Edição manual. SEM LLM. SEM chunks.
 * O TS do agent-start envia esses 3 blocos rígidos antes do bloco 4
 * (saudação/resposta do Agent Start).
 */
import { useState, useRef, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Loader2, Save, Upload } from 'lucide-react';
import { toast } from 'sonner';

interface Row { chave: string; valor: any }

export function ApresentacaoConfig() {
  const { data: rows = [], refetch, isLoading } = useQuery({
    queryKey: ['agent-config-apresentacao'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('agent_config')
        .select('chave,valor')
        .eq('agent', 'apresentacao');
      if (error) throw error;
      return (data || []) as Row[];
    },
  });

  const [v, setV] = useState<Record<string, any>>({});
  const [reapOn, setReapOn] = useState(false);
  const [reapMeses, setReapMeses] = useState(6);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const fotoInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!rows.length) return;
    const m: Record<string, any> = {};
    rows.forEach(r => { m[r.chave] = r.valor });
    setV(m);
    const rm = m.reapresentar_meses;
    setReapOn(typeof rm === 'number' && rm > 0);
    setReapMeses(typeof rm === 'number' && rm > 0 ? rm : 6);
  }, [rows]);

  const salvar = async (chave: string, valor: any) => {
    setSavingKey(chave);
    const { error } = await supabase.from('agent_config')
      .upsert({ agent: 'apresentacao', chave, valor }, { onConflict: 'agent,chave' });
    setSavingKey(null);
    if (error) return toast.error(error.message);
    toast.success('Salvo');
    refetch();
  };

  const handleUploadFoto = async (file: File) => {
    if (file.size > 16 * 1024 * 1024) return toast.error('Máx 16 MB');
    setUploading(true);
    const ext = file.name.split('.').pop() || 'png';
    const path = `apresentacao-${Date.now()}.${ext}`;
    const { error: upErr } = await supabase.storage.from('Start').upload(path, file, { upsert: true });
    if (upErr) { setUploading(false); return toast.error('Upload: ' + upErr.message) }
    const { data: pub } = supabase.storage.from('Start').getPublicUrl(path);
    setV({ ...v, bloco2_foto_url: pub.publicUrl });
    await salvar('bloco2_foto_url', pub.publicUrl);
    setUploading(false);
  };

  if (isLoading) return <Loader2 className="w-5 h-5 animate-spin" />;

  return (
    <div className="space-y-6">
      <div className="border rounded-xl p-4 bg-blue-50 dark:bg-blue-950/30 text-xs space-y-1">
        <p className="font-medium">📤 Como a 1ª Apresentação é enviada</p>
        <p className="text-muted-foreground leading-relaxed">
          Toda vez que um contato manda a 1ª mensagem (não-cliente, ou via reapresentação periódica),
          o bot envia <strong>4 mensagens em sequência</strong> com delay de 2s entre cada uma:
          <br />[1] Bloco texto institucional · [2] Foto + cardápio · [3] Bônus ·
          [4] Saudação ou resposta (vem do Agent Start)
        </p>
      </div>

      {/* BLOCO 1 */}
      <Section title="BLOCO 1 — TEXTO INSTITUCIONAL"
        hint="Primeira mensagem enviada. Texto puro, sem LLM.">
        <CampoTextarea label="Texto" rows={6}
          value={v.bloco1_texto || ''}
          onChange={x => setV({ ...v, bloco1_texto: x })}
          onSave={() => salvar('bloco1_texto', v.bloco1_texto)}
          saving={savingKey === 'bloco1_texto'} />
      </Section>

      {/* BLOCO 2 */}
      <Section title="BLOCO 2 — FOTO + CARDÁPIO"
        hint="Foto enviada com caption. Lista de produtos é gerada automaticamente a partir da tabela 'produtos' ativos.">
        <div className="space-y-1">
          <Label className="text-xs font-medium">Foto (bucket Start)</Label>
          <div className="border rounded-lg p-3 bg-muted/20 flex items-center gap-3">
            {v.bloco2_foto_url ? (
              <img src={v.bloco2_foto_url} alt="foto" className="w-20 h-20 object-cover rounded" />
            ) : (
              <div className="w-20 h-20 rounded bg-background border flex items-center justify-center text-xs text-muted-foreground">—</div>
            )}
            <div className="flex-1 min-w-0">
              <p className="text-[11px] text-muted-foreground truncate">
                {v.bloco2_foto_url || 'Nenhuma foto definida — usa default'}
              </p>
              <Button size="sm" variant="outline" className="mt-1" disabled={uploading}
                      onClick={() => fotoInputRef.current?.click()}>
                {uploading ? <Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" /> : <Upload className="w-3.5 h-3.5 mr-1" />}
                {uploading ? 'Enviando…' : 'Trocar foto'}
              </Button>
              <input ref={fotoInputRef} type="file" accept="image/*" className="hidden"
                     onChange={e => { const f = e.target.files?.[0]; if (f) handleUploadFoto(f); e.target.value = '' }} />
            </div>
          </div>
        </div>

        <CampoTextarea label="Header (acima da lista de produtos)" rows={2}
          value={v.bloco2_header || ''}
          onChange={x => setV({ ...v, bloco2_header: x })}
          onSave={() => salvar('bloco2_header', v.bloco2_header)}
          saving={savingKey === 'bloco2_header'} />

        <div className="border-l-2 border-emerald-500 pl-3 py-2 bg-emerald-50 dark:bg-emerald-950/20 text-[11px]">
          <p className="font-medium text-emerald-800 dark:text-emerald-300">📋 Lista de produtos (auto)</p>
          <p className="text-muted-foreground mt-0.5">
            Inserida aqui automaticamente. Cada linha: <code>{'{emoji}'} {'{nome_oficial}'} — R$ {'{preco}'}</code>.
            Pra alterar, edite a tabela em <strong>Estoque</strong>.
          </p>
        </div>

        <CampoTextarea label="Footer (opcional, abaixo da lista)" rows={2}
          value={v.bloco2_footer || ''}
          onChange={x => setV({ ...v, bloco2_footer: x })}
          onSave={() => salvar('bloco2_footer', v.bloco2_footer)}
          saving={savingKey === 'bloco2_footer'} />
      </Section>

      {/* BLOCO 3 */}
      <Section title="BLOCO 3 — BÔNUS"
        hint="Mensagem separada com regras de bônus por quantidade.">
        <CampoTextarea label="Texto dos bônus" rows={6}
          value={v.bloco3_bonus || ''}
          onChange={x => setV({ ...v, bloco3_bonus: x })}
          onSave={() => salvar('bloco3_bonus', v.bloco3_bonus)}
          saving={savingKey === 'bloco3_bonus'} />
      </Section>

      {/* REAPRESENTAÇÃO */}
      <Section title="REAPRESENTAÇÃO PERIÓDICA"
        hint="Reenvia esses 3 blocos pra contatos que sumiram há X meses (não-clientes).">
        <div className="space-y-2 border rounded-lg p-3 bg-muted/20">
          <label className="flex items-center justify-between cursor-pointer">
            <p className="text-xs font-medium">Ativar reapresentação</p>
            <Switch checked={reapOn} onCheckedChange={setReapOn} />
          </label>
          {reapOn && (
            <div className="flex items-end gap-2 pt-2">
              <div className="flex-1">
                <Label className="text-xs">Após (meses)</Label>
                <Input type="number" min={1} max={36} value={reapMeses}
                       onChange={e => setReapMeses(parseInt(e.target.value) || 6)} />
              </div>
              <Button size="sm" onClick={() => salvar('reapresentar_meses', reapMeses)}>
                <Save className="w-3.5 h-3.5 mr-1" /> Salvar
              </Button>
            </div>
          )}
          {!reapOn && v.reapresentar_meses != null && (
            <Button size="sm" variant="outline" onClick={() => salvar('reapresentar_meses', null)}>
              Desativar
            </Button>
          )}
        </div>
      </Section>
    </div>
  );
}

function Section({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="border rounded-xl p-4 space-y-3">
      <div>
        <p className="text-xs font-bold uppercase text-muted-foreground tracking-wider">{title}</p>
        {hint && <p className="text-[10px] text-muted-foreground italic mt-0.5">{hint}</p>}
      </div>
      {children}
    </div>
  );
}

function CampoTextarea({
  label, value, rows = 4, onChange, onSave, saving,
}: {
  label: string; value: string; rows?: number;
  onChange: (v: string) => void; onSave: () => void; saving: boolean;
}) {
  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <Label className="text-xs font-medium">{label}</Label>
        <Button size="sm" variant="ghost" className="h-6 px-2 text-xs" onClick={onSave} disabled={saving}>
          {saving ? <Loader2 className="w-3 h-3 mr-1 animate-spin" /> : <Save className="w-3 h-3 mr-1" />}
          Salvar
        </Button>
      </div>
      <Textarea value={value} onChange={e => onChange(e.target.value)} rows={rows}
                className="font-mono text-xs" />
    </div>
  );
}

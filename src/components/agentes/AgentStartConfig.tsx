/**
 * Configurações do Agent Start (editáveis sem redeploy).
 * Os blocos 1–4 da apresentação inicial migraram pra aba "1ª Apresentação".
 * Aqui ficam:
 *  - SAUDAÇÃO (bloco 5): templates por canal (BASE / ADS / REP / CLIENTE /
 *    CLIENTE PENDENTE). Usado quando o lead manda saudação genérica; se vier
 *    pergunta direta, o agent responde via LLM em vez de usar o template.
 *  - LLM: temperature.
 *
 * Campos salvos em agent_config (key/value JSONB).
 */
import { useState, useRef, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Loader2, Save, Upload, AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';

interface ConfigRow { agent: string; chave: string; valor: any; descricao: string | null }

// Apresentação inicial migrou pra aba "1ª Apresentação" (3 blocos rígidos).
// Aqui ficam só as saudações e configs de LLM.
const CAMPOS_APRESENTACAO: Array<{ chave: string; label: string; rows: number; warn?: string }> = [];

const CAMPOS_SAUDACAO = [
  { chave: 'saudacao_base',              label: 'BASE (lead orgânico)' },
  { chave: 'saudacao_ads',               label: 'ADS (tráfego pago)' },
  { chave: 'saudacao_rep',               label: 'REP (representante)' },
  { chave: 'saudacao_cliente',           label: 'CLIENTE (já comprou, sem pendência)' },
  { chave: 'saudacao_cliente_pendente',  label: 'CLIENTE PENDENTE (com saldo devedor) · placeholders {nome} {saldo}' },
];

export function AgentStartConfig() {
  const { data: rows = [], refetch, isLoading } = useQuery({
    queryKey: ['agent-config-start'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('agent_config')
        .select('agent,chave,valor,descricao')
        .eq('agent', 'start');
      if (error) throw error;
      return (data || []) as ConfigRow[];
    },
  });

  // Estado local
  const [valores, setValores] = useState<Record<string, any>>({});
  const [reapresentarOn, setReapresentarOn] = useState(false);
  const [reapresentarMeses, setReapresentarMeses] = useState(6);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const fotoInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!rows.length) return;
    const m: Record<string, any> = {};
    rows.forEach(r => { m[r.chave] = r.valor });
    setValores(m);
    const rm = m.reapresentar_meses;
    setReapresentarOn(typeof rm === 'number' && rm > 0);
    setReapresentarMeses(typeof rm === 'number' && rm > 0 ? rm : 6);
  }, [rows]);

  const salvar = async (chave: string, valor: any) => {
    setSavingKey(chave);
    const { error } = await supabase.from('agent_config')
      .upsert({ agent: 'start', chave, valor }, { onConflict: 'agent,chave' });
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
    setValores({ ...valores, foto_apresentacao_url: pub.publicUrl });
    await salvar('foto_apresentacao_url', pub.publicUrl);
    setUploading(false);
  };

  if (isLoading) return <Loader2 className="w-5 h-5 animate-spin" />;

  return (
    <div className="space-y-6">
      <div className="border rounded-xl p-3 bg-muted/20 text-[11px] text-muted-foreground">
        📌 Os 4 primeiros blocos da apresentação inicial (texto, cardápio, bônus, foto)
        vivem na aba <strong>1ª Apresentação</strong>. Aqui fica o <strong>bloco 5</strong>:
        saudação por canal (ou resposta à pergunta direta) + temperature do LLM.
      </div>

      {/* ===== SAUDAÇÃO ===== */}
      <Section title="SAUDAÇÃO" hint="Só é usada quando o lead manda saudação genérica ('oi', 'boa noite'). Se ele chegar com pergunta direta, o agent responde diretamente em vez de saudar. Placeholders: {nome}, {saldo}.">
        {CAMPOS_SAUDACAO.map(c => (
          <CampoTextarea
            key={c.chave}
            label={c.label}
            rows={2}
            value={valores[c.chave] || ''}
            onChange={v => setValores({ ...valores, [c.chave]: v })}
            onSave={() => salvar(c.chave, valores[c.chave])}
            saving={savingKey === c.chave}
          />
        ))}
      </Section>

      {/* ===== LLM ===== */}
      <Section title="LLM" hint="Configs do modelo. Reapresentação periódica vive na aba 1ª Apresentação.">
        <div className="space-y-1">
          <Label className="text-xs">LLM Temperature (0 = determinístico, 1 = criativo)</Label>
          <div className="flex items-center gap-3">
            <input type="range" min={0} max={1} step={0.05}
                   value={Number(valores.llm_temperature ?? 0.4)}
                   onChange={e => setValores({ ...valores, llm_temperature: parseFloat(e.target.value) })}
                   className="flex-1" />
            <span className="text-xs tabular-nums w-10">{Number(valores.llm_temperature ?? 0.4).toFixed(2)}</span>
            <Button size="sm" onClick={() => salvar('llm_temperature', Number(valores.llm_temperature ?? 0.4))}>
              <Save className="w-3.5 h-3.5" />
            </Button>
          </div>
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
  label, value, rows = 4, onChange, onSave, saving, warn,
}: {
  label: string; value: string; rows?: number; warn?: string;
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
      {warn && (
        <div className="flex items-start gap-1.5 text-[10px] text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/30 rounded p-1.5 border border-amber-200 dark:border-amber-900">
          <AlertTriangle className="w-3 h-3 shrink-0 mt-0.5" />
          <span>{warn}</span>
        </div>
      )}
      <Textarea value={value} onChange={e => onChange(e.target.value)} rows={rows}
                className="font-mono text-xs" />
    </div>
  );
}

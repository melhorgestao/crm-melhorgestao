/**
 * Bloco de regras editáveis específico pra campanhas tipo='marketing'.
 * Exibido logo abaixo do título no CampanhaDrawer.
 *
 * Regras:
 *  - Dispara para: ☐ CLIENTE ☐ W-FOLLOWUP (pode marcar ambas)
 *  - Cooldown RMKT/FUP: 24h / 3 dias / 7 dias
 *  - Nome da campanha (vai pra contatos.marketing_campanha)
 *  - Prioridade: Sem prioridade / Clientes
 */
import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Loader2, Save } from 'lucide-react';
import { toast } from 'sonner';
import type { CampanhaRow } from './CampanhaCard';

interface Props { campanha: CampanhaRow; onSaved: () => void }

const COOLDOWN_OPTS = [
  { value: 1, label: '24 horas' },
  { value: 3, label: '3 dias' },
  { value: 7, label: '7 dias' },
];

export function MarketingRulesBlock({ campanha, onSaved }: Props) {
  const [nome, setNome]               = useState(campanha.nome);
  const [disparaCli, setDisparaCli]   = useState(!!campanha.marketing_dispara_cliente);
  const [disparaFup, setDisparaFup]   = useState(!!campanha.marketing_dispara_wait_followup);
  const [cooldown, setCooldown]       = useState<number>(campanha.marketing_cooldown_dias || 1);
  const [prioridade, setPrioridade]   = useState<'sem_prioridade' | 'clientes'>(campanha.marketing_prioridade || 'sem_prioridade');
  const [saving, setSaving]           = useState(false);

  useEffect(() => {
    setNome(campanha.nome);
    setDisparaCli(!!campanha.marketing_dispara_cliente);
    setDisparaFup(!!campanha.marketing_dispara_wait_followup);
    setCooldown(campanha.marketing_cooldown_dias || 1);
    setPrioridade(campanha.marketing_prioridade || 'sem_prioridade');
  }, [campanha.id]);

  const handleSave = async () => {
    if (!disparaCli && !disparaFup) {
      toast.error('Selecione ao menos um público (Cliente ou Wait Follow-up)');
      return;
    }
    setSaving(true);
    const { error } = await supabase.from('campanhas')
      .update({
        nome: nome.trim(),
        marketing_dispara_cliente:       disparaCli,
        marketing_dispara_wait_followup: disparaFup,
        marketing_cooldown_dias:         cooldown,
        marketing_prioridade:            prioridade,
      })
      .eq('id', campanha.id);
    setSaving(false);
    if (error) return toast.error(error.message);
    toast.success('Regras salvas');
    onSaved();
  };

  return (
    <div className="border-l-4 border-emerald-500 bg-emerald-50 dark:bg-emerald-950/30 rounded-r-lg p-3 space-y-3">
      <p className="text-xs font-semibold text-emerald-900 dark:text-emerald-200">📣 Regras de marketing</p>

      <div className="space-y-1">
        <Label className="text-xs">Nome da campanha</Label>
        <Input value={nome} onChange={e => setNome(e.target.value)} placeholder="ex: Dia das Mães 2026" className="h-8 text-xs" />
        <p className="text-[10px] text-muted-foreground">
          Grava em <code className="font-mono">contatos.marketing_campanha</code>.
        </p>
      </div>

      <div className="space-y-1">
        <Label className="text-xs">Dispara apenas para</Label>
        <div className="flex flex-wrap gap-3 text-xs">
          <label className="flex items-center gap-1.5 cursor-pointer">
            <input type="checkbox" checked={disparaCli} onChange={e => setDisparaCli(e.target.checked)} />
            <span>CLIENTE</span>
          </label>
          <label className="flex items-center gap-1.5 cursor-pointer">
            <input type="checkbox" checked={disparaFup} onChange={e => setDisparaFup(e.target.checked)} />
            <span>WAIT FOLLOW-UP</span>
          </label>
        </div>
        <p className="text-[10px] text-muted-foreground">Pode marcar ambas. C-REP nunca recebe.</p>
      </div>

      <div className="space-y-1">
        <Label className="text-xs">Bloqueio RMKT/FollowUp por</Label>
        <Select value={String(cooldown)} onValueChange={v => setCooldown(parseInt(v))}>
          <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
          <SelectContent>
            {COOLDOWN_OPTS.map(o => (
              <SelectItem key={o.value} value={String(o.value)}>{o.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <p className="text-[10px] text-muted-foreground">Contato que receber este marketing fica fora de RMKT/Follow-up por este período.</p>
      </div>

      <div className="space-y-1">
        <Label className="text-xs">Prioridade</Label>
        <Select value={prioridade} onValueChange={v => setPrioridade(v as any)}>
          <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="sem_prioridade">Sem prioridade</SelectItem>
            <SelectItem value="clientes">Clientes primeiro</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <Button size="sm" className="w-full bg-emerald-600 hover:bg-emerald-700 text-white" onClick={handleSave} disabled={saving}>
        {saving ? <Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" /> : <Save className="w-3.5 h-3.5 mr-1" />}
        Salvar regras de marketing
      </Button>
    </div>
  );
}

import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { toast } from 'sonner';
import { Plus, Pencil, Trash2, Image as ImageIcon, Loader2 } from 'lucide-react';
import type { CampanhaRow } from './CampanhaCard';
import { TemplateModal, type TemplateRow } from './TemplateModal';
import { AnexosManager } from './AnexosManager';
import { MarketingRulesBlock } from './MarketingRulesBlock';

interface Props {
  open: boolean;
  onClose: () => void;
  campanha: CampanhaRow | null;
}

const FOLLOWUP_SUBS = ['24h', '3d', '7d'] as const;

export function CampanhaDrawer({ open, onClose, campanha }: Props) {
  const qc = useQueryClient();
  const [editNome, setEditNome] = useState('');
  const [editHorIni, setEditHorIni] = useState('09:00');
  const [editHorFim, setEditHorFim] = useState('20:00');
  const [editLimite, setEditLimite] = useState<string>('');
  const [editCooldown, setEditCooldown] = useState(0);
  const [editObs, setEditObs] = useState('');
  const [editDiasInativo, setEditDiasInativo] = useState<string>('');
  const [editDiasSemEnvio, setEditDiasSemEnvio] = useState<string>('');
  const [editRmktGap12, setEditRmktGap12] = useState<string>('30');
  const [editRmktGap35, setEditRmktGap35] = useState<string>('45');
  const [editRmktGap5p, setEditRmktGap5p] = useState<string>('60');
  const [editRmktMax,   setEditRmktMax]   = useState<string>('3');
  const [editMaxTent, setEditMaxTent] = useState<string>('');
  const [editCoffeeIni, setEditCoffeeIni] = useState<string>('');
  const [editCoffeeFim, setEditCoffeeFim] = useState<string>('');
  const [editSkipRate, setEditSkipRate] = useState<string>('');
  const [editIntervalo, setEditIntervalo] = useState<string>('');
  const [editJitter, setEditJitter] = useState<string>('');
  const [limiteInstLocal, setLimiteInstLocal] = useState<Record<string, string>>({});
  const [tplModalOpen, setTplModalOpen] = useState(false);
  const [tplEdit, setTplEdit] = useState<TemplateRow | null>(null);
  const [tplSubcat, setTplSubcat] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!campanha) return;
    setEditNome(campanha.nome);
    setEditHorIni(campanha.horario_inicio.slice(0, 5));
    setEditHorFim(campanha.horario_fim.slice(0, 5));
    // limite_diario_total removido — só limite por instância importa
    setEditCooldown(campanha.cooldown_dias);
    // observacao removida
    setEditDiasInativo(campanha.dias_inativo_min?.toString() || '');
    setEditDiasSemEnvio(campanha.dias_sem_envio?.toString() || '');
    setEditMaxTent(campanha.max_tentativas_categoria?.toString() || '');
    setEditRmktGap12((campanha as any).rmkt_gap_1_2_dias?.toString() || '30');
    setEditRmktGap35((campanha as any).rmkt_gap_3_5_dias?.toString() || '45');
    setEditRmktGap5p((campanha as any).rmkt_gap_5_plus_dias?.toString() || '60');
    setEditRmktMax((campanha as any).rmkt_max_envios?.toString() || '3');
    setEditCoffeeIni(campanha.coffee_break_inicio?.slice(0, 5) || '');
    setEditCoffeeFim(campanha.coffee_break_fim?.slice(0, 5) || '');
    setEditSkipRate(campanha.skip_rate != null ? (campanha.skip_rate * 100).toString() : '0');
    setEditIntervalo(campanha.intervalo_minutos?.toString() || '5');
    setEditJitter((campanha as any).intervalo_jitter_pct != null ? Math.round((campanha as any).intervalo_jitter_pct * 100).toString() : '40');
  }, [campanha]);

  // Templates da campanha
  const { data: templates, refetch: refetchTpls } = useQuery({
    queryKey: ['templates_campanha', campanha?.id],
    enabled: !!campanha?.id && open,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('templates_msg')
        .select('id, campanha_id, categoria, subcategoria, ordem, texto, ativo, anexo_url, anexo_tipo')
        .eq('campanha_id', campanha!.id)
        .order('subcategoria', { ascending: true, nullsFirst: true })
        .order('ordem', { ascending: true });
      if (error) throw error;
      return (data || []) as any[] as TemplateRow[];
    },
  });

  // Instâncias + toggle por campanha
  const { data: matrizData, refetch: refetchMatriz } = useQuery({
    queryKey: ['campanha_instancia', campanha?.id],
    enabled: !!campanha?.id && open,
    queryFn: async () => {
      const [instsRes, ciRes] = await Promise.all([
        supabase.from('instancias').select('id, nome, status, ativo').eq('ativo', true).order('nome'),
        supabase.from('campanha_instancia' as any).select('*').eq('campanha_id', campanha!.id),
      ]);
      const ci = Object.fromEntries(((ciRes.data || []) as any[]).map((r: any) => [r.instancia_id, r]));
      const rows = ((instsRes.data || []) as any[])
        .filter((i: any) => i.nome !== 'Instancia ADMIN')
        .map((i: any) => ({
          ...i,
          ativa: ci[i.id]?.ativa !== false, // default true se não existe linha
          limite_diario_instancia: ci[i.id]?.limite_diario_instancia ?? null,
        }));
      // sync estado local de inputs (sem sobrescrever se usuário já está digitando)
      setLimiteInstLocal(prev => {
        const next = { ...prev };
        for (const r of rows) {
          if (next[r.id] === undefined) {
            next[r.id] = r.limite_diario_instancia?.toString() ?? '';
          }
        }
        return next;
      });
      return rows;
    },
  });

  if (!campanha) return null;

  const saveConfig = async () => {
    setSaving(true);
    const changes: any = {};
    if (editNome !== campanha.nome) changes.nome = editNome.trim();
    const horIni = editHorIni.length === 5 ? editHorIni + ':00' : editHorIni;
    const horFim = editHorFim.length === 5 ? editHorFim + ':00' : editHorFim;
    if (horIni !== campanha.horario_inicio) changes.horario_inicio = horIni;
    if (horFim !== campanha.horario_fim) changes.horario_fim = horFim;
    const limite = editLimite.trim() === '' ? null : parseInt(editLimite, 10);
    // limite_diario_total removido (só por instância)
    if (editCooldown !== campanha.cooldown_dias) changes.cooldown_dias = editCooldown;
    // observacao removida
    const diasInativo = editDiasInativo.trim() === '' ? null : parseInt(editDiasInativo, 10);
    const diasSemEnvio = editDiasSemEnvio.trim() === '' ? null : parseInt(editDiasSemEnvio, 10);
    const maxTent = editMaxTent.trim() === '' ? null : parseInt(editMaxTent, 10);
    if (diasInativo !== campanha.dias_inativo_min) changes.dias_inativo_min = diasInativo;
    if (diasSemEnvio !== campanha.dias_sem_envio) changes.dias_sem_envio = diasSemEnvio;
    if (maxTent !== campanha.max_tentativas_categoria) changes.max_tentativas_categoria = maxTent;

    if (campanha.tipo === 'rmkt') {
      const g12 = parseInt(editRmktGap12) || 30;
      const g35 = parseInt(editRmktGap35) || 45;
      const g5p = parseInt(editRmktGap5p) || 60;
      const max = parseInt(editRmktMax)   || 3;
      if (g12 !== (campanha as any).rmkt_gap_1_2_dias)    changes.rmkt_gap_1_2_dias    = g12;
      if (g35 !== (campanha as any).rmkt_gap_3_5_dias)    changes.rmkt_gap_3_5_dias    = g35;
      if (g5p !== (campanha as any).rmkt_gap_5_plus_dias) changes.rmkt_gap_5_plus_dias = g5p;
      if (max !== (campanha as any).rmkt_max_envios)      changes.rmkt_max_envios      = max;
    }

    const coffeeIni = editCoffeeIni.trim() === '' ? null : (editCoffeeIni.length === 5 ? editCoffeeIni + ':00' : editCoffeeIni);
    const coffeeFim = editCoffeeFim.trim() === '' ? null : (editCoffeeFim.length === 5 ? editCoffeeFim + ':00' : editCoffeeFim);
    if (coffeeIni !== campanha.coffee_break_inicio) changes.coffee_break_inicio = coffeeIni;
    if (coffeeFim !== campanha.coffee_break_fim) changes.coffee_break_fim = coffeeFim;
    const skip = Math.max(0, Math.min(100, parseFloat(editSkipRate) || 0)) / 100;
    if (Math.abs(skip - (campanha.skip_rate || 0)) > 0.001) changes.skip_rate = skip;
    const intervalo = Math.max(1, Math.min(1440, parseInt(editIntervalo, 10) || 5));
    if (intervalo !== campanha.intervalo_minutos) changes.intervalo_minutos = intervalo;
    const jitter = Math.max(0, Math.min(90, parseFloat(editJitter) || 0)) / 100;
    if (Math.abs(jitter - ((campanha as any).intervalo_jitter_pct ?? 0.4)) > 0.001) changes.intervalo_jitter_pct = jitter;
    if (Object.keys(changes).length === 0) { setSaving(false); toast.info('Sem alterações'); return; }
    changes.updated_at = new Date().toISOString();
    const { error } = await supabase.from('campanhas').update(changes).eq('id', campanha.id);
    setSaving(false);
    if (error) { toast.error(error.message); return; }
    toast.success('Campanha atualizada');
    qc.invalidateQueries({ queryKey: ['campanhas_list'] });
  };

  const toggleInstancia = async (instId: string, novaAtiva: boolean) => {
    const { error } = await supabase
      .from('campanha_instancia' as any)
      .upsert({ campanha_id: campanha.id, instancia_id: instId, ativa: novaAtiva },
              { onConflict: 'campanha_id,instancia_id' });
    if (error) { toast.error(error.message); return; }
    refetchMatriz();
    qc.invalidateQueries({ queryKey: ['campanha_stats', campanha.id] });
  };

  const commitLimiteInstancia = async (instId: string, atualNoBanco: number | null) => {
    const raw = (limiteInstLocal[instId] ?? '').trim();
    const num = raw === '' ? null : Math.max(1, Math.min(99999, parseInt(raw, 10) || 0));
    if (num === atualNoBanco) return; // nada mudou
    const { error } = await supabase
      .from('campanha_instancia' as any)
      .upsert({ campanha_id: campanha.id, instancia_id: instId, limite_diario_instancia: num },
              { onConflict: 'campanha_id,instancia_id' });
    if (error) { toast.error(error.message); return; }
    toast.success(num === null ? 'Limite removido (usa global)' : `Limite: ${num}/dia`);
    refetchMatriz();
    qc.invalidateQueries({ queryKey: ['campanha_stats', campanha.id] });
  };

  const deleteTpl = async (id: string) => {
    if (!confirm('Excluir este template?')) return;
    const { error } = await supabase.from('templates_msg').delete().eq('id', id);
    if (error) { toast.error(error.message); return; }
    refetchTpls();
    qc.invalidateQueries({ queryKey: ['campanha_stats', campanha.id] });
  };

  const toggleTplAtivo = async (tpl: TemplateRow) => {
    const { error } = await supabase.from('templates_msg').update({ ativo: !tpl.ativo }).eq('id', tpl.id);
    if (error) { toast.error(error.message); return; }
    refetchTpls();
  };

  // Subcategoria principal da campanha (inferida pelos templates existentes ou pelo nome)
  const subcatPrincipal: string | null = (() => {
    if (campanha.tipo !== 'followup') return null;
    const t = (templates || []).find(x => x.subcategoria);
    if (t?.subcategoria) return t.subcategoria;
    const m = campanha.nome.match(/24h|3d|7d|3\s*dias?|7\s*dias?/i)?.[0];
    if (!m) return '24h';
    if (/3/.test(m)) return '3d';
    if (/7/.test(m)) return '7d';
    return '24h';
  })();

  // Agrupa templates — pra followup, mostra só a subcategoria principal dessa campanha
  const tplGroups: Array<{ key: string; label: string; items: TemplateRow[] }> = (() => {
    if (campanha.tipo !== 'followup') {
      return [{ key: 'all', label: 'Templates', items: templates || [] }];
    }
    return [{
      key: subcatPrincipal!,
      label: `Variações ${subcatPrincipal}`,
      items: (templates || []).filter(t => t.subcategoria === subcatPrincipal),
    }];
  })();

  return (
    <>
      <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
        <SheetContent className="w-full sm:max-w-xl overflow-y-auto">
          <SheetHeader>
            <SheetTitle>{campanha.nome}</SheetTitle>
          </SheetHeader>

          <div className="space-y-6 py-4">
            {/* Regra fixa — Ativação Geral */}
            {campanha.tipo === 'ativacao' && (
              <div className="border-l-4 border-amber-500 bg-amber-50 dark:bg-amber-950/30 rounded-r-lg p-3 text-xs">
                <p className="font-semibold text-amber-900 dark:text-amber-200 mb-1">📌 Regra desta campanha</p>
                <p className="text-amber-800 dark:text-amber-300">
                  Dispara apenas para contatos <code className="font-mono bg-amber-100 dark:bg-amber-900/50 px-1 rounded">ultima_interacao = NULL</code> e captura o contato para a instância (regra fixa).
                </p>
              </div>
            )}

            {/* Regras editáveis — Marketing */}
            {campanha.tipo === 'marketing' && (
              <MarketingRulesBlock campanha={campanha} onSaved={() => qc.invalidateQueries({ queryKey: ['campanhas'] })} />
            )}

            {/* Configurações */}
            <section className="space-y-3">
              <p className="text-xs uppercase text-muted-foreground tracking-wide">Configurações</p>
              <div className="space-y-2">
                <Label className="text-xs">Nome</Label>
                <Input value={editNome} onChange={e => setEditNome(e.target.value)} />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div className="space-y-1">
                  <Label className="text-xs">Horário início (BRT)</Label>
                  <Input type="time" value={editHorIni} onChange={e => setEditHorIni(e.target.value)} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Horário fim (BRT)</Label>
                  <Input type="time" value={editHorFim} onChange={e => setEditHorFim(e.target.value)} />
                </div>
              </div>
              {/* Avançado — cooldown raramente usado */}
              <details className="text-xs">
                <summary className="cursor-pointer text-muted-foreground hover:text-foreground select-none">
                  ⚙ Configuração avançada
                </summary>
                <div className="mt-3 space-y-1">
                  <Label className="text-xs">Cooldown cross-campanha (dias)</Label>
                  <Input type="number" value={editCooldown} onChange={e => setEditCooldown(parseInt(e.target.value) || 0)} placeholder="0 = desativado" />
                  <p className="text-[10px] text-muted-foreground">
                    ⚠️ Bloqueia <strong>qualquer outra campanha</strong> pro contato em X dias após esta. Use 0 — a granularidade que você quer está em "Regras de elegibilidade" abaixo.
                  </p>
                </div>
              </details>
              <Button className="w-full" onClick={saveConfig} disabled={saving}>
                {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
                Salvar configurações
              </Button>
            </section>

            {/* Regras de elegibilidade */}
            <section className="space-y-3">
              <p className="text-xs uppercase text-muted-foreground tracking-wide">Regras de elegibilidade</p>

              {campanha.tipo === 'followup' && (
                <div className="border rounded-lg bg-muted/30 p-3 text-xs space-y-1">
                  <p className="font-medium text-sm">📋 Critérios fixos</p>
                  <p className="text-muted-foreground">
                    Contatos com <code className="font-mono">ultima_interacao = wait_follow_up</code> e tempo desde <code className="font-mono">data_wait_follow_up</code> ≥ ao gap da tentativa:
                  </p>
                  <ul className="list-disc list-inside text-muted-foreground space-y-0.5">
                    <li><strong>Follow-up 24h</strong>: 1ª tentativa após 24h sem resposta</li>
                    <li><strong>Follow-up 3 dias</strong>: 2ª tentativa após 3 dias</li>
                    <li><strong>Follow-up 7 dias</strong>: 3ª tentativa após 7 dias</li>
                  </ul>
                  <p className="text-muted-foreground pt-1">Limite total: 3 tentativas (controlado por <code className="font-mono">follow_up_tentativas</code>).</p>
                </div>
              )}

              {campanha.tipo === 'rmkt' && (
                <>
                  {/* Gap por faixa de quantidade do último pedido */}
                  <div className="border rounded-lg p-3 bg-muted/20 space-y-2">
                    <p className="text-xs font-medium">Gap por quantidade do último pedido</p>
                    <p className="text-[10px] text-muted-foreground">
                      Dias mínimos desde a última venda pra entrar em RMKT, conforme a faixa de produtos comprados.
                    </p>
                    <div className="grid grid-cols-3 gap-2">
                      <div className="space-y-1">
                        <Label className="text-[10px]">1–2 produtos</Label>
                        <Input type="number" value={editRmktGap12} onChange={e => setEditRmktGap12(e.target.value)} className="h-8 text-xs" />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-[10px]">3–5 produtos</Label>
                        <Input type="number" value={editRmktGap35} onChange={e => setEditRmktGap35(e.target.value)} className="h-8 text-xs" />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-[10px]">6+ produtos</Label>
                        <Input type="number" value={editRmktGap5p} onChange={e => setEditRmktGap5p(e.target.value)} className="h-8 text-xs" />
                      </div>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-2">
                    <div className="space-y-1">
                      <Label className="text-xs">Dias sem receber esta campanha</Label>
                      <Input
                        type="number"
                        value={editDiasSemEnvio}
                        onChange={e => setEditDiasSemEnvio(e.target.value)}
                        placeholder="ex: 30"
                      />
                      <p className="text-[10px] text-muted-foreground">Gap entre RMKTs.</p>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Max envios por contato</Label>
                      <Input
                        type="number"
                        min={1}
                        max={20}
                        value={editRmktMax}
                        onChange={e => setEditRmktMax(e.target.value)}
                        placeholder="3"
                      />
                      <p className="text-[10px] text-muted-foreground">Contador zera na compra.</p>
                    </div>
                  </div>
                </>
              )}

              {campanha.tipo === 'ativacao' && (
                <>
                  <div className="space-y-1">
                    <Label className="text-xs">Dias sem receber esta campanha</Label>
                    <Input
                      type="number"
                      value={editDiasSemEnvio}
                      onChange={e => setEditDiasSemEnvio(e.target.value)}
                      placeholder="ex: 30"
                    />
                    <p className="text-[10px] text-muted-foreground">Gap entre envios de ativação pro mesmo contato (<code className="font-mono">data_ultimo_ativacao</code>).</p>
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Máx. de ativações por contato</Label>
                    <Input
                      type="number"
                      value={editMaxTent}
                      onChange={e => setEditMaxTent(e.target.value)}
                      placeholder="ex: 3"
                    />
                    <p className="text-[10px] text-muted-foreground">Contato sai da lista após receber X ativações (<code className="font-mono">ativacao_tentativas</code>).</p>
                  </div>
                </>
              )}

              {campanha.tipo !== 'followup' && (
                <p className="text-[10px] text-sf-green">
                  ✓ Valores aplicados imediatamente — o claim do workflow lê estas regras a cada execução.
                </p>
              )}
            </section>

            {/* Anti-ban + intervalo */}
            <section className="space-y-3">
              <p className="text-xs uppercase text-muted-foreground tracking-wide">⏱ Ritmo e Anti-ban</p>

              <div className="space-y-1">
                <Label className="text-xs">Intervalo entre execuções (minutos)</Label>
                <Input
                  type="number"
                  min="1"
                  max="1440"
                  value={editIntervalo}
                  onChange={e => setEditIntervalo(e.target.value)}
                  placeholder="5"
                />
                <p className="text-[10px] text-muted-foreground">
                  Base do intervalo entre envios (o sistema aplica a variação abaixo).
                  <strong> Ativação: 5min</strong>. <strong>RMKT/Follow-up: 30min</strong> recomendado. Pode ir de 1 a 1440 (24h).
                </p>
                {campanha.ultima_execucao_em && (
                  <p className="text-[10px] text-muted-foreground">
                    Última execução: <span className="font-mono">{new Date(campanha.ultima_execucao_em).toLocaleString('pt-BR')}</span>
                  </p>
                )}
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Variação do intervalo — jitter (%)</Label>
                <Input
                  type="number"
                  min="0"
                  max="90"
                  value={editJitter}
                  onChange={e => setEditJitter(e.target.value)}
                  placeholder="40"
                />
                <p className="text-[10px] text-muted-foreground">
                  Aleatoriza cada envio em torno do intervalo, pra fugir do padrão fixo (anti-ban).
                  Ex.: 30 min com <strong>40%</strong> → cada gap cai entre <strong>18 e 42 min</strong>.
                  {(() => {
                    const base = parseInt(editIntervalo, 10) || 0;
                    const j = (parseFloat(editJitter) || 0) / 100;
                    if (base > 0 && j > 0) {
                      const lo = Math.max(0.5, base * (1 - j)).toFixed(0);
                      const hi = (base * (1 + j)).toFixed(0);
                      return <> Agora: <strong>{lo}–{hi} min</strong>.</>;
                    }
                    return <> 0% = intervalo fixo (não recomendado).</>;
                  })()}
                </p>
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Coffee break (BRT)</Label>
                <div className="grid grid-cols-2 gap-2">
                  <Input
                    type="time"
                    value={editCoffeeIni}
                    onChange={e => setEditCoffeeIni(e.target.value)}
                    placeholder="início"
                  />
                  <Input
                    type="time"
                    value={editCoffeeFim}
                    onChange={e => setEditCoffeeFim(e.target.value)}
                    placeholder="fim"
                  />
                </div>
                <p className="text-[10px] text-muted-foreground">
                  Janela do dia em que NÃO dispara (ex: 12:00 → 13:30 simula pausa de almoço, evita padrão de bot). Deixe ambos vazios pra desativar.
                </p>
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Skip aleatório (%)</Label>
                <Input
                  type="number"
                  step="1"
                  min="0"
                  max="100"
                  value={editSkipRate}
                  onChange={e => setEditSkipRate(e.target.value)}
                  placeholder="0 = desativado"
                />
                <p className="text-[10px] text-muted-foreground">
                  Probabilidade de pular cada execução. <strong>Ativação: 10%</strong> recomendado (lead frio). <strong>RMKT/Follow-up: 3-5%</strong> (clientes engajados, não atrapalha cadência).
                </p>
              </div>

              <p className="text-[10px] text-sf-green">
                ✓ Workflow chama <code className="font-mono">pode_disparar_campanha</code> antes de cada claim. Valores aplicados na próxima execução.
              </p>
            </section>

            {/* Matriz por instância */}
            <section className="space-y-2">
              <p className="text-xs uppercase text-muted-foreground tracking-wide">Toggle por instância</p>
              <div className="border rounded-lg overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-muted/40">
                    <tr>
                      <th className="text-left px-3 py-2 text-xs font-medium">Instância</th>
                      <th className="text-center px-2 py-2 text-xs font-medium w-20">Ativa</th>
                      <th className="text-right px-3 py-2 text-xs font-medium">Limite/dia</th>
                    </tr>
                  </thead>
                  <tbody>
                    {matrizData?.map((i: any) => {
                      const paused = i.status !== 'ativo';
                      return (
                      <tr key={i.id} className={`border-t ${paused ? 'opacity-50' : ''}`}>
                        <td className="px-3 py-2">
                          <p className="font-medium flex items-center gap-1.5">
                            Instância {i.nome}
                            {paused && <span className="text-[10px] text-amber-600 font-normal">(pausada — não roda)</span>}
                          </p>
                          <p className="text-[10px] text-muted-foreground">{i.status}</p>
                        </td>
                        <td className="text-center px-2 py-2">
                          <Switch
                            checked={i.ativa}
                            onCheckedChange={(v) => toggleInstancia(i.id, v)}
                            title={paused ? 'Instância pausada globalmente — esse toggle só vale quando ela voltar a ficar ativa' : ''}
                          />
                        </td>
                        <td className="px-3 py-2">
                          <Input
                            type="number"
                            min="1"
                            value={limiteInstLocal[i.id] ?? ''}
                            onChange={e => setLimiteInstLocal(prev => ({ ...prev, [i.id]: e.target.value }))}
                            onBlur={() => commitLimiteInstancia(i.id, i.limite_diario_instancia)}
                            onKeyDown={e => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }}
                            placeholder="—"
                            title="Vazio = sem limite por instância (só o total da campanha vale). Número = teto diário só desta instância."
                            className="w-20 ml-auto text-right text-sm"
                          />
                        </td>
                      </tr>
                    );})}
                  </tbody>
                </table>
              </div>
              <p className="text-[10px] text-muted-foreground">
                <strong>Ativa</strong>: liga/desliga esta campanha só pra esta instância. <strong>Limite/dia</strong>: teto de envios desta campanha por esta instância (vazio = sem teto). Pressione Enter ou clique fora pra salvar.
              </p>
              <p className="text-[10px] text-muted-foreground">
                Pausar instância em <code className="font-mono">/instancias</code> sobrepõe esses toggles — workflows nem tentam usar instância pausada.
              </p>
            </section>

            {/* Anexos da campanha (rotação independente dos templates) */}
            <section className="space-y-2 border-t pt-4">
              <AnexosManager campanhaId={campanha.id} />
            </section>

            {/* Templates */}
            <section className="space-y-3">
              <div className="flex items-center justify-between">
                <p className="text-xs uppercase text-muted-foreground tracking-wide">Templates</p>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    setTplEdit(null);
                    setTplSubcat(campanha.tipo === 'followup' ? subcatPrincipal : null);
                    setTplModalOpen(true);
                  }}
                >
                  <Plus className="w-4 h-4 mr-1" /> Novo
                </Button>
              </div>

              {tplGroups.map(g => (
                <div key={g.key} className="space-y-2">
                  {campanha.tipo === 'followup' && (
                    <p className="text-xs font-semibold text-muted-foreground">{g.label}</p>
                  )}
                  {g.items.length === 0 ? (
                    <p className="text-xs text-muted-foreground italic px-2">Sem templates</p>
                  ) : (
                    g.items.map(tpl => (
                      <div key={tpl.id} className={`border rounded-lg p-3 ${!tpl.ativo ? 'opacity-50' : ''}`}>
                        <div className="flex items-start justify-between gap-2 mb-1">
                          <div className="flex items-center gap-2">
                            <Badge variant="outline" className="text-[10px]">Var. {tpl.ordem}</Badge>
                            {tpl.anexo_url && <ImageIcon className="w-3.5 h-3.5 text-blue-500" />}
                            {/* observação removida */}
                          </div>
                          <div className="flex items-center gap-1">
                            <Switch checked={tpl.ativo} onCheckedChange={() => toggleTplAtivo(tpl)} />
                            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => { setTplEdit(tpl); setTplSubcat(tpl.subcategoria); setTplModalOpen(true); }}>
                              <Pencil className="w-3.5 h-3.5" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => deleteTpl(tpl.id)}>
                              <Trash2 className="w-3.5 h-3.5" />
                            </Button>
                          </div>
                        </div>
                        <p className="text-sm whitespace-pre-wrap font-mono text-xs text-muted-foreground line-clamp-3">{tpl.texto}</p>
                      </div>
                    ))
                  )}
                </div>
              ))}
            </section>
          </div>
        </SheetContent>
      </Sheet>

      {campanha && (
        <TemplateModal
          open={tplModalOpen}
          onClose={() => { setTplModalOpen(false); refetchTpls(); qc.invalidateQueries({ queryKey: ['campanha_stats', campanha.id] }); }}
          campanhaId={campanha.id}
          campanhaTipo={campanha.tipo}
          campanhaSubcategoria={tplSubcat}
          template={tplEdit}
        />
      )}
    </>
  );
}

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
  const [editMaxTent, setEditMaxTent] = useState<string>('');
  const [tplModalOpen, setTplModalOpen] = useState(false);
  const [tplEdit, setTplEdit] = useState<TemplateRow | null>(null);
  const [tplSubcat, setTplSubcat] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!campanha) return;
    setEditNome(campanha.nome);
    setEditHorIni(campanha.horario_inicio.slice(0, 5));
    setEditHorFim(campanha.horario_fim.slice(0, 5));
    setEditLimite(campanha.limite_diario_total?.toString() || '');
    setEditCooldown(campanha.cooldown_dias);
    setEditObs(campanha.observacao || '');
    setEditDiasInativo(campanha.dias_inativo_min?.toString() || '');
    setEditDiasSemEnvio(campanha.dias_sem_envio?.toString() || '');
    setEditMaxTent(campanha.max_tentativas_categoria?.toString() || '');
  }, [campanha]);

  // Templates da campanha
  const { data: templates, refetch: refetchTpls } = useQuery({
    queryKey: ['templates_campanha', campanha?.id],
    enabled: !!campanha?.id && open,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('templates_msg')
        .select('id, campanha_id, categoria, subcategoria, ordem, texto, ativo, anexo_url, anexo_tipo, observacao')
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
      return ((instsRes.data || []) as any[])
        .filter((i: any) => i.nome !== 'Instancia ADMIN')
        .map((i: any) => ({
          ...i,
          ativa: ci[i.id]?.ativa !== false, // default true se não existe linha
          limite_diario_instancia: ci[i.id]?.limite_diario_instancia ?? null,
        }));
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
    if (limite !== campanha.limite_diario_total) changes.limite_diario_total = limite;
    if (editCooldown !== campanha.cooldown_dias) changes.cooldown_dias = editCooldown;
    if (editObs !== (campanha.observacao || '')) changes.observacao = editObs.trim() || null;
    const diasInativo = editDiasInativo.trim() === '' ? null : parseInt(editDiasInativo, 10);
    const diasSemEnvio = editDiasSemEnvio.trim() === '' ? null : parseInt(editDiasSemEnvio, 10);
    const maxTent = editMaxTent.trim() === '' ? null : parseInt(editMaxTent, 10);
    if (diasInativo !== campanha.dias_inativo_min) changes.dias_inativo_min = diasInativo;
    if (diasSemEnvio !== campanha.dias_sem_envio) changes.dias_sem_envio = diasSemEnvio;
    if (maxTent !== campanha.max_tentativas_categoria) changes.max_tentativas_categoria = maxTent;
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

  const setLimiteInstancia = async (instId: string, valor: string) => {
    const num = valor.trim() === '' ? null : parseInt(valor, 10);
    const { error } = await supabase
      .from('campanha_instancia' as any)
      .upsert({ campanha_id: campanha.id, instancia_id: instId, limite_diario_instancia: num },
              { onConflict: 'campanha_id,instancia_id' });
    if (error) { toast.error(error.message); return; }
    refetchMatriz();
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
              <div className="space-y-1">
                <Label className="text-xs">Limite diário total</Label>
                <Input type="number" value={editLimite} onChange={e => setEditLimite(e.target.value)} placeholder="sem limite" />
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
              <div className="space-y-1">
                <Label className="text-xs">Observação</Label>
                <Input value={editObs} onChange={e => setEditObs(e.target.value)} placeholder="ex: BlackFriday 2026" />
              </div>
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
                  <div className="space-y-1">
                    <Label className="text-xs">Dias sem compra (mínimo)</Label>
                    <Input
                      type="number"
                      value={editDiasInativo}
                      onChange={e => setEditDiasInativo(e.target.value)}
                      placeholder="ex: 30"
                    />
                    <p className="text-[10px] text-muted-foreground">Cliente só entra se está há pelo menos X dias sem comprar (<code className="font-mono">data_cliente</code>).</p>
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Dias sem receber esta campanha</Label>
                    <Input
                      type="number"
                      value={editDiasSemEnvio}
                      onChange={e => setEditDiasSemEnvio(e.target.value)}
                      placeholder="ex: 30"
                    />
                    <p className="text-[10px] text-muted-foreground">Gap entre envios de RMKT pro mesmo contato (<code className="font-mono">data_ultimo_rmkt</code>). Diferente do cooldown — não afeta outras campanhas.</p>
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
                            value={i.limite_diario_instancia ?? ''}
                            onChange={e => setLimiteInstancia(i.id, e.target.value)}
                            placeholder="—"
                            className="w-20 ml-auto text-right text-sm"
                          />
                        </td>
                      </tr>
                    );})}
                  </tbody>
                </table>
              </div>
              <p className="text-[10px] text-muted-foreground">
                Pausar instância em <code className="font-mono">/instancias</code> sobrepõe esses toggles — workflows nem tentam usar instância pausada. Os toggles aqui só importam quando a instância está online.
              </p>
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
                            {tpl.observacao && <span className="text-[10px] text-muted-foreground">{tpl.observacao}</span>}
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

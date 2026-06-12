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

  // Agrupa templates por subcategoria pra exibição
  const tplGroups: Array<{ key: string; label: string; items: TemplateRow[] }> = (() => {
    if (campanha.tipo !== 'followup') {
      return [{ key: 'all', label: 'Templates', items: templates || [] }];
    }
    return FOLLOWUP_SUBS.map(sub => ({
      key: sub,
      label: `Follow-up ${sub}`,
      items: (templates || []).filter(t => t.subcategoria === sub),
    }));
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
              <div className="grid grid-cols-2 gap-2">
                <div className="space-y-1">
                  <Label className="text-xs">Limite diário total</Label>
                  <Input type="number" value={editLimite} onChange={e => setEditLimite(e.target.value)} placeholder="sem limite" />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Cooldown (dias)</Label>
                  <Input type="number" value={editCooldown} onChange={e => setEditCooldown(parseInt(e.target.value) || 0)} />
                  <p className="text-[10px] text-muted-foreground">Mesmo contato não recebe outra campanha em X dias</p>
                </div>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Observação</Label>
                <Input value={editObs} onChange={e => setEditObs(e.target.value)} placeholder="ex: BlackFriday 2026" />
              </div>
              <Button className="w-full" onClick={saveConfig} disabled={saving}>
                {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
                Salvar configurações
              </Button>
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
                    {matrizData?.map((i: any) => (
                      <tr key={i.id} className="border-t">
                        <td className="px-3 py-2">
                          <p className="font-medium">Instância {i.nome}</p>
                          <p className="text-[10px] text-muted-foreground">{i.status}</p>
                        </td>
                        <td className="text-center px-2 py-2">
                          <Switch checked={i.ativa} onCheckedChange={(v) => toggleInstancia(i.id, v)} />
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
                    ))}
                  </tbody>
                </table>
              </div>
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
                    setTplSubcat(campanha.tipo === 'followup' ? '24h' : null);
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

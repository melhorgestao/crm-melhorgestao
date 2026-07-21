/**
 * CRUD de cupons aplicados automaticamente pelo agent-closing.
 * Regras: estado do cliente (anterior ao em_fechamento) + canal atual.
 * NUNCA aplica em C-REP (regra hardcoded no RPC cupom_para_contato).
 */
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Plus, Pencil, Trash2, Loader2 } from 'lucide-react';
import { toast } from 'sonner';

interface Cupom {
  id: string;
  nome: string;
  desconto_pct: number;
  estados_cliente: string[];
  canais_cliente: string[];
  /** Estágios de RMKT em que vale (1,2,3). Vazio = qualquer estágio. */
  rmkt_estagios: number[];
  /** Estágios de follow-up em que vale (1,2,3). Vazio = qualquer estágio. */
  followup_estagios: number[];
  expira_em: string | null;
  ativo: boolean;
  observacao: string | null;
}

const ESTAGIOS = [1, 2, 3];

const ESTADOS_OPTS: Array<{ key: string; label: string; hint?: string }> = [
  { key: '*',                 label: 'Todos' },
  { key: 'novo',              label: 'Novo (sem estado)' },
  { key: 'cliente',           label: 'Cliente', hint: 'inclui cliente_pendente' },
  { key: 'ativacao_contatos', label: 'Ativação' },
  { key: 'rmkt',              label: 'RMKT' },
  { key: 'followup',          label: 'Follow-up', hint: 'inclui wait_follow_up' },
];

const CANAIS_OPTS: Array<{ key: string; label: string; hint?: string }> = [
  { key: '*',    label: 'Todos' },
  { key: 'BASE', label: 'BASE' },
  { key: 'ADS',  label: 'ADS' },
  { key: 'REP',  label: 'REP', hint: 'C-REP não recebe cupom' },
];

export function CuponsManager() {
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<Cupom | null>(null);

  const { data: cupons = [], refetch, isLoading } = useQuery({
    queryKey: ['cupons-admin'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('cupons')
        .select('*')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data || []) as Cupom[];
    },
  });

  const handleNovo = () => {
    setEditing({
      id: '', nome: '', desconto_pct: 10,
      estados_cliente: ['*'], canais_cliente: ['*'],
      rmkt_estagios: [], followup_estagios: [],
      expira_em: null, ativo: true, observacao: null,
    });
    setOpen(true);
  };

  const handleEdit = (c: Cupom) => { setEditing(c); setOpen(true); };

  const handleDelete = async (c: Cupom) => {
    if (!confirm(`Remover cupom "${c.nome}"?`)) return;
    const { error } = await supabase.from('cupons').delete().eq('id', c.id);
    if (error) return toast.error(error.message);
    toast.success('Cupom removido');
    refetch();
  };

  const toggleAtivo = async (c: Cupom) => {
    await supabase.from('cupons').update({ ativo: !c.ativo }).eq('id', c.id);
    refetch();
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs font-medium uppercase text-muted-foreground tracking-wide">Cupons automáticos</p>
          <p className="text-[10px] text-muted-foreground">
            Aplicados pelo agent-closing antes de gerar o resumo. Maior desconto vence em caso de match múltiplo.
          </p>
        </div>
        <Button size="sm" onClick={handleNovo}>
          <Plus className="w-3.5 h-3.5 mr-1" /> Novo cupom
        </Button>
      </div>

      {isLoading && <Loader2 className="w-4 h-4 animate-spin" />}

      <div className="space-y-2">
        {cupons.length === 0 && !isLoading && (
          <p className="text-xs text-muted-foreground italic px-2 py-6 text-center border border-dashed rounded">
            Nenhum cupom cadastrado.
          </p>
        )}
        {cupons.map(c => (
          <div key={c.id} className="border rounded-lg p-3 bg-muted/20 flex items-center gap-3">
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <p className="font-bold text-sm">{c.nome}</p>
                <Badge className="bg-emerald-600 text-white">{c.desconto_pct}% OFF</Badge>
                {c.expira_em && (
                  <Badge variant="outline" className="text-[10px]">
                    expira {new Date(c.expira_em).toLocaleDateString()}
                  </Badge>
                )}
              </div>
              <p className="text-[11px] text-muted-foreground mt-0.5">
                Estado: {c.estados_cliente.map(e => labelEstado(e)).join(', ')} · Canal: {c.canais_cliente.map(k => labelCanal(k)).join(', ')}
                {c.rmkt_estagios?.length > 0 && ` · RMKT ${c.rmkt_estagios.join('/')}`}
                {c.followup_estagios?.length > 0 && ` · Follow-up ${c.followup_estagios.join('/')}`}
              </p>
            </div>
            <Switch checked={c.ativo} onCheckedChange={() => toggleAtivo(c)} />
            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleEdit(c)}>
              <Pencil className="w-3.5 h-3.5" />
            </Button>
            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleDelete(c)}>
              <Trash2 className="w-3.5 h-3.5" />
            </Button>
          </div>
        ))}
      </div>

      <CupomModal
        open={open}
        onClose={() => { setOpen(false); setEditing(null); refetch(); }}
        cupom={editing}
      />
    </div>
  );
}

function labelEstado(k: string): string {
  return ESTADOS_OPTS.find(o => o.key === k)?.label || k;
}
function labelCanal(k: string): string {
  return CANAIS_OPTS.find(o => o.key === k)?.label || k;
}

function CupomModal({ open, onClose, cupom }: { open: boolean; onClose: () => void; cupom: Cupom | null }) {
  const [nome, setNome] = useState('');
  const [pct, setPct] = useState(10);
  const [estados, setEstados] = useState<string[]>(['*']);
  const [canais, setCanais] = useState<string[]>(['*']);
  const [rmktEst, setRmktEst] = useState<number[]>([]);
  const [fupEst, setFupEst] = useState<number[]>([]);
  const [expira, setExpira] = useState<string>('');
  const [saving, setSaving] = useState(false);

  // Sincroniza o form toda vez que abre / troca de cupom.
  // ERA useState(fn): inicializador preguiçoso roda UMA vez só — como o modal
  // fica sempre montado, "Editar" abria com os campos em branco e salvar
  // sobrescrevia o cupom com os valores padrão.
  useEffect(() => {
    if (!open || !cupom) return;
    setNome(cupom.nome);
    setPct(cupom.desconto_pct);
    setEstados(cupom.estados_cliente?.length ? cupom.estados_cliente : ['*']);
    setCanais(cupom.canais_cliente?.length ? cupom.canais_cliente : ['*']);
    setRmktEst(cupom.rmkt_estagios || []);
    setFupEst(cupom.followup_estagios || []);
    setExpira(cupom.expira_em ? cupom.expira_em.slice(0, 10) : '');
  }, [open, cupom]);

  if (!open || !cupom) return null;

  const toggleArr = (arr: string[], k: string, setter: (a: string[]) => void) => {
    if (k === '*') return setter(['*']);
    let next = arr.filter(x => x !== '*');
    if (next.includes(k)) next = next.filter(x => x !== k);
    else next = [...next, k];
    if (next.length === 0) next = ['*'];
    setter(next);
  };

  const handleSave = async () => {
    if (!nome.trim()) return toast.error('Nome obrigatório');
    if (pct <= 0 || pct > 100) return toast.error('Desconto entre 1 e 100');
    setSaving(true);
    const payload = {
      nome: nome.trim(),
      desconto_pct: pct,
      estados_cliente: estados,
      canais_cliente: canais,
      // Estágio só faz sentido se o cupom mira aquele grupo (ou 'Todos').
      // Fora disso salva vazio = qualquer estágio.
      rmkt_estagios:     (estados.includes('rmkt')     || estados.includes('*')) ? rmktEst : [],
      followup_estagios: (estados.includes('followup') || estados.includes('*')) ? fupEst  : [],
      expira_em: expira ? new Date(expira).toISOString() : null,
      ativo: true,
    };
    const op = cupom.id
      ? supabase.from('cupons').update(payload).eq('id', cupom.id)
      : supabase.from('cupons').insert(payload);
    const { error } = await op;
    setSaving(false);
    if (error) return toast.error(error.message);
    toast.success(cupom.id ? 'Cupom atualizado' : 'Cupom criado');
    onClose();
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>{cupom.id ? 'Editar cupom' : 'Novo cupom'}</DialogTitle></DialogHeader>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label className="text-xs">Nome</Label>
              <Input value={nome} onChange={e => setNome(e.target.value)} placeholder="ex: ATIVACAO10" />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Desconto %</Label>
              <Input type="number" min={1} max={100} value={pct} onChange={e => setPct(parseInt(e.target.value) || 0)} />
            </div>
          </div>

          <div className="space-y-1">
            <Label className="text-xs">Estado do cliente (anterior ao fechamento)</Label>
            <div className="grid grid-cols-2 gap-1.5">
              {ESTADOS_OPTS.map(o => (
                <label key={o.key} className="flex items-center gap-2 cursor-pointer text-xs border rounded p-1.5 bg-muted/20">
                  {/* Sem 'disabled': marcar um estado específico desliga o
                      'Todos' automaticamente (toggleArr remove o '*'). */}
                  <input
                    type="checkbox"
                    checked={estados.includes(o.key)}
                    onChange={() => toggleArr(estados, o.key, setEstados)}
                  />
                  <span>{o.label}{o.hint && <span className="text-muted-foreground text-[10px]"> ({o.hint})</span>}</span>
                </label>
              ))}
            </div>
          </div>

          {/* Estágio de RMKT / Follow-up: permite cupom agressivo só no último
              disparo (ex: 40% no Follow-up 3 pra não perder o lead). */}
          {(['rmkt', 'followup'] as const).map(grupo => {
            const ativo = estados.includes(grupo) || estados.includes('*');
            if (!ativo) return null;
            const isRmkt = grupo === 'rmkt';
            const sel = isRmkt ? rmktEst : fupEst;
            const setSel = isRmkt ? setRmktEst : setFupEst;
            const nome = isRmkt ? 'RMKT' : 'Follow-up';
            const toggle = (n: number) =>
              setSel(sel.includes(n) ? sel.filter(x => x !== n) : [...sel, n].sort());
            return (
              <div key={grupo} className="space-y-1">
                <Label className="text-xs">
                  Estágio do {nome}
                  <span className="text-muted-foreground text-[10px] font-normal">
                    {' '}— quantas mensagens o lead já recebeu (vazio = qualquer estágio)
                  </span>
                </Label>
                <div className="flex gap-1.5">
                  {ESTAGIOS.map(n => (
                    <label
                      key={n}
                      className="flex items-center gap-1.5 cursor-pointer text-xs border rounded px-3 py-1.5 bg-muted/20"
                    >
                      <input type="checkbox" checked={sel.includes(n)} onChange={() => toggle(n)} />
                      <span>{nome} {n}</span>
                    </label>
                  ))}
                </div>
                {sel.length > 0 && (
                  <p className="text-[10px] text-muted-foreground">
                    Só vale pra quem está {sel.length === 1 ? 'no' : 'nos'} {nome} {sel.join(', ')}.
                  </p>
                )}
              </div>
            );
          })}

          <div className="space-y-1">
            <Label className="text-xs">Canal atual do cliente</Label>
            <div className="grid grid-cols-2 gap-1.5">
              {CANAIS_OPTS.map(o => (
                <label key={o.key} className="flex items-center gap-2 cursor-pointer text-xs border rounded p-1.5 bg-muted/20">
                  {/* Sem 'disabled' — mesmo motivo do bloco de estados. */}
                  <input
                    type="checkbox"
                    checked={canais.includes(o.key)}
                    onChange={() => toggleArr(canais, o.key, setCanais)}
                  />
                  <span>{o.label}{o.hint && <span className="text-muted-foreground text-[10px]"> ({o.hint})</span>}</span>
                </label>
              ))}
            </div>
          </div>

          <div className="space-y-1">
            <Label className="text-xs">Expira em (vazio = sem expiração)</Label>
            <Input type="date" value={expira} onChange={e => setExpira(e.target.value)} />
          </div>

          <div className="flex gap-2 pt-2">
            <Button variant="outline" className="flex-1" onClick={onClose}>Cancelar</Button>
            <Button className="flex-1 bg-sf-green hover:bg-sf-green/90" onClick={handleSave} disabled={saving}>
              {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
              {cupom.id ? 'Salvar' : 'Criar'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

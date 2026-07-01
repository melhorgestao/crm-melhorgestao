/**
 * Modal de VENDA disparado pelos cards do Kanban (Sinal Certo no fechamento
 * ou 🛒 no suporte). Tipo travado em Venda, contato travado (endereço editável).
 * Layout espelha o modal do Financeiro (Status, Sócio/Caixa, Canal, Modalidade).
 * Reusa a mesma RPC criar_pedido_v2.
 */
import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Separator } from '@/components/ui/separator';
import { Loader2, Plus, Trash2, ShoppingCart } from 'lucide-react';
import { toast } from 'sonner';
import { getProductDisplayName } from '@/lib/productDisplayNames';
import { cn } from '@/lib/utils';

interface Props {
  open: boolean;
  onClose: () => void;
  contato: { id: string; nome: string; telefone?: string | null; canal_atual?: string | null; canal_origem?: string | null } | null;
  onDone: () => void;
}

const MODALIDADES = [
  { v: 'mini',         label: 'Mini' },
  { v: 'pac',          label: 'PAC' },
  { v: 'sedex',        label: 'SEDEX' },
  { v: 'entrega_maos', label: 'Entrega em Mãos' },
];

const CANAIS = ['ADS', 'BASE', 'REP', 'C-REP'];

export function FechamentoVendaModal({ open, onClose, contato, onDone }: Props) {
  const [produtos, setProdutos] = useState<any[]>([]);
  const [ufsCadastradas, setUfsCadastradas] = useState<string[]>([]);
  const [socios, setSocios] = useState<{ key: string; nome: string }[]>([]);
  const [caixas, setCaixas] = useState<{ codigo: string; apelido: string }[]>([]);

  const [statusPagamento, setStatusPagamento] = useState<'pago' | 'pendente'>('pago');
  const [socioSel, setSocioSel] = useState<string>('V');
  const [canal, setCanal] = useState<string>('ADS');
  const [rows, setRows] = useState<{ produto_id: string; quantidade: number }[]>([{ produto_id: '', quantidade: 1 }]);
  const [modalidade, setModalidade] = useState('mini');
  const [ufPostagem, setUfPostagem] = useState('');
  const [valorManual, setValorManual] = useState<string>('');
  const [obs, setObs] = useState('');
  const [end, setEnd] = useState({ endereco: '', numero: '', complemento: '', bairro: '', cidade: '', uf: '', cep: '' });
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open || !contato) return;
    setLoading(true);
    (async () => {
      const [prodsRes, ctRes, ufsRes, sociosRes, caixasRes] = await Promise.all([
        supabase.from('produtos').select('*').eq('ativo', true).order('preco', { ascending: true }),
        supabase.from('contatos').select('endereco, numero, complemento, bairro, cidade, uf, cidade_uf, cep, observacao, canal_atual, canal_origem').eq('id', contato.id).maybeSingle(),
        supabase.from('estoque_ufs' as any).select('uf').order('uf'),
        supabase.from('socios' as any).select('key, nome').order('key'),
        supabase.from('caixas' as any).select('codigo, apelido').eq('ativo', true).order('codigo'),
      ]);
      setProdutos(prodsRes.data || []);
      setUfsCadastradas(((ufsRes.data || []) as any[]).map(r => r.uf).filter(Boolean));
      setSocios(((sociosRes.data || []) as any[]) || []);
      setCaixas(((caixasRes.data || []) as any[]) || []);

      const c: any = ctRes.data;
      if (c) {
        setEnd({
          endereco: c.endereco || '', numero: c.numero || '', complemento: c.complemento || '',
          bairro: c.bairro || '', cidade: c.cidade || '',
          uf: c.uf || (c.cidade_uf ? String(c.cidade_uf).slice(-2) : ''),
          cep: c.cep || '',
        });
        const contatoCanal = c.canal_atual || c.canal_origem || contato.canal_atual || contato.canal_origem || 'ADS';
        setCanal(CANAIS.includes(contatoCanal) ? contatoCanal : 'ADS');
      }
      setRows([{ produto_id: '', quantidade: 1 }]);
      setModalidade('mini'); setUfPostagem(''); setValorManual(''); setObs('');
      setStatusPagamento('pago'); setSocioSel('V');
      setLoading(false);
    })();
  }, [open, contato]);

  const valorAuto = useMemo(() => rows.reduce((s, r) => {
    const p = produtos.find(x => x.id === r.produto_id);
    return s + (p?.preco ? Number(p.preco) * (r.quantidade || 0) : 0);
  }, 0), [rows, produtos]);

  const valorFinal = valorManual !== '' ? Number(valorManual) : valorAuto;

  const setRow = (i: number, patch: Partial<{ produto_id: string; quantidade: number }>) =>
    setRows(rs => rs.map((r, idx) => idx === i ? { ...r, ...patch } : r));

  const submit = async () => {
    if (!contato) return;
    const prodRows = rows.filter(r => r.produto_id);
    if (prodRows.length === 0) { toast.error('Adicione ao menos 1 produto'); return; }
    if (!valorFinal || valorFinal <= 0) { toast.error('Valor inválido'); return; }
    setSaving(true);
    try {
      await supabase.from('contatos').update({
        endereco: end.endereco || null, numero: end.numero || null, complemento: end.complemento || null,
        bairro: end.bairro || null, cidade: end.cidade || null, uf: end.uf || null, cep: end.cep || null,
        updated_at: new Date().toISOString(),
      }).eq('id', contato.id);

      const produtosRpc = prodRows.map(r => {
        const p = produtos.find(x => x.id === r.produto_id);
        const preco = p?.preco != null ? Number(p.preco) : null;
        return { produto: getProductDisplayName(p || {}), produto_id: r.produto_id, quantidade: r.quantidade, valor_unit: preco, preco };
      });
      const canalPedido = canal === 'C-REP' ? 'REP' : canal;

      const { data, error } = await supabase.rpc('criar_pedido_v2' as any, {
        p_contato_id: contato.id,
        p_canal: canalPedido,
        p_valor: valorFinal,
        p_status_pagamento: statusPagamento,
        p_modalidade: modalidade,
        p_uf_postagem: ufPostagem || null,
        p_criado_por: (socioSel || 'V').toLowerCase(),
        p_obs: obs || null,
        p_produtos: produtosRpc,
      });
      if (error) throw error;
      const r = data as any;
      if (r && r.ok === false) throw new Error(r.error || 'falha ao criar pedido');

      toast.success(statusPagamento === 'pago' ? 'Venda registrada!' : 'Venda pendente registrada!');
      onDone();
      onClose();
    } catch (e: any) {
      toast.error('Erro: ' + (e.message || e));
    } finally {
      setSaving(false);
    }
  };

  const showSocio = statusPagamento === 'pago';

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o && !saving) onClose(); }}>
      <DialogContent className="max-w-md max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <ShoppingCart className="w-5 h-5 text-sf-green" /> Venda — {contato?.nome}
          </DialogTitle>
        </DialogHeader>

        {loading ? (
          <div className="py-10 flex justify-center"><Loader2 className="w-6 h-6 animate-spin" /></div>
        ) : (
          <div className="space-y-4 py-2">
            {/* Tipo travado (Venda) */}
            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Tipo</Label>
              <Input value="Venda" disabled className="min-h-[44px] font-medium mt-1" />
            </div>

            {/* Status pago/pendente */}
            <div className="flex items-center justify-between">
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Status</Label>
              <div className="flex items-center gap-2">
                <span className={cn('text-sm font-medium', statusPagamento === 'pendente' ? 'text-orange-500' : 'text-primary')}>
                  {statusPagamento === 'pago' ? 'Pago' : 'Pendente'}
                </span>
                <Switch
                  checked={statusPagamento === 'pago'}
                  onCheckedChange={v => setStatusPagamento(v ? 'pago' : 'pendente')}
                  className="data-[state=checked]:bg-sf-green"
                />
              </div>
            </div>

            <Separator />

            {/* Sócio / Caixa — só se pago */}
            {showSocio && (socios.length > 0 || caixas.length > 0) && (
              <div>
                <Label className="text-xs text-muted-foreground uppercase tracking-wide">Sócio / Caixa</Label>
                <div className="flex flex-wrap gap-2 mt-1">
                  {socios.map(s => (
                    <Button key={s.key} variant={socioSel === s.key ? 'default' : 'outline'}
                            className="min-h-[44px] flex-1" onClick={() => setSocioSel(s.key)}>
                      {s.nome || s.key}
                    </Button>
                  ))}
                  {caixas.map(c => (
                    <Button key={c.codigo}
                            variant={socioSel === c.codigo ? 'default' : 'outline'}
                            className={cn('min-h-[44px] flex-1',
                              socioSel === c.codigo
                                ? 'bg-amber-600 hover:bg-amber-700 text-white'
                                : 'border-amber-300 text-amber-700 hover:bg-amber-50 dark:hover:bg-amber-950/30')}
                            onClick={() => setSocioSel(c.codigo)}>
                      🏪 {c.apelido}
                    </Button>
                  ))}
                </div>
              </div>
            )}

            <Separator />

            {/* Contato travado */}
            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Contato</Label>
              <Input value={contato?.nome || ''} disabled className="min-h-[44px] mt-1" />
            </div>

            {/* Canal */}
            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Canal</Label>
              <Select value={canal} onValueChange={setCanal}>
                <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {CANAIS.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>

            {/* Produtos */}
            <div className="space-y-2">
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Produtos</Label>
              {rows.map((r, i) => (
                <div key={i} className="flex gap-2 items-center">
                  <Select value={r.produto_id} onValueChange={v => setRow(i, { produto_id: v })}>
                    <SelectTrigger className="flex-1"><SelectValue placeholder="Selecione o produto" /></SelectTrigger>
                    <SelectContent>
                      {produtos.map(p => (
                        <SelectItem key={p.id} value={p.id}>
                          {getProductDisplayName(p)} — R$ {Number(p.preco || 0).toFixed(0)}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Input type="number" min={1} value={r.quantidade} className="w-16"
                         onChange={e => setRow(i, { quantidade: parseInt(e.target.value) || 1 })} />
                  {rows.length > 1 && (
                    <Button variant="ghost" size="icon" className="h-8 w-8 shrink-0"
                            onClick={() => setRows(rs => rs.filter((_, idx) => idx !== i))}>
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  )}
                </div>
              ))}
              <Button variant="outline" size="sm"
                      onClick={() => setRows(rs => [...rs, { produto_id: '', quantidade: 1 }])}>
                <Plus className="w-3.5 h-3.5 mr-1" /> Adicionar produto
              </Button>
            </div>

            {/* Modalidade + UF postagem */}
            <div className="flex gap-3">
              <div className="flex-1 space-y-1">
                <Label className="text-xs text-muted-foreground uppercase tracking-wide">Modalidade</Label>
                <Select value={modalidade} onValueChange={setModalidade}>
                  <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {MODALIDADES.map(m => <SelectItem key={m.v} value={m.v}>{m.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="w-36 space-y-1">
                <Label className="text-xs text-muted-foreground uppercase tracking-wide">UF postagem</Label>
                <Select value={ufPostagem} onValueChange={setUfPostagem}>
                  <SelectTrigger className="min-h-[44px]"><SelectValue placeholder="Origem" /></SelectTrigger>
                  <SelectContent>
                    {ufsCadastradas.length === 0 ? (
                      <div className="px-2 py-1.5 text-xs text-muted-foreground">Nenhuma UF cadastrada</div>
                    ) : ufsCadastradas.map(uf => (
                      <SelectItem key={uf} value={uf}>{uf}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            {/* Endereço (editável, pré-preenchido) */}
            <div className="space-y-2 border rounded-lg p-3 bg-muted/20">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Endereço de entrega</p>
              <div className="flex gap-2">
                <Input className="flex-1" placeholder="Endereço" value={end.endereco} onChange={e => setEnd({ ...end, endereco: e.target.value })} />
                <Input className="w-20" placeholder="Nº" value={end.numero} onChange={e => setEnd({ ...end, numero: e.target.value })} />
              </div>
              <div className="flex gap-2">
                <Input className="flex-1" placeholder="Complemento" value={end.complemento} onChange={e => setEnd({ ...end, complemento: e.target.value })} />
                <Input className="flex-1" placeholder="Bairro" value={end.bairro} onChange={e => setEnd({ ...end, bairro: e.target.value })} />
              </div>
              <div className="flex gap-2">
                <Input className="flex-1" placeholder="Cidade" value={end.cidade} onChange={e => setEnd({ ...end, cidade: e.target.value })} />
                <Input className="w-16" placeholder="UF" maxLength={2} value={end.uf} onChange={e => setEnd({ ...end, uf: e.target.value.toUpperCase().slice(0, 2) })} />
                <Input className="w-28" placeholder="CEP" value={end.cep} onChange={e => setEnd({ ...end, cep: e.target.value })} />
              </div>
            </div>

            {/* Valor */}
            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Valor total (R$)</Label>
              <Input type="number" step="0.01" value={valorManual} placeholder={valorAuto.toFixed(2)}
                     onChange={e => setValorManual(e.target.value)} className="min-h-[44px] mt-1" />
              <p className="text-[10px] text-muted-foreground mt-0.5">Auto: R$ {valorAuto.toFixed(2)} (edite se precisar)</p>
            </div>

            {/* Observação */}
            <Input placeholder="Observação (opcional)" value={obs} onChange={e => setObs(e.target.value)} />

            <div className="flex gap-2 pt-2">
              <Button variant="outline" className="flex-1" onClick={onClose} disabled={saving}>Cancelar</Button>
              <Button className={cn('flex-1',
                statusPagamento === 'pago'
                  ? 'bg-sf-green hover:bg-sf-green/90'
                  : 'bg-orange-500 hover:bg-orange-600 text-white')}
                      onClick={submit} disabled={saving}>
                {saving ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <ShoppingCart className="w-4 h-4 mr-1" />}
                {statusPagamento === 'pago' ? 'Registrar Venda' : 'Registrar Pendente'}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

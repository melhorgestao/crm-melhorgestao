/**
 * Modal de VENDA disparado pelo botão [Sinal Certo] no card de FECHAMENTO
 * do Kanban. Tipo travado em "Venda", contato travado (só endereço editável).
 * Reusa a RPC criar_pedido_v2 (mesma do Financeiro).
 */
import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Loader2, Plus, Trash2, ShoppingCart } from 'lucide-react';
import { toast } from 'sonner';
import { getProductDisplayName } from '@/lib/productDisplayNames';

interface Props {
  open: boolean;
  onClose: () => void;
  contato: { id: string; nome: string; telefone?: string | null; canal_atual?: string | null; canal_origem?: string | null } | null;
  onDone: () => void;
}

const MODALIDADES = [
  { v: 'mini', label: 'Mini (envio)' },
  { v: 'caixa_p', label: 'Caixa P (envio)' },
  { v: 'entrega_maos', label: 'Entrega em mãos' },
];

export function FechamentoVendaModal({ open, onClose, contato, onDone }: Props) {
  const [produtos, setProdutos] = useState<any[]>([]);
  const [ufsCadastradas, setUfsCadastradas] = useState<string[]>([]);
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
      const [{ data: prods }, { data: c }, ufsRes] = await Promise.all([
        supabase.from('produtos').select('*').eq('ativo', true).order('preco', { ascending: true }),
        supabase.from('contatos').select('endereco, numero, complemento, bairro, cidade, uf, cidade_uf, cep, observacao').eq('id', contato.id).maybeSingle(),
        supabase.from('estoque_ufs' as any).select('uf').order('uf'),
      ]);
      setProdutos(prods || []);
      setUfsCadastradas(((ufsRes.data || []) as any[]).map(r => r.uf).filter(Boolean));
      if (c) {
        setEnd({
          endereco: c.endereco || '', numero: (c as any).numero || '', complemento: c.complemento || '',
          bairro: c.bairro || '', cidade: c.cidade || '', uf: c.uf || (c.cidade_uf ? String(c.cidade_uf).slice(-2) : ''),
          cep: c.cep || '',
        });
      }
      setRows([{ produto_id: '', quantidade: 1 }]);
      setModalidade('mini'); setUfPostagem(''); setValorManual(''); setObs('');
      setLoading(false);
    })();
  }, [open, contato]);

  const valorAuto = useMemo(() => {
    return rows.reduce((s, r) => {
      const p = produtos.find(x => x.id === r.produto_id);
      return s + (p?.preco ? Number(p.preco) * (r.quantidade || 0) : 0);
    }, 0);
  }, [rows, produtos]);

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
      // 1) atualiza endereço do contato (editável)
      await supabase.from('contatos').update({
        endereco: end.endereco || null, numero: end.numero || null, complemento: end.complemento || null,
        bairro: end.bairro || null, cidade: end.cidade || null, uf: end.uf || null, cep: end.cep || null,
        updated_at: new Date().toISOString(),
      }).eq('id', contato.id);

      // 2) monta produtos + canal
      const produtosRpc = prodRows.map(r => {
        const p = produtos.find(x => x.id === r.produto_id);
        const preco = p?.preco != null ? Number(p.preco) : null;
        return { produto: getProductDisplayName(p || {}), produto_id: r.produto_id, quantidade: r.quantidade, valor_unit: preco, preco };
      });
      const canal = (contato.canal_atual || contato.canal_origem || 'BASE');
      const canalPedido = canal === 'C-REP' ? 'REP' : canal;

      // 3) cria pedido (mesma RPC do Financeiro)
      const { data, error } = await supabase.rpc('criar_pedido_v2' as any, {
        p_contato_id: contato.id,
        p_canal: canalPedido,
        p_valor: valorFinal,
        p_status_pagamento: 'pago',
        p_modalidade: modalidade,
        p_uf_postagem: ufPostagem || null,
        p_obs: obs || null,
        p_produtos: produtosRpc,
      });
      if (error) throw error;
      const r = data as any;
      if (r && r.ok === false) throw new Error(r.error || 'falha ao criar pedido');

      toast.success('Venda registrada! Pedido criado.');
      onDone();
      onClose();
    } catch (e: any) {
      toast.error('Erro: ' + (e.message || e));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o && !saving) onClose(); }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <ShoppingCart className="w-5 h-5 text-sf-green" /> Venda — {contato?.nome}
          </DialogTitle>
        </DialogHeader>

        {loading ? (
          <div className="py-10 flex justify-center"><Loader2 className="w-6 h-6 animate-spin" /></div>
        ) : (
          <div className="space-y-4 py-2">
            {/* Tipo travado */}
            <div className="flex gap-3">
              <div className="flex-1 space-y-1">
                <Label className="text-xs">Tipo</Label>
                <Input value="Venda" disabled className="font-medium" />
              </div>
              <div className="flex-1 space-y-1">
                <Label className="text-xs">Contato</Label>
                <Input value={contato?.nome || ''} disabled />
              </div>
            </div>

            {/* Produtos */}
            <div className="space-y-2">
              <Label className="text-xs">Produtos</Label>
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
              <Button variant="outline" size="sm" onClick={() => setRows(rs => [...rs, { produto_id: '', quantidade: 1 }])}>
                <Plus className="w-3.5 h-3.5 mr-1" /> Adicionar produto
              </Button>
            </div>

            {/* Modalidade + UF postagem */}
            <div className="flex gap-3">
              <div className="flex-1 space-y-1">
                <Label className="text-xs">Modalidade</Label>
                <Select value={modalidade} onValueChange={setModalidade}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {MODALIDADES.map(m => <SelectItem key={m.v} value={m.v}>{m.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="w-32 space-y-1">
                <Label className="text-xs">UF postagem</Label>
                <Select value={ufPostagem} onValueChange={setUfPostagem}>
                  <SelectTrigger><SelectValue placeholder="Origem" /></SelectTrigger>
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

            {/* Endereço (editável) */}
            <div className="space-y-2 border rounded-lg p-3 bg-muted/20">
              <p className="text-xs font-semibold text-muted-foreground">Endereço de entrega</p>
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
            <div className="flex gap-3 items-end">
              <div className="flex-1 space-y-1">
                <Label className="text-xs">Valor total (R$)</Label>
                <Input type="number" step="0.01" value={valorManual} placeholder={valorAuto.toFixed(2)}
                       onChange={e => setValorManual(e.target.value)} />
                <p className="text-[10px] text-muted-foreground">Auto: R$ {valorAuto.toFixed(2)} (edite se precisar)</p>
              </div>
            </div>

            <Input placeholder="Observação (opcional)" value={obs} onChange={e => setObs(e.target.value)} />

            <div className="flex gap-2 pt-2">
              <Button variant="outline" className="flex-1" onClick={onClose} disabled={saving}>Cancelar</Button>
              <Button className="flex-1 bg-sf-green hover:bg-sf-green/90" onClick={submit} disabled={saving}>
                {saving ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <ShoppingCart className="w-4 h-4 mr-1" />}
                Registrar Venda
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

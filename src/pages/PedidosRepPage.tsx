import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Separator } from '@/components/ui/separator';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { toast } from 'sonner';
import { formatBRL, formatDateShort } from '@/lib/format';
import { Plus, Pencil, Trash2, ChevronLeft, ChevronRight, Copy, Loader2, Check } from 'lucide-react';
import { getProductDisplayName } from '@/lib/productDisplayNames';
import { cn, copyToClipboard } from '@/lib/utils';
import { useIsMobile } from '@/hooks/use-mobile';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';

const UF_OPTIONS = [
  'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
  'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SE','SP','TO'
];

export default function PedidosRepPage() {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const isMobile = useIsMobile();
  const [activeTab, setActiveTab] = useState('lista');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('todos');
  const [showForm, setShowForm] = useState(false);
  const [formValor, setFormValor] = useState('');
  const [formModalidade, setFormModalidade] = useState('mini');
  const [formUfPostagem, setFormUfPostagem] = useState('');
  const [formObs, setFormObs] = useState('');
  const [formStatusPagamento, setFormStatusPagamento] = useState<'pago' | 'pendente'>('pago');
  const [formProdutos, setFormProdutos] = useState<{ produto_id: string; quantidade: number }[]>([{ produto_id: '', quantidade: 1 }]);
  const [allProdutos, setAllProdutos] = useState<any[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [detailPedido, setDetailPedido] = useState<any>(null);
  const [entregaEmMaosTarget, setEntregaEmMaosTarget] = useState<any>(null);
  const [debitingStock, setDebitingStock] = useState(false);

  useEffect(() => {
    supabase.from('produtos').select('id, nome_oficial, tag, preco, estoque_atual').eq('ativo', true).then(r => setAllProdutos(r.data || []));
  }, []);

  const { data: pedidos, isLoading } = useQuery({
    queryKey: ['pedidos-rep', user?.id],
    queryFn: async () => {
      const { data } = await supabase
        .from('pedidos')
        .select('*, contatos(nome, telefone, tag_kanban, cpf, endereco, complemento, bairro, cidade_uf, cep)')
        .eq('representante_id', user?.id)
        .order('order_number', { ascending: false });
      return data || [];
    },
    staleTime: 5 * 60 * 1000,
  });

  let filtered = pedidos || [];
  if (search) {
    const s = search.toLowerCase();
    filtered = filtered.filter(p => (p.contatos as any)?.nome?.toLowerCase().includes(s) || (p.contatos as any)?.telefone?.includes(s));
  }
  if (statusFilter !== 'todos') {
    filtered = filtered.filter(p => p.status_pedido === statusFilter);
  }

  const handleCreatePedido = async () => {
    const valor = parseFloat(formValor.replace(',', '.'));
    if (!valor || isNaN(valor)) { toast.error('Valor inválido'); return; }
    setSubmitting(true);
    try {
      const isEntregaEmMaos = formModalidade === 'entrega_maos';

      if (isEntregaEmMaos) {
        const totalQty = formProdutos.reduce((sum, fp) => sum + (fp.quantidade || 1), 0);
        const { data: estoqueData } = await supabase
          .from('lotes')
          .select('id, produto_id, quantidade_atual')
          .eq('representante_id', user?.id)
          .gt('quantidade_atual', 0);

        const estoqueMap: Record<string, number> = {};
        (estoqueData || []).forEach(l => { estoqueMap[l.produto_id] = (estoqueMap[l.produto_id] || 0) + l.quantidade_atual; });

        for (const fp of formProdutos) {
          if (!fp.produto_id) continue;
          const disponivel = estoqueMap[fp.produto_id] || 0;
          if (disponivel < fp.quantidade) {
            const prod = allProdutos.find(p => p.id === fp.produto_id);
            toast.error(`Estoque insuficiente: ${getProductDisplayName(prod || {})} (disponível: ${disponivel})`);
            setSubmitting(false);
            return;
          }
        }

        const { data: pedidoResult, error: pedidoError } = await supabase.from('pedidos').insert({
          contato_id: null,
          representante_id: user?.id,
          valor,
          produto: JSON.stringify(formProdutos.filter(fp => fp.produto_id).map(fp => {
            const prod = allProdutos.find(p => p.id === fp.produto_id);
            return { produto: getProductDisplayName(prod || {}), quantidade: fp.quantidade, preco: prod?.preco || 0 };
          })),
          canal: 'REP',
          status_pedido: 'entregue',
          status_pagamento: formStatusPagamento,
          modalidade: 'entrega_maos',
          uf_postagem: formUfPostagem || null,
          observacao: formObs || null,
          criado_por: profile?.nome || 'Representante',
          entrega_em_maos: true,
          estoque_debitado: false,
        }).select().single();

        if (pedidoError) throw pedidoError;

        for (const fp of formProdutos) {
          if (!fp.produto_id) continue;
          const { data: lotes } = await supabase
            .from('lotes')
            .select('id, quantidade_atual')
            .eq('produto_id', fp.produto_id)
            .eq('representante_id', user?.id)
             .gt('quantidade_atual', 0)
            .order('created_at', { ascending: true });

          let remaining = fp.quantidade;
          for (const lote of lotes || []) {
            if (remaining <= 0) break;
            const debit = Math.min(lote.quantidade_atual, remaining);
            await supabase.from('lotes').update({ quantidade_atual: lote.quantidade_atual - debit }).eq('id', lote.id);
            await supabase.from('estoque_movimentacoes').insert({
              produto_id: fp.produto_id,
              tipo: 'saida',
              quantidade: debit,
              lote_id: lote.id,
              pedido_id: pedidoResult.id,
              representante_id: user?.id,
              criado_por: profile?.nome || 'Representante',
            });
            remaining -= debit;
          }

          await supabase.rpc('update_produto_estoque', { p_produto_id: fp.produto_id });
        }

        toast.success('Pedido de entrega em mãos criado e estoque debitado!');
      } else {
        const produtosRpc = formProdutos.filter(fp => fp.produto_id).map(fp => {
          const prod = allProdutos.find(p => p.id === fp.produto_id);
          return { produto_id: fp.produto_id, nome_oficial: getProductDisplayName(prod || {}), quantidade: fp.quantidade, preco: prod?.preco || 0 };
        });

        const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
        const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

        const body = {
          p_contato_id: null,
          p_canal: 'REP',
          p_valor: valor,
          p_status_pagamento: formStatusPagamento,
          p_modalidade: formModalidade,
          p_uf_postagem: formUfPostagem || null,
          p_criado_por: profile?.nome || 'Representante',
          p_produtos: produtosRpc.length > 0 ? produtosRpc : null,
          p_representante_id: user?.id,
        };

        console.log('REP: criar_pedido body:', body);

        const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/criar_pedido_v2`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`,
            'Prefer': 'return=representation',
          },
          body: JSON.stringify(body),
        });

        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(errorText || 'Erro ao criar pedido');
        }

        toast.success('Pedido criado! Aguardando logística.');
      }

      setShowForm(false);
      resetForm();
      queryClient.invalidateQueries({ queryKey: ['pedidos-rep'] });
    } catch (err: any) {
      toast.error(err.message || 'Erro ao criar pedido');
    } finally {
      setSubmitting(false);
    }
  };

  const resetForm = () => {
    setFormValor(''); setFormModalidade('mini'); setFormUfPostagem(''); setFormObs('');
    setFormStatusPagamento('pago'); setFormProdutos([{ produto_id: '', quantidade: 1 }]);
  };

  if (isLoading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Pedidos</h1>
        <Button onClick={() => { resetForm(); setShowForm(true); }} className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground">
          <Plus className="w-4 h-4 mr-1" /> Novo Pedido
        </Button>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="lista">Todos</TabsTrigger>
          <TabsTrigger value="pendentes">Pendentes</TabsTrigger>
        </TabsList>

        <TabsContent value={activeTab} className="space-y-4">
          {activeTab === 'lista' && (
            <div className="flex flex-wrap gap-3">
              <Input placeholder="Buscar por nome ou telefone..." value={search} onChange={e => setSearch(e.target.value)} className="w-64" />
              <Select value={statusFilter} onValueChange={setStatusFilter}>
                <SelectTrigger className="w-48"><SelectValue placeholder="Status" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="todos">Todos</SelectItem>
                  <SelectItem value="aguardando_rastreio">Aguardando Postagem</SelectItem>
                  <SelectItem value="postado">Postado</SelectItem>
                  <SelectItem value="entregue">Entregue</SelectItem>
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="overflow-x-auto">
            <table className="w-full text-sm table-fixed">
              <thead>
                <tr className="border-b font-bold">
                  <th className="text-left py-2 w-[12%]">Data</th>
                  <th className="text-left py-2 w-[10%]">Pedido</th>
                  <th className="text-left py-2 w-[20%]">Cliente</th>
                  <th className="text-right py-2 w-[15%]">Valor</th>
                  <th className="text-left py-2 w-[15%]">Status</th>
                  <th className="text-left py-2 w-[13%]">Modalidade</th>
                  <th className="py-2 w-[15%]"></th>
                </tr>
              </thead>
              <tbody>
                {filtered.length === 0 && (
                  <tr><td colSpan={7} className="text-center text-muted-foreground py-8">Nenhum pedido encontrado</td></tr>
                )}
                {(activeTab === 'lista' ? filtered : (pedidos || []).filter(p => p.status_pagamento === 'pendente')).map(p => (
                  <tr key={p.id} className="border-b hover:bg-muted/30 cursor-pointer" onClick={() => setDetailPedido(p)}>
                    <td className="py-2 truncate">{formatDateShort(p.data)}</td>
                    <td className="py-2 font-medium">#{p.order_number}</td>
                    <td className="py-2 truncate">{(p.contatos as any)?.nome || '—'}</td>
                    <td className="py-2 text-right font-medium">{formatBRL(Number(p.valor))}</td>
                    <td className="py-2">
                      <Badge variant={p.status_pedido === 'entregue' ? 'default' : p.status_pedido === 'postado' ? 'secondary' : 'outline'}>
                        {p.status_pedido === 'entregue' ? 'Entregue' : p.status_pedido === 'postado' ? 'Postado' : 'Aguardando Postagem'}
                      </Badge>
                      {p.status_pagamento === 'pendente' && <Badge variant="outline" className="ml-1 text-orange-500">Pendente</Badge>}
                      {p.entrega_em_maos && <Badge variant="outline" className="ml-1 text-blue-500">Entrega em Mãos</Badge>}
                    </td>
                    <td className="py-2 text-muted-foreground">{p.modalidade || '—'}</td>
                    <td className="py-2" onClick={e => e.stopPropagation()}>
                      {p.entrega_em_maos && !p.estoque_debitado && (
                        <Button variant="outline" size="sm" className="h-7 text-xs" onClick={() => setEntregaEmMaosTarget(p)}>
                          Atribuir Estoque
                        </Button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </TabsContent>
      </Tabs>

      <Dialog open={showForm} onOpenChange={() => { setShowForm(false); resetForm(); }}>
        <DialogContent className={cn(isMobile ? 'fixed inset-0 max-w-none w-full h-full rounded-none m-0 translate-x-0 translate-y-0 top-0 left-0 flex flex-col' : 'max-w-md max-h-[80vh] overflow-y-auto')}>
          <DialogHeader><DialogTitle>Novo Pedido</DialogTitle></DialogHeader>
          <div className={cn('space-y-4', isMobile ? 'flex-1 overflow-y-auto pb-20 px-1' : '')}>
            <div>
              <Label>Valor (R$)</Label>
              <Input value={formValor} onChange={e => setFormValor(e.target.value)} placeholder="0,00" className="min-h-[44px]" />
            </div>
            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Status Pagamento</Label>
              <div className="flex items-center gap-2 mt-1">
                <span className={cn('text-sm font-medium', formStatusPagamento === 'pendente' ? 'text-orange-500' : 'text-primary')}>
                  {formStatusPagamento === 'pago' ? 'Pago' : 'Pendente'}
                </span>
                <Switch checked={formStatusPagamento === 'pago'} onCheckedChange={v => setFormStatusPagamento(v ? 'pago' : 'pendente')} className="data-[state=checked]:bg-sf-green" />
              </div>
            </div>
            <Separator />
            <div>
              <Label>Produtos</Label>
              {formProdutos.map((fp, idx) => (
                <div key={idx} className="mt-2 flex gap-2">
                  <Select value={fp.produto_id} onValueChange={v => { const n = [...formProdutos]; n[idx].produto_id = v; setFormProdutos(n); }}>
                    <SelectTrigger className="flex-1 min-h-[44px]"><SelectValue placeholder="Produto" /></SelectTrigger>
                    <SelectContent>{allProdutos.map(p => <SelectItem key={p.id} value={p.id}>{getProductDisplayName(p)}</SelectItem>)}</SelectContent>
                  </Select>
                  <Input type="number" min={1} value={fp.quantidade} onChange={e => { const n = [...formProdutos]; n[idx].quantidade = Number(e.target.value); setFormProdutos(n); }} className="w-20 min-h-[44px]" placeholder="Qtd" />
                </div>
              ))}
              <Button variant="link" size="sm" onClick={() => setFormProdutos([...formProdutos, { produto_id: '', quantidade: 1 }])}>+ Adicionar produto</Button>
            </div>
            <Separator />
            <div>
              <Label>Modalidade</Label>
              <Select value={formModalidade} onValueChange={setFormModalidade}>
                <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="mini">Mini</SelectItem>
                  <SelectItem value="pac">PAC</SelectItem>
                  <SelectItem value="sedex">SEDEX</SelectItem>
                  <SelectItem value="entrega_maos">Entrega em Mãos</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {formModalidade !== 'entrega_maos' && (
              <div>
                <Label>Origem (UF Postagem)</Label>
                <Select value={formUfPostagem} onValueChange={setFormUfPostagem}>
                  <SelectTrigger className="min-h-[44px]"><SelectValue placeholder="Selecionar" /></SelectTrigger>
                  <SelectContent>
                    {UF_OPTIONS.map(uf => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            )}
            <div>
              <Label>Observação (Opcional)</Label>
              <Textarea value={formObs} onChange={e => setFormObs(e.target.value)} placeholder="Notas..." className="mt-1 min-h-[80px]" />
            </div>
            <Button onClick={handleCreatePedido} disabled={submitting} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px]">
              {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Criar Pedido'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={!!detailPedido} onOpenChange={() => setDetailPedido(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Detalhes do Pedido #{detailPedido?.order_number}</DialogTitle></DialogHeader>
          {detailPedido && (
            <div className="space-y-2 text-sm">
              <div>
                <strong>Produtos:</strong>
                {(() => {
                  try {
                    const prods = JSON.parse(detailPedido.produto);
                    if (Array.isArray(prods)) return prods.map((p: any, i: number) => <p key={i} className="ml-2">• {p.produto} × {p.quantidade}</p>);
                  } catch {}
                  return <p className="ml-2">{detailPedido.produto} × {detailPedido.quantidade}</p>;
                })()}
              </div>
              <p><strong>Valor:</strong> {formatBRL(Number(detailPedido.valor))}</p>
              <p><strong>Status:</strong> {detailPedido.status_pedido === 'entregue' ? 'Entregue' : detailPedido.status_pedido === 'postado' ? 'Postado' : 'Aguardando Postagem'}</p>
              <p><strong>Rastreio:</strong> {detailPedido.codigo_rastreio || 'Aguardando rastreio'}</p>
              {detailPedido.observacao && <p><strong>Obs:</strong> {detailPedido.observacao}</p>}
            </div>
          )}
        </DialogContent>
      </Dialog>

      <AlertDialog open={!!entregaEmMaosTarget} onOpenChange={() => setEntregaEmMaosTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Atribuir Estoque</AlertDialogTitle>
            <AlertDialogDescription>Debitar estoque do pedido #{entregaEmMaosTarget?.order_number}?</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              disabled={debitingStock}
              onClick={async () => {
                const p = entregaEmMaosTarget;
                setDebitingStock(true);
                try {
                  let prods: any[] = [];
                  try { prods = JSON.parse(p.produto); } catch { /* legacy format */ }
                  if (!Array.isArray(prods)) { toast.error('Formato de produto nao suportado'); setDebitingStock(false); return; }

                  for (const fp of prods) {
                    const prodId = fp.produto_id;
                    const qty = fp.quantidade || 1;
                    if (!prodId) continue;

                    const { data: lotes } = await supabase
                      .from('lotes')
                      .select('id, quantidade_atual')
                      .eq('produto_id', prodId)
                      .eq('representante_id', user?.id)
                      .gt('quantidade_atual', 0)
                      .order('created_at', { ascending: true });

                    let remaining = qty;
                    for (const lote of lotes || []) {
                      if (remaining <= 0) break;
                      const debit = Math.min(lote.quantidade_atual, remaining);
                      await supabase.from('lotes').update({ quantidade_atual: lote.quantidade_atual - debit }).eq('id', lote.id);
                      await supabase.from('estoque_movimentacoes').insert({
                        produto_id: prodId,
                        tipo: 'saida',
                        quantidade: debit,
                        lote_id: lote.id,
                        pedido_id: p.id,
                        representante_id: user?.id,
                        criado_por: profile?.nome || 'Representante',
                      });
                      remaining -= debit;
                    }

                    if (remaining > 0) {
                      toast.error(`Estoque insuficiente para ${fp.produto} (faltam ${remaining})`);
                      setDebitingStock(false);
                      return;
                    }

                    await supabase.rpc('update_produto_estoque', { p_produto_id: prodId });
                  }

                  await supabase.from('pedidos').update({ estoque_debitado: true }).eq('id', p.id);
                  toast.success('Estoque debitado com sucesso!');
                  setEntregaEmMaosTarget(null);
                  queryClient.invalidateQueries({ queryKey: ['pedidos-rep'] });
                } catch (err: any) {
                  toast.error(err.message || 'Erro ao debitar estoque');
                } finally {
                  setDebitingStock(false);
                }
              }}
              className="bg-sf-green text-primary-foreground"
            >
              {debitingStock ? 'Debitando...' : 'Confirmar'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

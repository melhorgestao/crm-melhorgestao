import { useEffect, useState, useMemo } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/hooks/useAuth';
import { useIsMobile } from '@/hooks/use-mobile';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { toast } from 'sonner';
import { formatBRL, formatDateShort } from '@/lib/format';
import { Copy, Download, Trophy, ClipboardCopy, StickyNote, Package } from 'lucide-react';
import { getTagDisplayName } from '@/lib/productDisplayNames';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { cn, copyToClipboard } from '@/lib/utils';

export default function PedidosPage() {
  const { user, profile } = useAuth();
  const isMobile = useIsMobile();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('todos');
  const [filterMode, setFilterMode] = useState<'ano' | 'mes'>('ano');
  const [year, setYear] = useState(new Date().getFullYear());
  const [month, setMonth] = useState(new Date().getMonth() + 1);
  const [selectedContact, setSelectedContact] = useState<any>(null);
  const [contactPedidos, setContactPedidos] = useState<any[]>([]);
  const [detailPedido, setDetailPedido] = useState<any>(null);
  const [activeTab, setActiveTab] = useState('lista');

  // Pendentes
  const [pendentesSearch, setPendentesSearch] = useState('');
  const [marcarPagoTarget, setMarcarPagoTarget] = useState<any>(null);
  const [marcarPagoSocio, setMarcarPagoSocio] = useState<string | null>(null);
  const [markingPago, setMarkingPago] = useState(false);
  const [socios, setSocios] = useState<{ key: string; nome: string }[]>([]);

  // Ranking
  const [rankStart, setRankStart] = useState(new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0]);
  const [rankEnd, setRankEnd] = useState(new Date().toISOString().split('T')[0]);
  const [rankValor, setRankValor] = useState<any[]>([]);
  const [rankQtd, setRankQtd] = useState<any[]>([]);
  const [rankPageV, setRankPageV] = useState(1);
  const [rankPageQ, setRankPageQ] = useState(1);

  const RANK_PER_PAGE = 10;
  const PER_PAGE_FETCH = 50;

  const queryClient = useQueryClient();

  // Realtime: quando qualquer pedido muda no banco (ex: superfrete-sync gravou
  // codigo_rastreio), invalida lista e atualiza o popup aberto se for o caso.
  useEffect(() => {
    const channel = supabase
      .channel('pedidos-realtime-pedidospage')
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'pedidos' }, (payload) => {
        const novo: any = payload.new;
        queryClient.invalidateQueries({ queryKey: ['pedidos_lista'] });
        queryClient.invalidateQueries({ queryKey: ['pedidos_pendentes'] });
        setDetailPedido(prev => (prev && prev.id === novo.id ? { ...prev, ...novo } : prev));
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [queryClient]);

  // Quando o popup abre, busca os dados frescos do banco para mostrar
  // codigo_rastreio mais atual sem depender do snapshot da lista.
  useEffect(() => {
    if (!detailPedido?.id) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('pedidos')
        .select('id, codigo_rastreio, status_pedido, etiqueta_paga, etiqueta_codigo, etiqueta_url')
        .eq('id', detailPedido.id)
        .maybeSingle();
      if (!cancelled && data) {
        setDetailPedido(prev => (prev && prev.id === data.id ? { ...prev, ...data } : prev));
      }
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [detailPedido?.id]);

  // Dynamic socios — tenta perfis via RPC e cai para cadastros da Administração se perfis estiverem vazios
  useEffect(() => {
    let cancelled = false;

    const loadSocios = async () => {
      const [rpcResult, adminContactsResult] = await Promise.all([
        supabase.rpc('listar_socios'),
        supabase
          .from('contatos')
          .select('nome')
          .eq('canal_origem', 'ADMIN')
          .order('created_at', { ascending: true }),
      ]);

      const byKey = new Map<string, { key: string; nome: string }>();

      ((rpcResult.data as any[]) || []).forEach((s: any) => {
        const key = String(s.socio_key || '').trim().toUpperCase();
        const nome = String(s.nome || '').trim();
        if (key && nome) byKey.set(key, { key, nome });
      });

      if (byKey.size === 0) {
        ((adminContactsResult.data as any[]) || []).forEach((contato: any) => {
          const nome = String(contato.nome || '').trim();
          const key = (nome.length === 1 ? nome : nome.charAt(0)).toUpperCase();
          if ((key === 'V' || key === 'A') && !byKey.has(key)) {
            byKey.set(key, { key, nome });
          }
        });
      }

      if (!cancelled) {
        setSocios([...byKey.values()].sort((a, b) => a.key.localeCompare(b.key)));
      }
    };

    loadSocios();
    return () => {
      cancelled = true;
    };
  }, []);

  // React Query for 'lista'
  const {
    data: pedidosPages,
    fetchNextPage: fetchNextPedidos,
    hasNextPage: hasMorePedidos,
    isFetchingNextPage: loadingMorePedidos,
    isLoading: loadingPedidos
  } = useInfiniteQuery({
    queryKey: ['pedidos_lista', filterMode, year, month],
    queryFn: async ({ pageParam = 0 }) => {
      let startDate: string, endDate: string;
      if (filterMode === 'ano') {
        startDate = `${year}-01-01`; endDate = `${year + 1}-01-01`;
      } else {
        startDate = `${year}-${String(month).padStart(2, '0')}-01`;
        const nextM = month === 12 ? 1 : month + 1;
        const nextY = month === 12 ? year + 1 : year;
        endDate = `${nextY}-${String(nextM).padStart(2, '0')}-01`;
      }
      const { data } = await supabase.from('pedidos')
        .select('id, data, canal, order_number, valor, status_pedido, status_pagamento, produto, quantidade, uf_postagem, codigo_rastreio, contato_id, entrega_em_maos, estoque_debitado, locked_at, is_free, contatos(nome, telefone, tag_vip, cpf, endereco, complemento, bairro, cidade_uf, cep, canal_origem)')
        .gte('data', startDate).lt('data', endDate)
        .order('order_number', { ascending: false })
        .range(pageParam * PER_PAGE_FETCH, (pageParam + 1) * PER_PAGE_FETCH - 1);
      return data || [];
    },
    getNextPageParam: (lastPage, allPages) => lastPage.length === PER_PAGE_FETCH ? allPages.length : undefined,
    initialPageParam: 0,
    staleTime: 5 * 60 * 1000,
  });

  const pedidos = useMemo(() => pedidosPages?.pages.flat() || [], [pedidosPages]);

  // React Query for 'pendentes'
  const {
    data: pendentesPages,
    fetchNextPage: fetchNextPendentes,
    hasNextPage: hasMorePendentes,
    isFetchingNextPage: loadingMorePendentes,
    isLoading: loadingPendentes
  } = useInfiniteQuery({
    queryKey: ['pedidos_pendentes'],
    queryFn: async ({ pageParam = 0 }) => {
      const { data } = await supabase.from('pedidos')
        .select('id, data, canal, order_number, valor, status_pedido, status_pagamento, modalidade, uf_postagem, quantidade, contato_id, observacao, criado_por, codigo_rastreio, produto, locked_at, is_free, contatos(nome, telefone, cpf, endereco, complemento, bairro, cidade_uf, cep, canal_origem)')
        .eq('status_pagamento', 'pendente')
        .order('order_number', { ascending: false })
        .range(pageParam * PER_PAGE_FETCH, (pageParam + 1) * PER_PAGE_FETCH - 1);
      return data || [];
    },
    getNextPageParam: (lastPage, allPages) => lastPage.length === PER_PAGE_FETCH ? allPages.length : undefined,
    initialPageParam: 0,
    staleTime: 5 * 60 * 1000,
  });

  const pendentes = useMemo(() => pendentesPages?.pages.flat() || [], [pendentesPages]);

  const [filteredPedidos, setFilteredPedidos] = useState<any[]>([]);
  const [filteredPendentes, setFilteredPendentes] = useState<any[]>([]);

  useEffect(() => {
    let f = [...pedidos];
    if (search) f = f.filter(p => (p.contatos as any)?.nome?.toLowerCase().includes(search.toLowerCase()) || (p.contatos as any)?.telefone?.includes(search));
    if (statusFilter !== 'todos') f = f.filter(p => p.status_pedido === statusFilter);
    setFilteredPedidos(f);
  }, [pedidos, search, statusFilter]);

  useEffect(() => {
    let f = [...pendentes];
    if (pendentesSearch) f = f.filter(p => (p.contatos as any)?.nome?.toLowerCase().includes(pendentesSearch.toLowerCase()) || (p.contatos as any)?.telefone?.includes(pendentesSearch));
    setFilteredPendentes(f);
  }, [pendentes, pendentesSearch]);

  const fetchRanking = async () => {
    const { data } = await supabase.from('pedidos').select('contato_id, valor, quantidade, contatos(nome)').gte('data', rankStart).lte('data', rankEnd);
    if (!data) return;
    const byContact: Record<string, { nome: string; totalValor: number; totalQtd: number }> = {};
    data.forEach((p: any) => {
      // FREE nao soma em ranking de valor nem de quantidade
      if (p.is_free) return;
      const id = p.contato_id;
      if (!byContact[id]) byContact[id] = { nome: p.contatos?.nome || '—', totalValor: 0, totalQtd: 0 };
      byContact[id].totalValor += Number(p.valor) || 0;
      byContact[id].totalQtd += 1;
    });
    const arr = Object.values(byContact);
    setRankValor([...arr].sort((a, b) => b.totalValor - a.totalValor));
    setRankQtd([...arr].sort((a, b) => b.totalQtd - a.totalQtd));
  };

  useEffect(() => {
    if (activeTab === 'ranking') fetchRanking();
  }, [activeTab, rankStart, rankEnd]);

  const openContactDetail = async (contatoId: string) => {
    const [contatoResult, pedsResult] = await Promise.all([
      supabase.from('contatos').select('*').eq('id', contatoId).single(),
      supabase.from('pedidos').select('*').eq('contato_id', contatoId).order('data', { ascending: false })
    ]);
    setSelectedContact(contatoResult.data);
    setContactPedidos(pedsResult.data || []);
  };

  // Hoje em SP (YYYY-MM-DD) para travar pedidos entregues após virar o dia
  const todaySP = useMemo(() => {
    const now = new Date();
    const sp = new Date(now.toLocaleString('en-US', { timeZone: 'America/Sao_Paulo' }));
    return `${sp.getFullYear()}-${String(sp.getMonth() + 1).padStart(2, '0')}-${String(sp.getDate()).padStart(2, '0')}`;
  }, []);

  const isStatusLocked = (p: any) => {
    if (p.locked_at) return true;
    if (p.status_pedido === 'entregue') {
      const pedidoData = (p.data || '').slice(0, 10);
      if (pedidoData && pedidoData < todaySP) return true;
    }
    return false;
  };

  const updateStatus = async (pedidoId: string, newStatus: string, isLocked?: boolean) => {
    if (isLocked) {
      toast.error('Pedido entregue bloqueado após fechamento do dia');
      return;
    }
    const { error } = await supabase.from('pedidos').update({ status_pedido: newStatus }).eq('id', pedidoId);
    if (error) { 
      toast.error('Erro ao atualizar: ' + error.message); 
      console.error('Update status error:', error);
      return; 
    }
    toast.success('Status atualizado!');
    await queryClient.invalidateQueries({ queryKey: ['pedidos_lista'] });
  };

  const copyPhone = (phone: string) => { 
    copyToClipboard(phone).then(success => {
      if (success) toast.success('Número Copiado!');
      else toast.error('Falha ao copiar');
    });
  };

  const exportCSV = () => {
    const rows = [['#', 'Data', 'Nome', 'Canal', 'Valor', 'Status', 'Telefone']];
    filteredPedidos.forEach(p => {
      rows.push([`#${p.order_number}`, formatDateShort(p.data), (p.contatos as any)?.nome || '', p.canal, String(p.valor), p.status_pedido === 'postado' ? 'Postado' : p.status_pedido === 'entregue' ? 'Entregue' : 'Aguardando Postagem', (p.contatos as any)?.telefone || '']);
    });
    const csv = rows.map(r => r.join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = 'pedidos.csv'; a.click();
  };

  const handleMarcarPago = async () => {
    if (!marcarPagoTarget || !marcarPagoSocio) return;
    setMarkingPago(true);
    const p = marcarPagoTarget;
    try {
      // 1. Update pedido status — data_pago = hoje (data do recebimento)
      const todayISO = new Date().toISOString().slice(0, 10);
      const { error: pError } = await supabase.from('pedidos')
        .update({
          status_pagamento: 'pago',
          status_pedido: 'aguardando_rastreio',
          recebido_por: marcarPagoSocio,
          data_pago: todayISO,
        } as any)
        .eq('id', p.id);
      if (pError) throw pError;

      // 2. Convert existing pending lancamento (socio='P') to assigned partner
      // This avoids creating duplicate entries in Financeiro
      const { data: existingP } = await supabase
        .from('lancamentos_socios')
        .select('id')
        .eq('pedido_id', p.id)
        .eq('socio', 'P')
        .eq('tipo', 'VENDA')
        .maybeSingle();

      if (existingP) {
        // UPDATE: convert P → V/A (preserves criado_por, valor, snapshot links)
        const { error: lsUpdError } = await supabase
          .from('lancamentos_socios')
          .update({
            socio: marcarPagoSocio,
            status_pagamento: 'pago',
            realizado: true,
            realizado_em: new Date().toISOString(),
          })
          .eq('id', existingP.id);
        if (lsUpdError) throw lsUpdError;
      } else {
        // Fallback: legacy pending sales without a 'P' row → INSERT new
        const { error: lsError } = await supabase.from('lancamentos_socios').insert({
          socio: marcarPagoSocio,
          tipo: 'VENDA',
          valor: p.valor,
          canal: p.canal,
          contato_id: p.contato_id,
          quantidade: p.quantidade,
          modalidade: p.modalidade,
          uf_postagem: p.uf_postagem,
          pedido_id: p.id,
          status_pagamento: 'pago',
          criado_por: p.criado_por || (socios[0]?.nome || 'Sistema')
        });
        if (lsError) throw lsError;
      }

      // 3. Update financeiro: convert receita_pendente to receita
      // Using a more flexible match to ensure it finds the record
      const { error: fError } = await supabase.from('financeiro')
        .update({ tipo: 'receita' })
        .or(`descricao.eq.${p.canal} - Venda Pendente #${p.id},descricao.ilike.%Venda Pendente #${p.id}%`);

      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Sistema',
        acao: `Venda Pendente marcada como PAGA por ${marcarPagoSocio}`,
        tabela_afetada: 'pedidos',
        registro_id: p.id,
        detalhe: `Pedido de ${(p.contatos as any)?.nome}`
      });

      const socioNome = socios.find(s => s.key === marcarPagoSocio)?.nome || marcarPagoSocio;
      toast.success(`Pago! Atribuído a ${socioNome}`);
      setMarcarPagoTarget(null);
      setMarcarPagoSocio(null);
      queryClient.invalidateQueries({ queryKey: ['pedidos_lista'] });
      queryClient.invalidateQueries({ queryKey: ['pedidos_pendentes'] });
    } catch (err: any) {
      toast.error('Erro ao marcar como pago: ' + err.message);
    } finally {
      setMarkingPago(false);
    }
  };

  // FREE nunca entra em totais nem em ticket medio
  const totalSum = filteredPedidos.reduce((s, p) => s + (p.is_free ? 0 : (Number(p.valor) || 0)), 0);
  const pagosNonFree = filteredPedidos.filter(p => !p.is_free).length;
  const ticketMedio = pagosNonFree > 0 ? totalSum / pagosNonFree : 0;

  const getProductBreakdown = () => {
    if (statusFilter !== 'aguardando_rastreio') return null;
    const breakdown: Record<string, number> = {};
    let totalQtd = 0;
    filteredPedidos.forEach(p => {
      try {
        const prods = JSON.parse(p.produto);
        if (Array.isArray(prods)) {
          prods.forEach((item: any) => {
            const displayName = getTagDisplayName(item.produto || 'Outro');
            const qty = item.quantidade || 1;
            breakdown[displayName] = (breakdown[displayName] || 0) + qty;
            totalQtd += qty;
          });
          return;
        }
      } catch {}
      const tag = p.produto || 'Outro';
      const qty = p.quantidade || 1;
      const displayName = getTagDisplayName(tag);
      breakdown[displayName] = (breakdown[displayName] || 0) + qty;
      totalQtd += qty;
    });
    return { breakdown, totalQtd, totalPedidos: filteredPedidos.length };
  };

  const productBreakdown = getProductBreakdown();

  if (loadingPedidos) return <Skeleton className="h-[500px]" />;

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold">Pedidos</h1>
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="lista">Lista</TabsTrigger>
          <TabsTrigger value="pendentes">💳 Pendentes</TabsTrigger>
          <TabsTrigger value="ranking">🏆 Ranking</TabsTrigger>
        </TabsList>

        <TabsContent value="lista" className="space-y-4">
          <div className="flex flex-wrap gap-3 items-center">
            <Select value={filterMode} onValueChange={(v: 'ano' | 'mes') => setFilterMode(v)}>
              <SelectTrigger className="w-24"><SelectValue /></SelectTrigger>
              <SelectContent><SelectItem value="ano">Ano</SelectItem><SelectItem value="mes">Mês</SelectItem></SelectContent>
            </Select>
            <Input type="number" value={year} onChange={e => setYear(Number(e.target.value))} className="w-20 text-center" />
            {filterMode === 'mes' && (
              <Select value={String(month)} onValueChange={v => setMonth(Number(v))}>
                <SelectTrigger className="w-28"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="1">Jan</SelectItem>
                  <SelectItem value="2">Fev</SelectItem>
                  <SelectItem value="3">Mar</SelectItem>
                  <SelectItem value="4">Abr</SelectItem>
                  <SelectItem value="5">Mai</SelectItem>
                  <SelectItem value="6">Jun</SelectItem>
                  <SelectItem value="7">Jul</SelectItem>
                  <SelectItem value="8">Ago</SelectItem>
                  <SelectItem value="9">Set</SelectItem>
                  <SelectItem value="10">Out</SelectItem>
                  <SelectItem value="11">Nov</SelectItem>
                  <SelectItem value="12">Dez</SelectItem>
                </SelectContent>
              </Select>
            )}
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="todos">Todos</SelectItem>
                <SelectItem value="aguardando_rastreio">Aguardando Postagem</SelectItem>
                <SelectItem value="postado">Postado</SelectItem>
                <SelectItem value="entregue">Entregue</SelectItem>
              </SelectContent>
            </Select>
            <Input placeholder="Buscar por nome ou telefone" value={search} onChange={e => setSearch(e.target.value)} className="w-64" />
            <Button variant="outline" size="sm" onClick={exportCSV}><Download className="w-4 h-4 mr-1" /> CSV</Button>
          </div>

          {/* Web Table - hidden on mobile */}
          <div className="hidden md:block overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr className="border-b font-bold"><th className="text-left py-2 w-12">#</th><th className="text-left py-2">Data</th><th className="text-left py-2">Nome</th><th className="text-left py-2">Canal</th><th className="text-right py-2 pr-8">Valor</th><th className="text-left py-2">Status</th></tr></thead>
              <tbody>
                {filteredPedidos.map(p => (
                  <tr key={p.id} className="border-b border-border/50 hover:bg-muted/50 cursor-pointer" onClick={() => setDetailPedido(p)}>
                    <td className="py-2 text-muted-foreground font-mono text-xs">#{p.order_number}</td>
                    <td className="py-2">{formatDateShort(p.data)}</td>
                    <td className="py-2 font-medium">
                      <button onClick={e => { e.stopPropagation(); openContactDetail(p.contato_id); }} className="hover:underline text-primary">
                        {(p.contatos as any)?.nome || '—'}
                      </button>
                      {(p.contatos as any)?.tag_vip && <Trophy className="inline w-3 h-3 ml-1 text-sf-gold" />}
                    </td>
                    <td className="py-2">
                      <Badge variant="outline" className="text-[10px]">{p.canal || '—'}</Badge>
                    </td>
                    <td className="py-2 text-right pr-8 font-medium">{p.is_free ? <span className="text-sky-600 font-bold">FREE</span> : formatBRL(Number(p.valor))}</td>
                    <td className="py-2" onClick={e => e.stopPropagation()}>
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <Select value={p.status_pedido || 'aguardando_rastreio'} onValueChange={v => updateStatus(p.id, v, isStatusLocked(p))} disabled={isStatusLocked(p)}>
                          <SelectTrigger className={cn("h-7 w-auto min-w-[120px] text-xs border-0 bg-transparent p-0 shadow-none focus:ring-0 focus:ring-offset-0 focus-visible:ring-0 focus-visible:ring-offset-0 [&>svg]:opacity-50", isStatusLocked(p) && "[&>svg]:hidden disabled:opacity-100 cursor-default")}>
                            <SelectValue>
                              {p.status_pedido === 'entregue' ? (
                                <Badge className="bg-green-600 text-white hover:bg-green-600">Entregue</Badge>
                              ) : p.status_pedido === 'postado' ? (
                                <Badge className="bg-sky-100 text-sky-700 hover:bg-sky-100 border border-sky-200">Postado</Badge>
                              ) : (
                                <Badge variant="secondary">Aguardando</Badge>
                              )}
                            </SelectValue>
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="aguardando_rastreio">Aguardando Postagem</SelectItem>
                            <SelectItem value="postado">Postado</SelectItem>
                            <SelectItem value="entregue">Entregue</SelectItem>
                          </SelectContent>
                        </Select>
                        {p.status_pagamento === 'pendente' && (
                          <Badge variant="outline" className="text-[10px] border-amber-500 text-amber-600 py-0 h-5">
                            PENDENTE
                          </Badge>
                        )}
                        {p.entrega_em_maos && (
                          <Badge variant="outline" className="text-[10px] border-blue-500 text-blue-600 py-0 h-5">
                            🤝 MÃOS
                          </Badge>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="hidden md:flex justify-between items-center mt-4">
            <div className="text-sm">
              <span className="text-muted-foreground">Total: </span>
              <span className="font-bold">{formatBRL(totalSum)}</span>
              <span className="mx-3 text-muted-foreground">|</span>
              <span className="text-muted-foreground">Ticket Médio: </span>
              <span className="font-bold text-primary">{formatBRL(ticketMedio)}</span>
              <span className="mx-3 text-muted-foreground">|</span>
              <span className="text-muted-foreground">Qtd: </span>
              <span className="font-bold">{filteredPedidos.length}</span>
            </div>
            {hasMorePedidos && (
              <Button variant="outline" size="sm" onClick={() => fetchNextPedidos()} disabled={loadingMorePedidos}>
                {loadingMorePedidos ? 'Carregando...' : 'Carregar mais...'}
              </Button>
            )}
          </div>
        </TabsContent>

        {/* Mobile Cards View - only in Lista tab */}
        {isMobile && activeTab === 'lista' && (
          <div className="md:hidden space-y-2 px-1">
            {filteredPedidos.map(p => (
              <div key={p.id} className="p-3 border rounded-xl hover:bg-muted/30">
                <div className="flex justify-between items-start mb-2">
                  <div className="cursor-pointer" onClick={() => setDetailPedido(p)}>
                    <span className="font-bold text-sm">#{p.order_number}</span>
                    <span className="text-xs text-muted-foreground ml-2">{formatDateShort(p.data)}</span>
                  </div>
                  <div className="flex items-center gap-1">
                    {p.codigo_rastreio ? (
                      <Button variant="ghost" size="icon" className="h-6 w-6 p-0" onClick={e => { e.stopPropagation(); copyToClipboard(p.codigo_rastreio).then(s => s && toast.success('Rastreio copiado!')); }}>
                        <Package className="w-4 h-4 text-primary" />
                      </Button>
                    ) : (
                      <Package className="w-4 h-4 text-muted-foreground/40" />
                    )}
                    <div className="flex flex-wrap items-center gap-1">
                      <Badge variant="outline" className="text-[10px]">{p.canal || '—'}</Badge>
                      {p.entrega_em_maos && <Badge variant="outline" className="text-[10px] border-blue-500 text-blue-600">🤝 Mãos</Badge>}
                      {p.is_free && <Badge className="bg-sky-100 text-sky-700 hover:bg-sky-100 border-sky-300 text-[10px] font-bold px-1.5 py-0">FREE</Badge>}
                    </div>
                  </div>
                </div>
                <div className="text-sm font-medium mb-1 flex items-center gap-2">
                  <button onClick={e => { e.stopPropagation(); openContactDetail(p.contato_id); }} className="hover:underline text-primary">
                    {(p.contatos as any)?.nome || '—'}
                  </button>
                </div>
                <div className="flex justify-between items-center gap-2">
                  <span className="text-sm font-bold cursor-pointer" onClick={() => setDetailPedido(p)}>{p.is_free ? <span className="text-sky-600">FREE</span> : formatBRL(Number(p.valor))}</span>
                  <div className="flex items-center gap-1 flex-wrap justify-end">
                    {p.status_pagamento === 'pendente' && (
                      <Badge variant="outline" className="text-[9px] border-amber-500 text-amber-600 py-0 h-5 px-1.5">
                        PENDENTE
                      </Badge>
                    )}
                    <Select value={p.status_pedido || 'aguardando_rastreio'} onValueChange={v => updateStatus(p.id, v, isStatusLocked(p))} disabled={isStatusLocked(p)}>
                      <SelectTrigger className={cn("h-6 w-auto text-[10px] py-0 px-2", isStatusLocked(p) && "[&>svg]:hidden disabled:opacity-100 cursor-default")}>
                        {p.status_pedido === 'entregue' ? (
                          <span className="text-green-600 font-medium">Entregue</span>
                        ) : p.status_pedido === 'postado' ? (
                          <span className="text-sky-600 font-medium">Postado</span>
                        ) : (
                          <span>Aguardando</span>
                        )}
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="aguardando_rastreio">Aguardando Postagem</SelectItem>
                        <SelectItem value="postado">Postado</SelectItem>
                        <SelectItem value="entregue">Entregue</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
              </div>
            ))}
              <div className="text-center font-bold text-sm py-2">
                Total: {formatBRL(totalSum)}
                <span className="mx-2 text-muted-foreground">|</span>
                Ticket: {formatBRL(ticketMedio)}
                <span className="mx-2 text-muted-foreground">|</span>
                Qtd: {filteredPedidos.length}
              </div>
          </div>
        )}

        <TabsContent value="pendentes" className="space-y-4">
          <Input placeholder="Buscar por nome ou telefone" value={pendentesSearch} onChange={e => setPendentesSearch(e.target.value)} className="max-w-sm" />
          <div className="hidden md:block overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr className="border-b font-bold">
                <th className="text-left py-2 w-12">#</th>
                <th className="text-left py-2">Data</th>
                <th className="text-left py-2">Nome</th>
                <th className="text-left py-2">Canal</th>
                <th className="text-right py-2 pr-8">Valor</th>
                <th className="text-left py-2">Status</th>
                <th className="text-center py-2">Obs</th>
                <th className="py-2"></th>
              </tr></thead>
              <tbody>
                {filteredPendentes.map(p => (
                  <tr key={p.id} className="border-b border-border/50 hover:bg-muted/50">
                    <td className="py-2 text-muted-foreground font-mono text-xs">#{p.order_number}</td>
                    <td className="py-2">{formatDateShort(p.data)}</td>
                    <td className="py-2 font-medium">{(p.contatos as any)?.nome || '—'}</td>
                    <td className="py-2">
                      <Badge variant="outline" className="text-[10px]">{p.canal || '—'}</Badge>
                    </td>
                    <td className="py-2 text-right pr-8 font-medium">{p.is_free ? <span className="text-sky-600 font-bold">FREE</span> : formatBRL(Number(p.valor))}</td>
                    <td className="py-2">
                      <Badge variant="secondary">
                        {p.status_pedido === 'entregue' ? '✅ Entregue' : p.status_pedido === 'postado' ? 'Postado' : 'Aguardando'}
                      </Badge>
                    </td>
                    <td className="py-2 text-center">
                      <Popover>
                        <PopoverTrigger asChild>
                          <Button variant="ghost" size="icon" className={cn("h-8 w-8", !p.observacao && "opacity-20 hover:opacity-100")}>
                            <StickyNote className={cn("w-4 h-4", p.observacao ? "text-orange-500" : "text-muted-foreground")} />
                          </Button>
                        </PopoverTrigger>
                        <PopoverContent className="w-64 p-3 text-sm">
                          <p className="font-bold text-xs text-muted-foreground mb-1 uppercase tracking-wider">Observações</p>
                          <p className="whitespace-pre-wrap">{p.observacao || 'Nenhuma observação informada.'}</p>
                        </PopoverContent>
                      </Popover>
                    </td>
                    <td className="py-2">
                      <Button size="sm" className="min-h-[44px] bg-sf-green hover:bg-sf-green/90 text-primary-foreground" onClick={() => setMarcarPagoTarget(p)}>
                        Marcar como Pago
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {filteredPendentes.length === 0 && activeTab === 'pendentes' && <p className="text-muted-foreground text-center py-8">Nenhum pedido pendente</p>}
          {hasMorePendentes && (
            <div className="flex justify-center mt-4">
              <Button variant="outline" size="sm" onClick={() => fetchNextPendentes()} disabled={loadingMorePendentes}>
                {loadingMorePendentes ? 'Carregando...' : 'Carregar mais...'}
              </Button>
            </div>
          )}

          {/* Mobile Cards View - only in Pendentes tab */}
          {isMobile && activeTab === 'pendentes' && (
            <div className="md:hidden space-y-2 px-1">
              {filteredPendentes.map(p => (
                <div key={p.id} className="p-3 border rounded-xl hover:bg-muted/30" onClick={() => setDetailPedido(p)}>
                  <div className="flex justify-between items-start mb-2">
                    <div>
                      <span className="font-bold text-sm">#{p.order_number}</span>
                      <span className="text-xs text-muted-foreground ml-2">{formatDateShort(p.data)}</span>
                    </div>
                    <div className="flex items-center gap-1">
                      <Popover>
                        <PopoverTrigger asChild>
                          <Button variant="ghost" size="icon" className={cn("h-6 w-6 p-0", !p.observacao && "opacity-30 hover:opacity-100")} onClick={e => e.stopPropagation()}>
                            <StickyNote className={cn("w-4 h-4", p.observacao ? "text-orange-500" : "text-muted-foreground")} />
                          </Button>
                        </PopoverTrigger>
                        <PopoverContent className="w-64 p-3 text-sm">
                          <p className="font-bold text-xs text-muted-foreground mb-1 uppercase tracking-wider">Observações</p>
                          <p className="whitespace-pre-wrap">{p.observacao || 'Nenhuma observação informada.'}</p>
                        </PopoverContent>
                      </Popover>
                      <Badge variant="outline" className="text-[10px]">{p.canal || '—'}</Badge>
                    </div>
                  </div>
                  <div className="text-sm font-medium mb-1">{(p.contatos as any)?.nome || '—'}</div>
                  <div className="flex justify-between items-center">
                    <span className="text-sm font-bold">{p.is_free ? <span className="text-sky-600">FREE</span> : formatBRL(Number(p.valor))}</span>
                    <Badge variant="secondary" className="text-[10px]">
                      {p.status_pedido === 'entregue' ? '✅ Entregue' : p.status_pedido === 'postado' ? 'Postado' : 'Aguardando'}
                    </Badge>
                  </div>
                  <div className="mt-2">
                    <Button size="sm" className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground text-xs" onClick={() => setMarcarPagoTarget(p)}>
                      Marcar como Pago
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </TabsContent>

        <TabsContent value="ranking" className="space-y-4">
          <div className="flex gap-3 items-center">
            <span className="text-sm">De:</span><Input type="date" value={rankStart} onChange={e => setRankStart(e.target.value)} className="w-40" />
            <span className="text-sm">Até:</span><Input type="date" value={rankEnd} onChange={e => setRankEnd(e.target.value)} className="w-40" />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Card>
              <CardHeader><CardTitle className="text-sm">🥇 Top por Valor Total</CardTitle></CardHeader>
              <CardContent>
                {rankValor.slice((rankPageV - 1) * RANK_PER_PAGE, rankPageV * RANK_PER_PAGE).map((r, i) => (
                  <div key={i} className="flex justify-between py-1.5 border-b border-border/50">
                    <span className="text-sm font-medium">{(rankPageV - 1) * RANK_PER_PAGE + i + 1}. {r.nome}</span>
                    <span className="text-sm font-bold text-primary">{formatBRL(r.totalValor)}</span>
                  </div>
                ))}
                {rankValor.length === 0 && <p className="text-muted-foreground text-sm">Nenhum dado</p>}
                <div className="flex gap-2 mt-2 justify-end">
                  <Button variant="outline" size="sm" disabled={rankPageV <= 1} onClick={() => setRankPageV(p => p - 1)}>Anterior</Button>
                  <Button variant="outline" size="sm" disabled={rankPageV * RANK_PER_PAGE >= rankValor.length} onClick={() => setRankPageV(p => p + 1)}>Próxima</Button>
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardHeader><CardTitle className="text-sm">🥈 Top por Quantidade</CardTitle></CardHeader>
              <CardContent>
                {rankQtd.slice((rankPageQ - 1) * RANK_PER_PAGE, rankPageQ * RANK_PER_PAGE).map((r, i) => (
                  <div key={i} className="flex justify-between py-1.5 border-b border-border/50">
                    <span className="text-sm font-medium">{(rankPageQ - 1) * RANK_PER_PAGE + i + 1}. {r.nome}</span>
                    <span className="text-sm font-bold text-primary">{r.totalQtd} pedidos</span>
                  </div>
                ))}
                {rankQtd.length === 0 && <p className="text-muted-foreground text-sm">Nenhum dado</p>}
                <div className="flex gap-2 mt-2 justify-end">
                  <Button variant="outline" size="sm" disabled={rankPageQ <= 1} onClick={() => setRankPageQ(p => p - 1)}>Anterior</Button>
                  <Button variant="outline" size="sm" disabled={rankPageQ * RANK_PER_PAGE >= rankQtd.length} onClick={() => setRankPageQ(p => p + 1)}>Próxima</Button>
                </div>
              </CardContent>
            </Card>
          </div>
        </TabsContent>
      </Tabs>

      {/* Marcar Pago Prompt */}
      <AlertDialog open={!!marcarPagoTarget} onOpenChange={() => setMarcarPagoTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Atribuir recebimento</AlertDialogTitle>
            <AlertDialogDescription>
              A venda pendente de {(marcarPagoTarget?.contatos as any)?.nome} foi paga. Atribua o recebimento a um dos Sócios:
            </AlertDialogDescription>
          </AlertDialogHeader>
          <div className="flex flex-wrap gap-4 justify-center py-4">
            {socios.length === 0 ? (
              <div className="text-sm text-muted-foreground text-center py-6 px-4">
                Nenhum sócio cadastrado.<br />
                Cadastre sócios em <strong>Administração</strong>.
              </div>
            ) : socios.map(s => (
              <Button
                key={s.key}
                variant={marcarPagoSocio === s.key ? 'default' : 'outline'}
                className={cn("w-24 h-24 flex-col gap-2", marcarPagoSocio === s.key && "bg-sf-green hover:bg-sf-green/90")}
                onClick={() => setMarcarPagoSocio(s.key)}
              >
                <div className="text-3xl font-bold">{s.nome.charAt(0)}</div>
                <div className="text-xs">{s.nome}</div>
              </Button>
            ))}
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setMarcarPagoSocio(null)}>Cancelar</AlertDialogCancel>
            <AlertDialogAction 
              onClick={handleMarcarPago} 
              disabled={!marcarPagoSocio || markingPago}
              className="bg-sf-green hover:bg-sf-green/90"
            >
              {markingPago ? 'Processando...' : 'Confirmar Recebimento'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Contact detail dialog */}
      <Dialog open={!!selectedContact} onOpenChange={() => setSelectedContact(null)}>
        <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
          <DialogHeader><DialogTitle>{selectedContact?.nome}</DialogTitle></DialogHeader>
          <div className="space-y-3 text-sm">
            <p><strong>Telefone:</strong> {selectedContact?.telefone} <Button variant="ghost" size="icon" className="h-5 w-5 inline" onClick={() => copyPhone(selectedContact?.telefone || '')}><Copy className="w-3 h-3" /></Button></p>
            <p><strong>CPF:</strong> {selectedContact?.cpf || '—'}</p>
            <p><strong>Endereço:</strong> {selectedContact?.endereco || '—'}</p>
            <p><strong>Complemento:</strong> {selectedContact?.complemento || '—'}</p>
            <p><strong>Bairro:</strong> {selectedContact?.bairro || '—'}</p>
            <p><strong>Cidade/UF:</strong> {selectedContact?.cidade_uf || '—'}</p>
            <p><strong>CEP:</strong> {selectedContact?.cep || '—'}</p>
            <p><strong>Canal:</strong> {selectedContact?.canal_origem}</p>
            <p><strong>VIP:</strong> {selectedContact?.tag_vip ? 'Sim' : 'Não'}</p>
            <h4 className="font-bold mt-3">Histórico de Pedidos</h4>
            {contactPedidos.map(p => {
              let prodDisplay: string;
              try {
                const prods = JSON.parse(p.produto);
                if (Array.isArray(prods)) {
                  prodDisplay = prods.map((item: any) => `${item.produto} ×${item.quantidade}`).join(', ');
                } else {
                  prodDisplay = `${getTagDisplayName(p.produto)} ×${p.quantidade}`;
                }
              } catch {
                prodDisplay = `${getTagDisplayName(p.produto)} ×${p.quantidade}`;
              }
              return (
                <div key={p.id} className="border-b border-border/50 py-2">
                  <p>{prodDisplay} — {p.is_free ? <span className="text-sky-600 font-bold">FREE</span> : formatBRL(Number(p.valor))} — {formatDateShort(p.data)} — {p.status_pedido === 'entregue' ? '✅ Entregue' : p.status_pedido === 'postado' ? 'Postado' : 'Aguardando'}</p>
                </div>
              );
            })}
            {contactPedidos.length === 0 && <p className="text-muted-foreground">Nenhum pedido encontrado</p>}
          </div>
        </DialogContent>
      </Dialog>

      {/* Pedido detail dialog */}
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
                    if (Array.isArray(prods)) {
                      return prods.map((p: any, i: number) => (
                        <p key={i} className="ml-2">• {getTagDisplayName(p.produto)} × {p.quantidade}</p>
                      ));
                    }
                  } catch {}
                  return <p className="ml-2">{getTagDisplayName(detailPedido.produto)} × {detailPedido.quantidade}</p>;
                })()}
              </div>
              <p><strong>Valor Total:</strong> {detailPedido.is_free ? <span className="text-sky-600 font-bold">FREE</span> : formatBRL(Number(detailPedido.valor))}</p>
              <p><strong>CPF:</strong> {(detailPedido.contatos as any)?.cpf || '—'}</p>
              <p><strong>Endereço:</strong> {(detailPedido.contatos as any)?.endereco || '—'}</p>
              <p><strong>Complemento:</strong> {(detailPedido.contatos as any)?.complemento || '—'}</p>
              <p><strong>Bairro:</strong> {(detailPedido.contatos as any)?.bairro || '—'}</p>
              <p><strong>Cidade/UF:</strong> {(detailPedido.contatos as any)?.cidade_uf || '—'}</p>
              <p><strong>CEP:</strong> {(detailPedido.contatos as any)?.cep || '—'}</p>
              <p><strong>UF Postagem:</strong> {detailPedido.uf_postagem || '—'}</p>
              <p><strong>Canal:</strong> {detailPedido.canal}</p>
              <p><strong>Status:</strong> {detailPedido.status_pedido === 'entregue' ? 'Entregue' : detailPedido.status_pedido === 'postado' ? 'Postado' : 'Aguardando Postagem'}</p>
              <p><strong>Rastreio:</strong> {detailPedido.codigo_rastreio || 'Aguardando rastreio'}{detailPedido.codigo_rastreio && <Button variant="ghost" size="icon" className="h-6 w-6 ml-1" onClick={() => copyToClipboard(detailPedido.codigo_rastreio).then(s => s && toast.success('Código copiado!'))}><Copy className="w-3 h-3" /></Button>}</p>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

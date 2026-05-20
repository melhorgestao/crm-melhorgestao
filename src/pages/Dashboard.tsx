import { useEffect, useState, useMemo } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Progress } from '@/components/ui/progress';
import { formatBRL } from '@/lib/format';
import { DollarSign, Tag, Package, UserPlus, RefreshCw, TrendingUp, TrendingDown, Target, CreditCard } from 'lucide-react';
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, BarChart, Bar, CartesianGrid } from 'recharts';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { getTagDisplayName } from '@/lib/productDisplayNames';

function renderProdutos(val: any): string {
  if (val == null) return '—';
  const s = String(val).trim();
  if (!s) return '—';
  if (s.startsWith('[') || s.startsWith('{')) {
    try {
      const parsed = JSON.parse(s);
      const arr = Array.isArray(parsed) ? parsed : [parsed];
      const parts = arr.map((it: any) => {
        const nome = it?.produto || it?.nome_oficial || it?.nome || '';
        const qtd = Number(it?.quantidade) || 0;
        const display = nome ? getTagDisplayName(nome) : '';
        if (!display) return '';
        return qtd > 1 ? `${display} x${qtd}` : display;
      }).filter(Boolean);
      if (parts.length) return parts.join(', ');
    } catch { /* ignore */ }
  }
  return s;
}

export default function Dashboard() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const localToday = (() => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; })();
  
  const [period, setPeriod] = useState<'hoje' | 'ontem' | 'semana' | '15dias'>('hoje');

  const getPeriodRange = () => {
    const now = new Date();
    const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    
    if (period === 'hoje') return { from: today, to: today };
    
    if (period === 'ontem') {
      const y = new Date(now.getTime() - 86400000);
      const yesterday = `${y.getFullYear()}-${String(y.getMonth() + 1).padStart(2, '0')}-${String(y.getDate()).padStart(2, '0')}`;
      return { from: yesterday, to: yesterday };
    }
    
    if (period === 'semana') {
      const dayOfWeek = now.getDay();
      const diff = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
      const monday = new Date(now.getTime() - diff * 86400000);
      const from = `${monday.getFullYear()}-${String(monday.getMonth() + 1).padStart(2, '0')}-${String(monday.getDate()).padStart(2, '0')}`;
      return { from, to: today };
    }
    
    const fifteen = new Date(now.getTime() - 14 * 86400000);
    const from = `${fifteen.getFullYear()}-${String(fifteen.getMonth() + 1).padStart(2, '0')}-${String(fifteen.getDate()).padStart(2, '0')}`;
    return { from, to: today };
  };

  const { from: dateFrom, to: dateTo } = getPeriodRange();

  const monthStart = `${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}-01`;
  
  // Auto-migration trigger for Leads (ADS -> BASE)
  // This eliminates the need for an external n8n cron job.
  useEffect(() => {
    const triggerDailyTasks = async () => {
      const today = localToday;
      const lastMigration = localStorage.getItem('sf_last_migration_date');
      
      if (lastMigration !== today) {
        console.log('Iniciando migração diária de leads (ADS -> BASE)...');
        // Run in background without blocking UI
        supabase.rpc('perform_midnight_lead_migration' as any).then(({ data, error }) => {
          if (error) {
            console.error('Erro na migração automática:', error);
          } else {
            console.log('Migração concluída:', data);
          }
        });
        
        // Also lock yesterday's delivered orders and paid vendas
        supabase.rpc('perform_daily_lock' as any).then(({ data, error }) => {
          if (error) {
            console.error('Erro no lock diário:', error);
          } else {
            console.log('Lock diário executado:', data);
          }
        });
        
        localStorage.setItem('sf_last_migration_date', today);
        queryClient.invalidateQueries({ queryKey: ['dashboard_data'] });
        queryClient.invalidateQueries({ queryKey: ['dashboard_ads'] });
      }
    };
    triggerDailyTasks();
  }, [queryClient]);

  const [metaValor, setMetaValor] = useState<number | null>(null);
  const [metaInput, setMetaInput] = useState('');
  const [editingMeta, setEditingMeta] = useState(false);
  const [faturamentoMes, setFaturamentoMes] = useState(0);



  // Queries
  const { data: pendentesTotal = 0 } = useQuery({
    queryKey: ['dashboard_pendentes'],
    queryFn: async () => {
      const { data } = await supabase.from('pedidos').select('valor').eq('status_pagamento', 'pendente').neq('is_free', true);
      return data?.reduce((s, p) => s + (Number(p.valor) || 0), 0) || 0;
    },
    staleTime: 5 * 60 * 1000,
  });

  const { data: metaData } = useQuery({
    queryKey: ['dashboard_meta', user?.id],
    queryFn: async () => {
      if (!user) return null;
      const now = new Date();
      const { data } = await supabase.from('metas_mensais' as any).select('*')
        .eq('user_id', user.id).eq('ano', now.getFullYear()).eq('mes', now.getMonth() + 1).maybeSingle();
      return data ? Number((data as any).valor) : null;
    },
    enabled: !!user,
    staleTime: 5 * 60 * 1000,
  });

  useEffect(() => {
    if (metaData !== undefined) {
      setMetaValor(metaData);
      setMetaInput(metaData ? String(metaData) : '');
    }
  }, [metaData]);

  const { data: channelBars = [] } = useQuery({
    queryKey: ['dashboard_channels', dateFrom, dateTo],
    queryFn: async () => {
      const channels = ['ADS', 'BASE', 'REP'];
      const { data, error } = await supabase
        .from('pedidos')
        .select('valor, canal')
        .in('canal', channels)
        .neq('is_free', true)
        .gte('data', dateFrom)
        .lte('data', dateTo);
      
      if (error) throw error;

      return channels.map(c => ({
        canal: c,
        valor: data?.filter(r => r.canal === c).reduce((s, r) => s + Number(r.valor), 0) || 0
      }));
    },
    staleTime: 5 * 60 * 1000,
  });

  const { data: adsConversion = { total: 0, pagou: 0 } } = useQuery({
    queryKey: ['dashboard_ads', dateFrom, dateTo],
    queryFn: async () => {
      // Convert local dates to UTC for timestamptz comparison (São Paulo = UTC-3)
      const toUTC = (dateStr: string, endOfDay: boolean) => {
        const [y, m, d] = dateStr.split('-').map(Number);
        const localDate = new Date(y, m - 1, d, endOfDay ? 23 : 0, endOfDay ? 59 : 0, endOfDay ? 59 : 0);
        return localDate.toISOString();
      };
      
      const rangeStart = toUTC(dateFrom, false);
      const rangeEnd = toUTC(dateTo, true);
      
      const { count: adsTotal } = await supabase.from('contatos').select('id', { count: 'exact', head: true })
        .eq('canal_origem', 'ADS').gte('created_at', rangeStart).lte('created_at', rangeEnd);
      const { count: adsPagou } = await supabase.from('pedidos').select('id', { count: 'exact', head: true })
        .eq('canal', 'ADS').eq('status_pagamento', 'pago').neq('is_free', true).gte('data', dateFrom).lte('data', dateTo);
      return { total: adsTotal || 0, pagou: adsPagou || 0 };
    },
    staleTime: 5 * 60 * 1000,
  });

  useEffect(() => {
    const channel = supabase.channel('dashboard-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'pedidos' }, () => {
        queryClient.invalidateQueries({ queryKey: ['dashboard_pendentes'] });
        queryClient.invalidateQueries({ queryKey: ['dashboard_data'] });
        queryClient.invalidateQueries({ queryKey: ['dashboard_ads'] });
        queryClient.invalidateQueries({ queryKey: ['dashboard_channels'] });
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [queryClient]);

  const saveMeta = async () => {
    if (!user) return;
    const val = parseFloat(metaInput.replace(',', '.'));
    if (!val || isNaN(val)) { toast.error('Valor inválido'); return; }
    const now = new Date();
    const { error } = await supabase.from('metas_mensais' as any).upsert({
      user_id: user.id,
      ano: now.getFullYear(),
      mes: now.getMonth() + 1,
      valor: val,
    }, { onConflict: 'user_id,ano,mes' });
    if (error) { toast.error('Erro ao salvar meta'); console.error(error); return; }
    setMetaValor(val);
    setEditingMeta(false);
    toast.success('Meta salva!');
  };
  const { data: dashboardData, isLoading } = useQuery({
    queryKey: ['dashboard_data', dateFrom, dateTo],
    queryFn: async () => {
      const year = new Date().getFullYear();
      const currentMonthStart = `${year}-${String(new Date().getMonth() + 1).padStart(2, '0')}-01`;

      const [pedRangeData, channelData] = await Promise.all([
        supabase.from('pedidos').select('id, valor, quantidade, canal, contato_id, data, produto, contatos(nome)').neq('is_free', true).gte('data', dateFrom).lte('data', dateTo),
        supabase.from('pedidos').select('valor, canal').neq('is_free', true).gte('data', currentMonthStart)
      ]);

      const fat = pedRangeData.data?.reduce((s, p) => s + Number(p.valor || 0), 0) || 0;
      const pedRange = pedRangeData.data || [];
      const totalPedidos = pedRange.length;
      const totalProdutos = pedRange.reduce((s, p) => s + (p.quantidade || 0), 0) || 0;

      // Clientes Novos = contatos únicos com pedido no período onde canal = ADS
      const novosSet = new Set<string>();
      pedRange.forEach(p => {
        if (p.canal === 'ADS' && p.contato_id) novosSet.add(p.contato_id);
      });

      // Clientes Recorrentes = contatos únicos com pedido no período onde canal IN (BASE, REP, C-REP)
      const recorrentesSet = new Set<string>();
      pedRange.forEach(p => {
        if ((p.canal === 'BASE' || p.canal === 'REP' || p.canal === 'C-REP') && p.contato_id) recorrentesSet.add(p.contato_id);
      });

      const dayStats = { faturamento: fat, ticket: totalPedidos ? fat / totalPedidos : 0, produtos: totalProdutos, novos: novosSet.size, recorrentes: recorrentesSet.size };
      
      const faturamentoMes = channelData.data?.reduce((s, r) => s + Number(r.valor || 0), 0) || 0;

      const todayStr = `${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}-${String(new Date().getDate()).padStart(2, '0')}`;
      const yesterdayDate = new Date(Date.now() - 86400000);
      const yesterdayStr = `${yesterdayDate.getFullYear()}-${String(yesterdayDate.getMonth() + 1).padStart(2, '0')}-${String(yesterdayDate.getDate()).padStart(2, '0')}`;
      
      const [todayData, yesterdayData] = await Promise.all([
        supabase.from('pedidos').select('valor').neq('is_free', true).gte('data', todayStr).lte('data', todayStr),
        supabase.from('pedidos').select('valor').neq('is_free', true).gte('data', yesterdayStr).lte('data', yesterdayStr)
      ]);

      const todayFat = todayData.data?.reduce((s, r) => s + Number(r.valor), 0) || 0;
      const yesterdayFat = yesterdayData.data?.reduce((s, r) => s + Number(r.valor), 0) || 0;

      let fatIndicator = { percent: 0, direction: 'neutral' as 'up'|'down'|'neutral' };
      if (yesterdayFat !== 0) {
        const pct = ((todayFat - yesterdayFat) / yesterdayFat) * 100;
        fatIndicator = { percent: Math.abs(pct), direction: pct > 0 ? 'up' : pct < 0 ? 'down' : 'neutral' };
      }

      const months: { mes: string; valor: number }[] = [];
      const monthPromises = [];
      for (let m = 1; m <= 12; m++) {
        const start = `${year}-${String(m).padStart(2, '0')}-01`;
        const end = m === 12 ? `${year + 1}-01-01` : `${year}-${String(m + 1).padStart(2, '0')}-01`;
        monthPromises.push(supabase.from('pedidos').select('valor').neq('is_free', true).gte('data', start).lt('data', end));
      }
      const monthResults = await Promise.all(monthPromises);
      monthResults.forEach((res, m) => {
        const total = res.data?.reduce((s, r) => s + Number(r.valor), 0) || 0;
        months.push({ mes: ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'][m], valor: total });
      });

      return { dayStats, pedidosDia: pedRange, faturamentoMes, fatIndicator, monthlyChart: months };
    },
    staleTime: 5 * 60 * 1000,
  });

  const dayStats = dashboardData?.dayStats || { faturamento: 0, ticket: 0, produtos: 0, novos: 0, recorrentes: 0 };
  const pedidosDia = dashboardData?.pedidosDia || [];
  const fatIndicator = dashboardData?.fatIndicator || { percent: 0, direction: 'neutral' };
  const monthlyChart = dashboardData?.monthlyChart || [];
  const faturamentoMesVal = dashboardData?.faturamentoMes || 0;;

  if (isLoading) return <div className="space-y-4"><Skeleton className="h-32" /><Skeleton className="h-64" /></div>;

  const statCards = [
    { icon: DollarSign, label: 'Faturamento Total', value: formatBRL(dayStats.faturamento) },
    { icon: Tag, label: 'Ticket Médio', value: formatBRL(dayStats.ticket) },
    { icon: Package, label: 'Total de Produtos Vendidos', value: dayStats.produtos },
    { icon: UserPlus, label: 'Clientes Novos', value: dayStats.novos },
    { icon: RefreshCw, label: 'Clientes Recorrentes', value: dayStats.recorrentes },
  ];

  const metaPercent = metaValor ? Math.min((faturamentoMesVal / metaValor) * 100, 100) : 0;
  const now = new Date();
  const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  const diasRestantes = Math.max(0, endOfMonth.getDate() - now.getDate());

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-bold">Dashboard</h1>
        <div className="flex items-center gap-2">
          {(['hoje', 'ontem', 'semana', '15dias'] as const).map(p => (
            <Button
              key={p}
              variant={period === p ? 'default' : 'outline'}
              size="sm"
              className="text-xs h-8"
              onClick={() => setPeriod(p)}
            >
              {p === 'hoje' ? 'Hoje' : p === 'ontem' ? 'Ontem' : p === 'semana' ? 'Essa semana' : 'Últimos 15 dias'}
            </Button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
        {statCards.map((s, i) => (
          <Card key={i} className={i === 0 ? "border-purple-300 border-2" : ""}>
            <CardContent className="pt-4 pb-3 px-4">
              <div className="flex items-center gap-2 mb-1">
                <s.icon className="w-4 h-4 text-primary" />
                <span className="text-xs text-muted-foreground">{s.label}</span>
              </div>
              <p className="text-lg font-bold">{s.value}</p>
              {i === 0 && fatIndicator.direction !== 'neutral' && (
                <div className={`flex items-center gap-1 text-xs mt-1 ${fatIndicator.direction === 'up' ? 'text-green-600' : 'text-destructive'}`}>
                  {fatIndicator.direction === 'up' ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
                  <span>{fatIndicator.direction === 'up' ? '▲' : '▼'} {fatIndicator.percent.toFixed(0)}% vs ontem</span>
                </div>
              )}
            </CardContent>
          </Card>
        ))}
        {/* Pendentes card */}
        <Card className="border-orange-300 border-2 bg-orange-50/10">
          <CardContent className="pt-4 pb-3 px-4">
            <div className="flex items-center gap-2 mb-1">
              <CreditCard className="w-4 h-4 text-orange-600" />
              <span className="text-xs text-muted-foreground">Pendentes</span>
            </div>
            <p className="text-lg font-bold text-orange-700">{formatBRL(pendentesTotal)}</p>
          </CardContent>
        </Card>
      </div>

      {/* Meta Mensal Widget */}
      <Card>
        <CardContent className="pt-4 pb-4 px-4">
          <div className="flex items-center gap-2 mb-3">
            <Target className="w-4 h-4 text-primary" />
            <span className="text-sm font-bold">Meta do Mês</span>
          </div>
          {metaValor && !editingMeta ? (
            <div className="space-y-3">
              <div className="flex items-center justify-between text-sm">
                <span>Realizado: {formatBRL(faturamentoMesVal)}</span>
                <span className="font-bold">{metaPercent.toFixed(0)}%</span>
              </div>
              <Progress value={metaPercent} className="h-3 [&>div]:bg-[#2D5A27]" />
              <div className="flex items-center justify-between text-xs text-muted-foreground">
                <span>Meta: {formatBRL(metaValor)}</span>
                <span>Faltam {diasRestantes} dias</span>
              </div>
              <Button variant="ghost" size="sm" className="text-xs" onClick={() => setEditingMeta(true)}>Editar meta</Button>
            </div>
          ) : (
            <div className="flex items-center gap-2">
              <Input placeholder="R$ 0,00" value={metaInput} onChange={e => setMetaInput(e.target.value)} className="w-40 h-8 text-sm" />
              <Button size="sm" onClick={saveMeta} className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground h-8">
                {metaValor ? 'Atualizar' : 'Definir meta do mês'}
              </Button>
              {editingMeta && <Button variant="ghost" size="sm" className="h-8" onClick={() => setEditingMeta(false)}>Cancelar</Button>}
            </div>
          )}
        </CardContent>
      </Card>

      <div className="grid md:grid-cols-2 gap-6">
        <Card>
          <CardHeader><CardTitle className="text-sm">Faturamento x Mês</CardTitle></CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={250}>
              <LineChart data={monthlyChart}>
                <XAxis dataKey="mes" tick={{ fontSize: 12 }} />
                <YAxis tick={{ fontSize: 12 }} tickFormatter={v => `R$${(v / 1000).toFixed(0)}k`} />
                <Tooltip formatter={(v: number) => formatBRL(v)} />
                <Line type="monotone" dataKey="valor" stroke="#2D5A27" strokeWidth={2} dot={{ fill: '#2D5A27' }} />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="text-sm">Faturamento por Canal</CardTitle></CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={250}>
              <BarChart data={channelBars}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="canal" tick={{ fontSize: 12 }} />
                <YAxis tick={{ fontSize: 12 }} tickFormatter={v => `R$${(v / 1000).toFixed(0)}k`} />
                <Tooltip formatter={(v: number) => formatBRL(v)} />
                <Bar dataKey="valor" fill="#2D5A27" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        <Card>
          <CardHeader><CardTitle className="text-sm">Taxa Conversão Mensagens ADS</CardTitle></CardHeader>
          <CardContent>
            <div className="flex items-center justify-center gap-8 py-4">
              <div className="text-center">
                <p className="text-3xl font-bold text-destructive">{adsConversion.total}</p>
                <p className="text-xs text-muted-foreground">Contatos ADS</p>
              </div>
              <span className="text-2xl text-muted-foreground">/</span>
              <div className="text-center">
                <p className="text-3xl font-bold text-primary">{adsConversion.pagou}</p>
                <p className="text-xs text-muted-foreground">Pedidos ADS</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="text-sm">Pedidos do Período</CardTitle></CardHeader>
          <CardContent>
            {pedidosDia.length === 0 ? (
              <p className="text-muted-foreground text-sm">Nenhum pedido no período</p>
            ) : (
              <div className="overflow-x-auto max-h-64 overflow-y-auto">
                <table className="w-full text-sm">
                  <thead><tr className="border-b"><th className="text-left py-1">Nome</th><th className="text-left py-1">Produto</th><th className="text-right py-1">Valor</th><th className="text-left py-1">Canal</th></tr></thead>
                  <tbody>
                    {pedidosDia.map(p => (
                      <tr key={p.id} className="border-b border-border/50">
                        <td className="py-1.5">{(p.contatos as any)?.nome || '—'}</td>
                        <td className="py-1.5">{renderProdutos(p.produto)}</td>
                        <td className="py-1.5 text-right">{formatBRL(Number(p.valor))}</td>
                        <td className="py-1.5 uppercase">{p.canal}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

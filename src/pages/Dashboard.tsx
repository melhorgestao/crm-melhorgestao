import { useEffect, useState, useMemo } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { formatBRL } from '@/lib/format';
import { cn } from '@/lib/utils';
import { DollarSign, Tag, Package, UserPlus, RefreshCw, TrendingUp, TrendingDown, Target, CreditCard, Users } from 'lucide-react';
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, BarChart, Bar, CartesianGrid, Cell, LabelList, PieChart, Pie, Legend } from 'recharts';

// Cor por canal (paleta categórica validada CVD-safe — slots 1/2/3 da dataviz).
const CANAL_CORES: Record<string, string> = { ADS: '#2a78d6', BASE: '#eb6834', REP: '#1baf7a' };

// Funil do pipeline (colunas do Kanban + Venda). Cores alinhadas ao acento de
// cada coluna do Kanban; Venda em verde (resultado).
const PIPELINE_CORES: Record<string, string> = {
  'Suporte': '#2a78d6', 'Follow-up': '#eb6834', 'Fechamento': '#1baf7a', 'RMKT': '#4a3aa7', 'Venda': '#008300',
};

// Anel de progresso da meta (SVG puro, sem dependência). Preenche conforme %.
function MetaRing({ percent, size = 116, stroke = 11 }: { percent: number; size?: number; stroke?: number }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = Math.max(0, Math.min(100, percent));
  const offset = c * (1 - pct / 100);
  const atingiu = pct >= 100;
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" strokeWidth={stroke} className="stroke-muted" />
        <circle
          cx={size / 2} cy={size / 2} r={r} fill="none" strokeWidth={stroke} strokeLinecap="round"
          stroke={atingiu ? '#008300' : '#2D5A27'}
          strokeDasharray={c} strokeDashoffset={offset}
          style={{ transition: 'stroke-dashoffset 700ms ease' }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-2xl font-bold tabular-nums leading-none">{pct.toFixed(0)}%</span>
        <span className="text-[10px] text-muted-foreground mt-0.5">da meta</span>
      </div>
    </div>
  );
}
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
  
  const [period, setPeriod] = useState<'hoje' | 'ontem' | '7dias' | '15dias' | '30dias'>('hoje');

  const getPeriodRange = () => {
    const now = new Date();
    const fmt = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    const today = fmt(now);

    if (period === 'hoje') return { from: today, to: today };

    if (period === 'ontem') {
      const y = new Date(now.getTime() - 86400000);
      const yesterday = fmt(y);
      return { from: yesterday, to: yesterday };
    }

    // Ultimos N dias inclui hoje (today - (N-1) ate today)
    const n = period === '7dias' ? 7 : period === '15dias' ? 15 : 30;
    const start = new Date(now.getTime() - (n - 1) * 86400000);
    return { from: fmt(start), to: today };
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
      // Faturamento por canal com a MESMA métrica de caixa real do widget:
      //   VENDA        -> por realizado_em||data (pendente entra quando pagou)
      //   PARCELA_VENDA-> por data
      // C-REP é dobrado em REP (igual à contagem de representantes dos KPIs).
      const { data, error } = await supabase
        .from('lancamentos_socios')
        .select('valor, canal, data, realizado_em, tipo')
        .in('tipo', ['VENDA', 'PARCELA_VENDA']);

      if (error) throw error;

      const channels = ['ADS', 'BASE', 'REP'] as const;
      const totals: Record<string, number> = { ADS: 0, BASE: 0, REP: 0 };
      (data || []).forEach((r: any) => {
        const ref = r.tipo === 'VENDA'
          ? (r.realizado_em ? new Date(r.realizado_em).toISOString().slice(0, 10) : r.data)
          : r.data;
        if (!ref || ref < dateFrom || ref > dateTo) return;
        const key = (r.canal === 'REP' || r.canal === 'C-REP') ? 'REP' : r.canal;
        if (key in totals) totals[key] += Number(r.valor || 0);
      });

      return channels.map(c => ({ canal: c, valor: totals[c] }));
    },
    staleTime: 5 * 60 * 1000,
  });

  // Funil do pipeline: contagem atual de contatos por coluna do Kanban + vendas
  // do período. Mesmo mapeamento coluna↔estado do Kanban (fechamento_aguardando
  // conta como Fechamento, não Suporte).
  const { data: pipelineBars = [] } = useQuery({
    queryKey: ['dashboard_pipeline', dateFrom, dateTo],
    queryFn: async () => {
      const [{ data: contatos }, { count: vendas }] = await Promise.all([
        supabase.from('contatos')
          .select('ultima_interacao, fechamento_aguardando')
          .in('ultima_interacao', ['suporte', 'wait_follow_up', 'follow_up', 'wait_follow_up_custom', 'em_fechamento', 'rmkt']),
        supabase.from('pedidos').select('id', { count: 'exact', head: true })
          .neq('is_free', true).eq('status_pagamento', 'pago').gte('data_pago', dateFrom).lte('data_pago', dateTo),
      ]);

      let suporte = 0, followup = 0, fechamento = 0, rmkt = 0;
      (contatos || []).forEach((r: any) => {
        const st = r.ultima_interacao;
        if (st === 'suporte') { r.fechamento_aguardando ? fechamento++ : suporte++; }
        else if (st === 'em_fechamento') fechamento++;
        else if (st === 'rmkt') rmkt++;
        else followup++; // wait_follow_up / follow_up / wait_follow_up_custom
      });

      return [
        { etapa: 'Suporte', qtd: suporte },
        { etapa: 'Follow-up', qtd: followup },
        { etapa: 'Fechamento', qtd: fechamento },
        { etapa: 'RMKT', qtd: rmkt },
        { etapa: 'Venda', qtd: vendas || 0 },
      ];
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

      // Realizado da Meta = fluxo de caixa REAL do mes, via lancamentos_socios.
      // Soma VENDA (pago direto OU pendente convertido) + PARCELA_VENDA por
      // data efetiva de entrada do dinheiro:
      //   - VENDA com realizado_em IS NOT NULL -> filtra por realizado_em
      //     (pendente que virou pago — data do pagamento)
      //   - VENDA com realizado_em IS NULL -> filtra por data
      //     (criado ja pago — data da criacao)
      //   - PARCELA_VENDA -> filtra por data (cada parcela na data que foi paga)

      const [pedRangeData, vendasAll, parcelasRange, parcelasMes] = await Promise.all([
        // Pedidos pagos no periodo (para metricas auxiliares: ticket, produtos, clientes)
        supabase.from('pedidos').select('id, valor, valor_original, desconto_total, quantidade, canal, contato_id, data_pago, produto, contatos(nome)').neq('is_free', true).eq('status_pagamento', 'pago').gte('data_pago', dateFrom).lte('data_pago', dateTo),
        // TODAS as VENDAs em lancamentos_socios (sera filtrado em JS por realizado_em/data)
        supabase.from('lancamentos_socios').select('valor, data, realizado_em').eq('tipo', 'VENDA'),
        // PARCELA_VENDAs do PERIODO atual (Faturamento Total do widget)
        supabase.from('lancamentos_socios').select('valor').eq('tipo', 'PARCELA_VENDA').gte('data', dateFrom).lte('data', dateTo),
        // PARCELA_VENDAs do MES (Realizado da Meta — mes inteiro)
        supabase.from('lancamentos_socios').select('valor').eq('tipo', 'PARCELA_VENDA').gte('data', currentMonthStart),
      ]);

      const pedRange = pedRangeData.data || [];
      const totalPedidos = pedRange.length;
      const totalProdutos = pedRange.reduce((s, p) => s + (p.quantidade || 0), 0) || 0;

      // Faturamento Total do PERIODO = caixa real recebido nesse range
      // (VENDA com realizado_em||data no range) + (PARCELA_VENDA com data no range)
      const fatVendasRange = (vendasAll.data || []).filter((v: any) => {
        const ref = v.realizado_em
          ? new Date(v.realizado_em).toISOString().slice(0, 10)
          : v.data;
        return ref >= dateFrom && ref <= dateTo;
      }).reduce((s: number, v: any) => s + Number(v.valor || 0), 0);
      const fatParcelasRange = (parcelasRange.data || []).reduce((s: number, p: any) => s + Number(p.valor || 0), 0);
      const fat = fatVendasRange + fatParcelasRange;

      // Ticket medio usa o cash flow real dividido pelo numero de pedidos pagos
      // que CONTRIBUIRAM no range (pagos completos + pendentes com parcela no range)
      const pedidosComCaixaNoRange = pedRange.length;

      // Clientes Novos = contatos únicos com pedido no período onde canal = ADS
      const novosSet = new Set<string>();
      pedRange.forEach(p => {
        if (p.canal === 'ADS' && p.contato_id) novosSet.add(p.contato_id);
      });

      // Clientes Recorrentes = contatos únicos com pedido no período onde canal = BASE
      const recorrentesSet = new Set<string>();
      pedRange.forEach(p => {
        if (p.canal === 'BASE' && p.contato_id) recorrentesSet.add(p.contato_id);
      });

      // Clientes Representantes = contatos únicos com pedido no período onde canal IN (REP, C-REP)
      const repSet = new Set<string>();
      pedRange.forEach(p => {
        if ((p.canal === 'REP' || p.canal === 'C-REP') && p.contato_id) repSet.add(p.contato_id);
      });

      const dayStats = { faturamento: fat, ticket: pedidosComCaixaNoRange ? fat / pedidosComCaixaNoRange : 0, produtos: totalProdutos, novos: novosSet.size, recorrentes: recorrentesSet.size, representantes: repSet.size };

      // Calcula Realizado da Meta a partir de lancamentos_socios.
      // Para VENDA: usa realizado_em se presente (pendente -> pago), senao usa
      // data (criado ja pago). Ambos comparados com o inicio do mes atual.
      const monthStartISO = currentMonthStart;
      const realizadoVendas = (vendasAll.data || []).filter((v: any) => {
        const ref = v.realizado_em
          ? new Date(v.realizado_em).toISOString().slice(0, 10)
          : v.data;
        return ref >= monthStartISO;
      }).reduce((s: number, v: any) => s + Number(v.valor || 0), 0);
      const realizadoParcelas = (parcelasMes.data || []).reduce((s: number, p: any) => s + Number(p.valor || 0), 0);
      const faturamentoMes = realizadoVendas + realizadoParcelas;

      // Periodo de comparacao espelha o periodo atual com o mesmo numero de dias.
      // 'hoje' -> ontem | 'ontem' -> anteontem | 'semana' -> semana passada | '15dias' -> 15 anteriores
      const toISO = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      const fromDate = new Date(`${dateFrom}T00:00:00`);
      const toDate = new Date(`${dateTo}T00:00:00`);
      const spanDays = Math.round((toDate.getTime() - fromDate.getTime()) / 86400000) + 1;
      const prevToDate = new Date(fromDate.getTime() - 86400000);
      const prevFromDate = new Date(prevToDate.getTime() - (spanDays - 1) * 86400000);
      const prevFromStr = toISO(prevFromDate);
      const prevToStr = toISO(prevToDate);

      // Caixa real do periodo anterior (mesma logica do faturamento atual)
      const [prevParcelasData] = await Promise.all([
        supabase.from('lancamentos_socios').select('valor').eq('tipo', 'PARCELA_VENDA').gte('data', prevFromStr).lte('data', prevToStr),
      ]);
      const prevVendasFat = (vendasAll.data || []).filter((v: any) => {
        const ref = v.realizado_em
          ? new Date(v.realizado_em).toISOString().slice(0, 10)
          : v.data;
        return ref >= prevFromStr && ref <= prevToStr;
      }).reduce((s: number, v: any) => s + Number(v.valor || 0), 0);
      const prevParcelasFat = (prevParcelasData.data || []).reduce((s: number, p: any) => s + Number(p.valor || 0), 0);
      const currentFat = fat;
      const prevFat = prevVendasFat + prevParcelasFat;

      const compareLabel = period === 'hoje' ? 'vs ontem'
        : period === 'ontem' ? 'vs anteontem'
        : period === '7dias' ? 'vs 7 dias anteriores'
        : period === '15dias' ? 'vs 15 dias anteriores'
        : 'vs 30 dias anteriores';

      let fatIndicator = { percent: 0, direction: 'neutral' as 'up'|'down'|'neutral', label: compareLabel };
      if (prevFat !== 0) {
        const pct = ((currentFat - prevFat) / prevFat) * 100;
        fatIndicator = { percent: Math.abs(pct), direction: pct > 0 ? 'up' : pct < 0 ? 'down' : 'neutral', label: compareLabel };
      }

      // Faturamento x Mês = MESMA métrica de caixa real do widget de Faturamento
      // (não mais pedidos.valor por data_pago, que divergia). Bucketa por mês:
      //   VENDA        -> mês de realizado_em||data (pendente que pagou depois
      //                   entra no mês em que foi de fato paga)
      //   PARCELA_VENDA-> mês da data (cada parcela no mês que caiu no caixa)
      const { data: parcelasAno } = await supabase
        .from('lancamentos_socios')
        .select('valor, data').eq('tipo', 'PARCELA_VENDA')
        .gte('data', `${year}-01-01`).lt('data', `${year + 1}-01-01`);

      const monthTotals = new Array(12).fill(0);
      const bucket = (ref: string | null | undefined, valor: any) => {
        if (!ref) return;
        const y = Number(ref.slice(0, 4));
        const mo = Number(ref.slice(5, 7));
        if (y === year && mo >= 1 && mo <= 12) monthTotals[mo - 1] += Number(valor || 0);
      };
      (vendasAll.data || []).forEach((v: any) => {
        const ref = v.realizado_em ? new Date(v.realizado_em).toISOString().slice(0, 10) : v.data;
        bucket(ref, v.valor);
      });
      (parcelasAno || []).forEach((p: any) => bucket(p.data, p.valor));

      const NOMES_MES = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      const months: { mes: string; valor: number }[] = monthTotals.map((valor, i) => ({ mes: NOMES_MES[i], valor }));

      // Top produtos do período (por unidades vendidas nos pedidos pagos)
      const prodMap = new Map<string, number>();
      pedRange.forEach((p: any) => {
        const nome = (p.produto || '—').trim() || '—';
        prodMap.set(nome, (prodMap.get(nome) || 0) + (p.quantidade || 0));
      });
      const topProdutos = [...prodMap.entries()]
        .map(([produto, qtd]) => ({ produto, qtd }))
        .sort((a, b) => b.qtd - a.qtd)
        .slice(0, 5);

      return { dayStats, pedidosDia: pedRange, faturamentoMes, fatIndicator, monthlyChart: months, topProdutos };
    },
    staleTime: 5 * 60 * 1000,
  });

  const dayStats = dashboardData?.dayStats || { faturamento: 0, ticket: 0, produtos: 0, novos: 0, recorrentes: 0, representantes: 0 };
  const pedidosDia = dashboardData?.pedidosDia || [];
  const fatIndicator = dashboardData?.fatIndicator || { percent: 0, direction: 'neutral', label: 'vs ontem' };
  const monthlyChart = dashboardData?.monthlyChart || [];
  const topProdutos = dashboardData?.topProdutos || [];
  const faturamentoMesVal = dashboardData?.faturamentoMes || 0;
  const clientesComposicao = [
    { nome: 'Novos', valor: dayStats.novos, cor: CANAL_CORES.ADS },
    { nome: 'Recorrentes', valor: dayStats.recorrentes, cor: CANAL_CORES.BASE },
    { nome: 'Representantes', valor: dayStats.representantes, cor: CANAL_CORES.REP },
  ].filter(d => d.valor > 0);

  if (isLoading) return <div className="space-y-4"><Skeleton className="h-32" /><Skeleton className="h-64" /></div>;

  const statCards = [
    { icon: DollarSign, label: 'Faturamento Total', value: formatBRL(dayStats.faturamento) },
    { icon: Tag, label: 'Ticket Médio', value: formatBRL(dayStats.ticket) },
    { icon: Package, label: 'Total de Produtos Vendidos', value: dayStats.produtos },
    { icon: UserPlus, label: 'Clientes Novos', value: dayStats.novos },
    { icon: RefreshCw, label: 'Clientes Recorrentes', value: dayStats.recorrentes },
    { icon: Users, label: 'Clientes Representantes', value: dayStats.representantes },
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
          {(['hoje', 'ontem', '7dias', '15dias', '30dias'] as const).map(p => (
            <Button
              key={p}
              variant={period === p ? 'default' : 'outline'}
              size="sm"
              className="text-xs h-8"
              onClick={() => setPeriod(p)}
            >
              {p === 'hoje' ? 'Hoje' : p === 'ontem' ? 'Ontem' : p === '7dias' ? 'Últimos 7 dias' : p === '15dias' ? 'Últimos 15 dias' : 'Últimos 30 dias'}
            </Button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
        {statCards.map((s, i) => (
          <Card key={i} className={cn('rounded-xl border-border/50 shadow-sm transition-all duration-150 hover:shadow-md hover:-translate-y-0.5', i === 0 && 'ring-1 ring-primary/25')}>
            <CardContent className="pt-4 pb-3 px-4">
              <div className="flex items-center gap-2 mb-2">
                <span className="inline-flex items-center justify-center w-7 h-7 rounded-lg bg-primary/10 text-primary shrink-0">
                  <s.icon className="w-4 h-4" />
                </span>
                <span className="text-[11px] uppercase tracking-wide text-muted-foreground leading-tight">{s.label}</span>
              </div>
              <p className="text-2xl font-bold tracking-tight tabular-nums">{s.value}</p>
              {i === 0 && fatIndicator.direction !== 'neutral' && (
                <div className={cn('flex items-center gap-1 text-xs mt-1 font-medium',
                  fatIndicator.direction === 'up' ? 'text-emerald-600' : 'text-destructive')}>
                  {fatIndicator.direction === 'up' ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
                  <span>{fatIndicator.percent.toFixed(0)}% {fatIndicator.label}</span>
                </div>
              )}
            </CardContent>
          </Card>
        ))}
        {/* Pendentes card */}
        <Card className="rounded-xl border-border/50 shadow-sm ring-1 ring-orange-300/50 transition-all duration-150 hover:shadow-md hover:-translate-y-0.5">
          <CardContent className="pt-4 pb-3 px-4">
            <div className="flex items-center gap-2 mb-2">
              <span className="inline-flex items-center justify-center w-7 h-7 rounded-lg bg-orange-500/10 text-orange-600 shrink-0">
                <CreditCard className="w-4 h-4" />
              </span>
              <span className="text-[11px] uppercase tracking-wide text-muted-foreground leading-tight">Pendentes</span>
            </div>
            <p className="text-2xl font-bold tracking-tight tabular-nums text-orange-700">{formatBRL(pendentesTotal)}</p>
          </CardContent>
        </Card>
      </div>

      {/* Meta Mensal Widget */}
      <Card className="rounded-xl border-border/50 shadow-sm">
        <CardContent className="pt-4 pb-4 px-4">
          <div className="flex items-center gap-2 mb-3">
            <Target className="w-4 h-4 text-primary" />
            <span className="text-sm font-bold">Caixa Mensal</span>
          </div>
          {metaValor && !editingMeta ? (
            <div className="flex items-center gap-5">
              <MetaRing percent={metaPercent} />
              <div className="flex-1 min-w-0 space-y-2">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-xs uppercase tracking-wide text-muted-foreground">Realizado</span>
                  <span className="text-lg font-bold tabular-nums">{formatBRL(faturamentoMesVal)}</span>
                </div>
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-xs uppercase tracking-wide text-muted-foreground">Meta</span>
                  <span className="text-sm font-medium tabular-nums text-muted-foreground">{formatBRL(metaValor)}</span>
                </div>
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-xs uppercase tracking-wide text-muted-foreground">Faltam</span>
                  <span className="text-sm font-medium tabular-nums">{formatBRL(Math.max(0, metaValor - faturamentoMesVal))} · {diasRestantes} dias</span>
                </div>
                <Button variant="ghost" size="sm" className="text-xs h-7 px-2 -ml-2" onClick={() => setEditingMeta(true)}>Editar meta</Button>
              </div>
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
        <Card className="rounded-xl border-border/50 shadow-sm">
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

        <Card className="rounded-xl border-border/50 shadow-sm">
          <CardHeader><CardTitle className="text-sm">Faturamento por Canal</CardTitle></CardHeader>
          <CardContent>
            {channelBars.every(c => c.valor === 0) ? (
              <div className="h-[250px] flex flex-col items-center justify-center text-center gap-1">
                <p className="text-sm text-muted-foreground">Sem faturamento no período</p>
                <p className="text-xs text-muted-foreground/60">Selecione um intervalo maior no topo</p>
              </div>
            ) : (
              <ResponsiveContainer width="100%" height={250}>
                <BarChart data={channelBars}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-muted" />
                  <XAxis dataKey="canal" tick={{ fontSize: 12 }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fontSize: 12 }} axisLine={false} tickLine={false}
                    tickFormatter={v => v >= 1000 ? `R$${(v / 1000).toFixed(0)}k` : `R$${v}`} />
                  <Tooltip formatter={(v: number) => formatBRL(v)} cursor={{ fill: 'hsl(var(--muted))', opacity: 0.4 }} />
                  <Bar dataKey="valor" radius={[4, 4, 0, 0]} maxBarSize={72}>
                    {channelBars.map(c => <Cell key={c.canal} fill={CANAL_CORES[c.canal] || '#2a78d6'} />)}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        <Card className="rounded-xl border-border/50 shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Funil do Pipeline</CardTitle>
            <p className="text-xs text-muted-foreground">Contatos por coluna do Kanban · Venda = pedidos pagos no período</p>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={pipelineBars} layout="vertical" margin={{ left: 4, right: 32, top: 4, bottom: 4 }}>
                <XAxis type="number" hide />
                <YAxis type="category" dataKey="etapa" width={78} tick={{ fontSize: 12 }} axisLine={false} tickLine={false} />
                <Tooltip cursor={{ fill: 'hsl(var(--muted))', opacity: 0.4 }} formatter={(v: number) => [v, 'Contatos']} />
                <Bar dataKey="qtd" radius={[0, 4, 4, 0]} maxBarSize={26} isAnimationActive animationDuration={700}>
                  {pipelineBars.map(b => <Cell key={b.etapa} fill={PIPELINE_CORES[b.etapa] || '#2a78d6'} />)}
                  <LabelList dataKey="qtd" position="right" className="fill-foreground" fontSize={12} />
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card className="rounded-xl border-border/50 shadow-sm">
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

      <div className="grid md:grid-cols-2 gap-6">
        {/* Top produtos do período */}
        <Card className="rounded-xl border-border/50 shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Top Produtos</CardTitle>
            <p className="text-xs text-muted-foreground">Mais vendidos no período (unidades)</p>
          </CardHeader>
          <CardContent>
            {topProdutos.length === 0 ? (
              <div className="h-[220px] flex items-center justify-center">
                <p className="text-sm text-muted-foreground">Nenhuma venda no período</p>
              </div>
            ) : (
              <ResponsiveContainer width="100%" height={220}>
                <BarChart data={topProdutos} layout="vertical" margin={{ left: 4, right: 32, top: 4, bottom: 4 }}>
                  <XAxis type="number" hide />
                  <YAxis type="category" dataKey="produto" width={120} tick={{ fontSize: 12 }} axisLine={false} tickLine={false} />
                  <Tooltip cursor={{ fill: 'hsl(var(--muted))', opacity: 0.4 }} formatter={(v: number) => [v, 'Unidades']} />
                  <Bar dataKey="qtd" fill="#2a78d6" radius={[0, 4, 4, 0]} maxBarSize={26} animationDuration={700}>
                    <LabelList dataKey="qtd" position="right" className="fill-foreground" fontSize={12} />
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>

        {/* Composição de clientes do período */}
        <Card className="rounded-xl border-border/50 shadow-sm">
          <CardHeader>
            <CardTitle className="text-sm">Composição de Clientes</CardTitle>
            <p className="text-xs text-muted-foreground">Quem comprou no período, por origem</p>
          </CardHeader>
          <CardContent>
            {(dayStats.novos + dayStats.recorrentes + dayStats.representantes) === 0 ? (
              <div className="h-[220px] flex items-center justify-center">
                <p className="text-sm text-muted-foreground">Nenhum cliente no período</p>
              </div>
            ) : (
              <ResponsiveContainer width="100%" height={220}>
                <PieChart>
                  <Pie
                    data={clientesComposicao}
                    dataKey="valor" nameKey="nome" innerRadius={54} outerRadius={82} paddingAngle={2} stroke="none"
                    animationDuration={700}
                  >
                    {clientesComposicao.map((d, i) => <Cell key={i} fill={d.cor} />)}
                  </Pie>
                  <Tooltip formatter={(v: number, n) => [v, n]} />
                  <Legend verticalAlign="bottom" height={24} iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                </PieChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

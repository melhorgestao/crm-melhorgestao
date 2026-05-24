import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Info, TrendingUp, TrendingDown } from 'lucide-react';
import { formatBRL, formatPercent } from '@/lib/format';
import { cn } from '@/lib/utils';

type DeltaInfo = { percent: number; direction: 'up' | 'down' | 'neutral' } | null;

export default function MetricasPage() {
  const [loading, setLoading] = useState(true);
  const [month, setMonth] = useState(new Date().getMonth() + 1);
  const [year, setYear] = useState(new Date().getFullYear());
  const [data, setData] = useState<any>({});
  const [pendentesTotal, setPendentesTotal] = useState(0);
  const [deltas, setDeltas] = useState<{ fat: DeltaInfo; prod: DeltaInfo; lucro: DeltaInfo }>({ fat: null, prod: null, lucro: null });

  useEffect(() => { fetchData(); fetchPendentes(); }, [month, year]);

  const fetchPendentes = async () => {
    // Exclui pedidos FREE (sem impacto financeiro)
    const { data } = await supabase.from('pedidos').select('valor, is_free').eq('status_pagamento', 'pendente').neq('is_free', true);
    setPendentesTotal(data?.reduce((s, p) => s + (Number(p.valor) || 0), 0) || 0);
  };

  // Calcula soma agregada (faturamento, produtos non-free, lucro) num range arbitrario.
  // Reusa a mesma logica de pagos+pendentes (non-free) e financeiro do periodo.
  const computeRangeMetrics = async (startISO: string, endISO: string) => {
    const [{ data: pedPagos }, { data: pedPend }, { data: fin }] = await Promise.all([
      supabase.from('pedidos').select('valor, quantidade, canal')
        .eq('status_pagamento', 'pago').neq('is_free', true)
        .gte('data_pago', startISO).lt('data_pago', endISO),
      supabase.from('pedidos').select('valor, quantidade, canal')
        .eq('status_pagamento', 'pendente').neq('is_free', true)
        .gte('data', startISO).lt('data', endISO),
      supabase.from('financeiro').select('tipo, valor').gte('data', startISO).lt('data', endISO),
    ]);
    const ped = [...(pedPagos || []), ...(pedPend || [])];
    const fat = ped.reduce((s, p: any) => s + (Number(p.valor) || 0), 0);
    const prod = ped.reduce((s, p: any) => s + (p.quantidade || 0), 0);
    const despesas = (fin || []).filter((f: any) => f.tipo === 'despesa');
    const custo = despesas.reduce((s: number, d: any) => s + Number(d.valor), 0);
    const lucro = fat - custo;
    return { fat, prod, lucro };
  };

  // Compara periodo atual com mesmo numero de dias do mes anterior.
  // Ex: mes atual em 15/maio -> compara com 1-15/abril
  const fetchDeltas = async (start: string, end: string) => {
    const startD = new Date(`${start}T00:00:00`);
    const endD = new Date(`${end}T00:00:00`);
    const today = new Date();
    const todayISO = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    // Se end > hoje (mes ainda em curso), usa hoje como limite real
    const realEnd = end > todayISO ? todayISO : end;
    const realEndD = new Date(`${realEnd}T00:00:00`);
    // N dias corridos no periodo atual ate hoje
    const nDays = Math.max(1, Math.round((realEndD.getTime() - startD.getTime()) / 86400000) + 1);

    // Mes anterior: mesmos N primeiros dias
    const prevMonth = startD.getMonth() === 0 ? 11 : startD.getMonth() - 1;
    const prevYear = startD.getMonth() === 0 ? startD.getFullYear() - 1 : startD.getFullYear();
    const prevStartD = new Date(prevYear, prevMonth, 1);
    const prevEndD = new Date(prevYear, prevMonth, Math.min(nDays, daysInMonth(prevYear, prevMonth)));
    const toISO = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    // Range exclusivo no final (lt), entao adicionamos +1 dia ao limite
    const prevEndExclusive = new Date(prevEndD.getTime() + 86400000);
    // Range atual ate realEnd inclusive
    const currEndExclusive = new Date(realEndD.getTime() + 86400000);

    const [curr, prev] = await Promise.all([
      computeRangeMetrics(start, toISO(currEndExclusive)),
      computeRangeMetrics(toISO(prevStartD), toISO(prevEndExclusive)),
    ]);

    const makeDelta = (a: number, b: number): DeltaInfo => {
      if (!b) return null;
      const pct = ((a - b) / b) * 100;
      return { percent: Math.abs(pct), direction: pct > 0 ? 'up' : pct < 0 ? 'down' : 'neutral' };
    };

    setDeltas({
      fat: makeDelta(curr.fat, prev.fat),
      prod: makeDelta(curr.prod, prev.prod),
      lucro: makeDelta(curr.lucro, prev.lucro),
    });
  };

  const daysInMonth = (y: number, m: number) => new Date(y, m + 1, 0).getDate();

  const fetchData = async () => {
    setLoading(true);
    const start = `${year}-${String(month).padStart(2, '0')}-01`;
    const nextM = month === 12 ? 1 : month + 1;
    const nextY = month === 12 ? year + 1 : year;
    const end = `${nextY}-${String(nextM).padStart(2, '0')}-01`;

    // PAGOS non-free do periodo (por data_pago = data do recebimento)
    const { data: pedPagos } = await supabase.from('pedidos').select('*')
      .eq('status_pagamento', 'pago').neq('is_free', true)
      .gte('data_pago', start).lt('data_pago', end);

    // PENDENTES non-free do periodo (por data de criacao)
    const { data: pedPend } = await supabase.from('pedidos').select('*')
      .eq('status_pagamento', 'pendente').neq('is_free', true)
      .gte('data', start).lt('data', end);

    // FREE do periodo (canal a parte)
    const { data: pedFree } = await supabase.from('pedidos').select('quantidade, data_pago')
      .eq('is_free', true).gte('data_pago', start).lt('data_pago', end);

    const ped = [...(pedPagos || []), ...(pedPend || [])];

    const { data: fin } = await supabase.from('financeiro').select('*').gte('data', start).lt('data', end);

    const receitas = (ped || []).filter(p => p.valor && Number(p.valor) > 0);
    const despesas = (fin || []).filter(f => f.tipo === 'despesa');

    const fatTotal = receitas.reduce((s, r) => s + Number(r.valor || 0), 0);
    const fatBase = receitas.filter(r => r.canal === 'BASE').reduce((s, r) => s + Number(r.valor || 0), 0);
    const fatAds = receitas.filter(r => r.canal === 'ADS').reduce((s, r) => s + Number(r.valor || 0), 0);
    const fatRep = receitas.filter(r => r.canal === 'REP').reduce((s, r) => s + Number(r.valor || 0), 0);

    const custoTotal = despesas.reduce((s, d) => s + Number(d.valor), 0);
    const custoAds = despesas.filter(d => d.categoria === 'ads').reduce((s, d) => s + Number(d.valor), 0);
    const etiquetaTotal = despesas.filter(d => d.categoria === 'etiqueta').reduce((s, d) => s + Number(d.valor), 0);
    const logTotal = despesas.filter(d => d.categoria === 'logistica').reduce((s, d) => s + Number(d.valor), 0);
    const materialTotal = despesas.filter(d => d.categoria === 'material').reduce((s, d) => s + Number(d.valor), 0);

    const prodTotal = (ped || []).reduce((s, p) => s + (p.quantidade || 0), 0);
    const prodAds = (ped || []).filter(p => p.canal === 'ADS').reduce((s, p) => s + (p.quantidade || 0), 0);
    const prodBase = (ped || []).filter(p => p.canal === 'BASE').reduce((s, p) => s + (p.quantidade || 0), 0);
    const prodRep = (ped || []).filter(p => p.canal === 'REP').reduce((s, p) => s + (p.quantidade || 0), 0);
    const prodFree = (pedFree || []).reduce((s, p) => s + (p.quantidade || 0), 0);
    const prodTotalRealistico = prodTotal + prodFree;

    // Custos operacional/produto continuam por unidade total (inclui FREE)
    const denomCustos = prodTotalRealistico > 0 ? prodTotalRealistico : 1;
    const lucro = fatTotal - custoTotal;
    const margem = fatTotal > 0 ? (lucro / fatTotal) * 100 : 0;
    const icm = (lucro + custoAds) > 0 ? (custoAds / (lucro + custoAds)) * 100 : 0;

    // CPA Un. ADS = custo ADS / unidades ADS (so unidades adquiridas via ads)
    const cpaUnAds = prodAds > 0 ? custoAds / prodAds : 0;
    // CAC = custo ADS / numero de pedidos ADS (custo por venda ADS)
    const pedidosAds = (ped || []).filter(p => p.canal === 'ADS').length;
    const cac = pedidosAds > 0 ? custoAds / pedidosAds : 0;

    const custoOpUn = (etiquetaTotal + logTotal) / denomCustos;
    const custoProdUn = materialTotal / denomCustos;

    const medLucroBase = prodBase > 0 ? (fatBase / prodBase) - custoProdUn - custoOpUn : 0;
    const medLucroAds = prodAds > 0 ? (fatAds / prodAds) - custoProdUn - custoOpUn - cpaUnAds : 0;
    const medLucroRep = prodRep > 0 ? (fatRep / prodRep) - custoProdUn - custoOpUn : 0;
    const medLucroGeral = prodTotal > 0 ? lucro / prodTotal : 0;

    setData({
      fatTotal, fatBase, fatAds, fatRep,
      custoTotal, custoAds, etiquetaTotal, logTotal, materialTotal,
      prodTotal, prodAds, prodBase, prodRep, prodFree, prodTotalRealistico, pedidosAds,
      lucro, margem, icm, cpaUnAds, cac, custoOpUn, custoProdUn,
      medLucroBase, medLucroAds, medLucroRep, medLucroGeral,
    });
    setLoading(false);

    // Delta% em background — nao bloqueia render
    fetchDeltas(start, end).catch(console.error);
  };

  // ---------- UI helpers ----------
  const InfoTip = ({ children }: { children: React.ReactNode }) => (
    <TooltipProvider delayDuration={150}>
      <Tooltip>
        <TooltipTrigger asChild>
          <button type="button" className="text-muted-foreground/60 hover:text-foreground transition" aria-label="Formula">
            <Info className="w-3.5 h-3.5" />
          </button>
        </TooltipTrigger>
        <TooltipContent className="max-w-xs text-xs leading-relaxed">
          {children}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );

  const MetricCard = ({ label, value, color = 'bg-card', tip }: { label: string; value: string; color?: string; tip?: React.ReactNode }) => (
    <Card className={cn(color)}>
      <CardContent className="p-3">
        <div className="flex items-center gap-1.5">
          <p className="text-xs text-muted-foreground">{label}</p>
          {tip && <InfoTip>{tip}</InfoTip>}
        </div>
        <p className="text-lg font-bold">{value}</p>
      </CardContent>
    </Card>
  );

  const TopCard = ({ label, value, delta, color, tip }: { label: string; value: string; delta: DeltaInfo; color: string; tip?: React.ReactNode }) => (
    <Card className={cn(color)}>
      <CardContent className="p-4">
        <div className="flex items-center gap-1.5">
          <p className="text-sm text-muted-foreground font-medium">{label}</p>
          {tip && <InfoTip>{tip}</InfoTip>}
        </div>
        <p className="text-2xl font-bold mt-1">{value}</p>
        {delta && delta.direction !== 'neutral' && (
          <div className={cn('flex items-center gap-1 text-xs mt-1', delta.direction === 'up' ? 'text-green-600' : 'text-destructive')}>
            {delta.direction === 'up' ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
            <span>{delta.direction === 'up' ? '▲' : '▼'} {delta.percent.toFixed(0)}% vs mês anterior</span>
          </div>
        )}
        {!delta && <p className="text-[10px] text-muted-foreground mt-1">— sem dado anterior pra comparar</p>}
      </CardContent>
    </Card>
  );

  if (loading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Métricas</h1>
        <div className="flex gap-2">
          <Select value={String(month)} onValueChange={v => setMonth(Number(v))}>
            <SelectTrigger className="w-24"><SelectValue /></SelectTrigger>
            <SelectContent>{Array.from({ length: 12 }, (_, i) => <SelectItem key={i} value={String(i + 1)}>Mês {i + 1}</SelectItem>)}</SelectContent>
          </Select>
          <Select value={String(year)} onValueChange={v => setYear(Number(v))}>
            <SelectTrigger className="w-20"><SelectValue /></SelectTrigger>
            <SelectContent>{[2024, 2025, 2026].map(y => <SelectItem key={y} value={String(y)}>{y}</SelectItem>)}</SelectContent>
          </Select>
        </div>
      </div>

      <Tabs defaultValue="visao" className="space-y-6">
        <TabsList className="grid grid-cols-3 w-full md:w-auto md:inline-flex">
          <TabsTrigger value="visao">📊 Visão Geral</TabsTrigger>
          <TabsTrigger value="financeiro">💰 Financeiro</TabsTrigger>
          <TabsTrigger value="operacional">📦 Operacional</TabsTrigger>
        </TabsList>

        {/* ========================= VISÃO GERAL ========================= */}
        <TabsContent value="visao" className="space-y-6">
          {/* Top 3 com delta */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <TopCard
              label="💰 Faturamento Total (Inclui Pendentes)"
              value={formatBRL(data.fatTotal)}
              delta={deltas.fat}
              color="bg-card border-l-4 border-l-primary"
              tip="Soma de pedidos pagos (por data do recebimento) + pendentes (por data de criação) do período. Exclui FREE."
            />
            <TopCard
              label="📦 Total de Produtos"
              value={String(data.prodTotalRealistico ?? data.prodTotal)}
              delta={deltas.prod}
              color="bg-card border-l-4 border-l-primary"
              tip="Unidades movimentadas no período: pagos + pendentes + FREE. Reflete operação real."
            />
            <TopCard
              label="💵 Lucro"
              value={formatBRL(data.lucro)}
              delta={deltas.lucro}
              color="bg-card border-l-4 border-l-primary"
              tip="Faturamento (com pendentes) − Custos do período."
            />
          </div>

          {/* Placeholder para Insights (Fase 4) */}
          <Card className="border-dashed">
            <CardContent className="p-6 text-center text-muted-foreground text-sm">
              💡 Insights e gráficos chegam nas próximas fases.
            </CardContent>
          </Card>
        </TabsContent>

        {/* ========================= FINANCEIRO ========================= */}
        <TabsContent value="financeiro" className="space-y-6">
          {/* Faturamento */}
          <div>
            <h2 className="font-bold mb-2" style={{ color: '#7B1FA2' }}>FATURAMENTO</h2>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              <MetricCard
                label="Fat. Total (Inclui Pendentes)"
                value={formatBRL(data.fatTotal)}
                color="bg-card border border-purple-200"
                tip="Soma de pedidos pagos (por data_pago) + pendentes (por data de criação)."
              />
              <Card className="bg-card border-2 border-purple-300">
                <CardContent className="p-3">
                  <div className="flex items-center gap-1.5">
                    <p className="text-xs text-muted-foreground">💳 Pendentes</p>
                    <InfoTip>Soma de pedidos pendentes (todos os períodos). Apenas visualização — já está incluso no Fat. Total acima.</InfoTip>
                  </div>
                  <p className="text-lg font-bold text-purple-700">{formatBRL(pendentesTotal)}</p>
                  <p className="text-[10px] text-muted-foreground">Global — independente do período</p>
                </CardContent>
              </Card>
              <MetricCard label="Fat. Base" value={formatBRL(data.fatBase)} color="bg-card border border-purple-200" tip="Soma valor de pedidos do canal BASE no período." />
              <MetricCard label="Fat. ADS" value={formatBRL(data.fatAds)} color="bg-card border border-purple-200" tip="Soma valor de pedidos do canal ADS no período." />
              <MetricCard label="Fat. Rep" value={formatBRL(data.fatRep)} color="bg-card border border-purple-200" tip="Soma valor de pedidos do canal REP no período." />
            </div>
          </div>

          {/* Custos */}
          <div>
            <h2 className="font-bold mb-2 text-destructive">CUSTOS</h2>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              <MetricCard label="Custo Total" value={formatBRL(data.custoTotal)} color="bg-card border-l-4 border-l-destructive" tip="Soma de todos os lançamentos tipo 'despesa' em Financeiro no período." />
              <MetricCard label="Custo ADS" value={formatBRL(data.custoAds)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'ads' em Financeiro." />
              <MetricCard label="Etiqueta Total" value={formatBRL(data.etiquetaTotal)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'etiqueta' em Financeiro." />
              <MetricCard label="Log Total" value={formatBRL(data.logTotal)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'logistica' em Financeiro." />
              <MetricCard label="Material Total" value={formatBRL(data.materialTotal)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'material' em Financeiro." />
            </div>
          </div>

          {/* Resultado */}
          <div>
            <h2 className="font-bold mb-2 text-primary">RESULTADO</h2>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
              <MetricCard label="Lucro" value={formatBRL(data.lucro)} color="bg-card border-l-4 border-l-primary" tip="Faturamento − Custo Total." />
              <MetricCard label="Margem" value={formatPercent(data.margem)} color="bg-card border-l-4 border-l-primary" tip="(Lucro ÷ Faturamento) × 100" />
              <MetricCard label="Med. Lucro Un. Base" value={formatBRL(data.medLucroBase)} color="bg-card border-l-4 border-l-primary" tip="(Fat. Base ÷ Prod. Base) − Custo Produto Un. − Custo Operacional Un." />
              <MetricCard label="Med. Lucro Un. ADS" value={formatBRL(data.medLucroAds)} color="bg-card border-l-4 border-l-primary" tip="(Fat. ADS ÷ Prod. ADS) − Custo Produto Un. − Custo Operacional Un. − CPA Un. ADS" />
              <MetricCard label="Med. Lucro Un. Rep" value={formatBRL(data.medLucroRep)} color="bg-card border-l-4 border-l-primary" tip="(Fat. Rep ÷ Prod. Rep) − Custo Produto Un. − Custo Operacional Un." />
              <MetricCard label="Med. Lucro Un. Geral" value={formatBRL(data.medLucroGeral)} color="bg-card border-l-4 border-l-primary" tip="Lucro ÷ Produtos (pagos + pendentes, exclui FREE)." />
            </div>
          </div>
        </TabsContent>

        {/* ========================= OPERACIONAL ========================= */}
        <TabsContent value="operacional" className="space-y-6">
          {/* Indicadores */}
          <div>
            <h2 className="font-bold mb-2 text-sf-gold">INDICADORES</h2>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              <MetricCard label="ICM" value={formatPercent(data.icm)} color="bg-card border-l-4 border-l-sf-gold" tip="Índice de Custo de Marketing: Custo ADS ÷ (Lucro + Custo ADS) × 100. Quanto menor, melhor." />
              <MetricCard label="CPA Un. ADS" value={formatBRL(data.cpaUnAds)} color="bg-card border-l-4 border-l-sf-gold" tip="Custo ADS por unidade vendida ADS: Custo ADS ÷ Unidades ADS." />
              <MetricCard label="CAC" value={formatBRL(data.cac)} color="bg-card border-l-4 border-l-sf-gold" tip="Custo de Aquisição por venda ADS: Custo ADS ÷ Nº de pedidos ADS." />
              <MetricCard label="Custo Operacional Un." value={formatBRL(data.custoOpUn)} color="bg-card border-l-4 border-l-sf-gold" tip="(Etiqueta + Logística) ÷ Total de unidades (inclui FREE)." />
              <MetricCard label="Custo Produto Un." value={formatBRL(data.custoProdUn)} color="bg-card border-l-4 border-l-sf-gold" tip="Material ÷ Total de unidades (inclui FREE)." />
            </div>
          </div>

          {/* Produtos */}
          <div>
            <h2 className="font-bold mb-2" style={{ color: '#1976D2' }}>PRODUTOS</h2>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              <MetricCard label="Total de Produtos" value={String(data.prodTotalRealistico ?? data.prodTotal)} color="bg-card border-l-4 border-l-blue-500" tip="Pagos + Pendentes + FREE. Reflete unidades efetivamente movimentadas." />
              <MetricCard label="Prod. ADS" value={String(data.prodAds)} color="bg-card border-l-4 border-l-blue-500" tip="Unidades em pedidos do canal ADS (pagos + pendentes)." />
              <MetricCard label="Prod. Base" value={String(data.prodBase)} color="bg-card border-l-4 border-l-blue-500" tip="Unidades em pedidos do canal BASE (pagos + pendentes)." />
              <MetricCard label="Prod. Rep" value={String(data.prodRep)} color="bg-card border-l-4 border-l-blue-500" tip="Unidades em pedidos do canal REP (pagos + pendentes)." />
              <MetricCard label="Prod. Free" value={String(data.prodFree ?? 0)} color="bg-card border-l-4 border-l-sky-500" tip="Unidades em pedidos FREE (brindes/reposições da Logística). Não afeta lucro." />
            </div>
          </div>

          {/* Placeholder para LTV / Taxa Recompra / DSO (Fase 2) */}
          <Card className="border-dashed">
            <CardContent className="p-6 text-center text-muted-foreground text-sm">
              📈 LTV, Taxa de Recompra e DSO chegam na próxima fase.
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}

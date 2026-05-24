import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { formatBRL, formatPercent } from '@/lib/format';
import { cn } from '@/lib/utils';

export default function MetricasPage() {
  const [loading, setLoading] = useState(true);
  const [month, setMonth] = useState(new Date().getMonth() + 1);
  const [year, setYear] = useState(new Date().getFullYear());
  const [data, setData] = useState<any>({});
  const [pendentesTotal, setPendentesTotal] = useState(0);

  useEffect(() => { fetchData(); fetchPendentes(); }, [month, year]);

  const fetchPendentes = async () => {
    // Exclui pedidos FREE (sem impacto financeiro)
    const { data } = await supabase.from('pedidos').select('valor, is_free').eq('status_pagamento', 'pendente').neq('is_free', true);
    setPendentesTotal(data?.reduce((s, p) => s + (Number(p.valor) || 0), 0) || 0);
  };

  const fetchData = async () => {
    setLoading(true);
    const start = `${year}-${String(month).padStart(2, '0')}-01`;
    const nextM = month === 12 ? 1 : month + 1;
    const nextY = month === 12 ? year + 1 : year;
    const end = `${nextY}-${String(nextM).padStart(2, '0')}-01`;

    // Faturamento/lucros/medidas: pedidos PAGOS, computados no dia do recebimento (data_pago).
    // Exclui FREE (canal a parte) — esses NUNCA afetam lucro/margem/medLucro por canal.
    const { data: pedAll } = await supabase.from('pedidos').select('*').eq('status_pagamento', 'pago').gte('data_pago', start).lt('data_pago', end);
    const ped = (pedAll || []).filter((p: any) => !p.is_free);

    // Produtos FREE do periodo (canal a parte) — entram so no total geral de produtos
    const { data: pedFree } = await supabase.from('pedidos').select('quantidade, data_pago')
      .eq('is_free', true).gte('data_pago', start).lt('data_pago', end);

    // Produtos PENDENTES do periodo (data de criacao, ja que data_pago e NULL)
    // Ja foram enviados, estoque ja consumido — entram no total geral
    const { data: pedPend } = await supabase.from('pedidos').select('quantidade, data')
      .eq('status_pagamento', 'pendente').neq('is_free', true).gte('data', start).lt('data', end);

    const { data: fin } = await supabase.from('financeiro').select('*').gte('data', start).lt('data', end);

    // Faturamento vem de pedidos (vendas)
    const receitas = (ped || []).filter(p => p.valor && Number(p.valor) > 0);
    // Despesas continuam vindo de financeiro
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

    // Produtos por canal: SO pagos non-FREE. Mantem todas as metricas de lucro intactas.
    const prodTotal = (ped || []).reduce((s, p) => s + (p.quantidade || 0), 0);
    const prodAds = (ped || []).filter(p => p.canal === 'ADS').reduce((s, p) => s + (p.quantidade || 0), 0);
    const prodBase = (ped || []).filter(p => p.canal === 'BASE').reduce((s, p) => s + (p.quantidade || 0), 0);
    const prodRep = (ped || []).filter(p => p.canal === 'REP').reduce((s, p) => s + (p.quantidade || 0), 0);

    // Produtos do canal FREE (brindes/reposicoes) — separado, NAO afeta lucro
    const prodFree = (pedFree || []).reduce((s, p) => s + (p.quantidade || 0), 0);
    // Produtos de pedidos pendentes (ja enviados, custos ja incorridos)
    const prodPendentes = (pedPend || []).reduce((s, p) => s + (p.quantidade || 0), 0);
    // Total realista: pagos + free + pendentes — visao operacional completa
    const prodTotalRealistico = prodTotal + prodFree + prodPendentes;

    const lucro = fatTotal - custoTotal;
    const margem = fatTotal > 0 ? (lucro / fatTotal) * 100 : 0;
    const icm = (lucro + custoAds) > 0 ? (custoAds / (lucro + custoAds)) * 100 : 0;
    const cpaUnAds = prodAds > 0 ? custoAds / prodAds : 0;
    const custoOpUn = prodTotal > 0 ? (etiquetaTotal + logTotal) / prodTotal : 0;
    const custoProdUn = prodTotal > 0 ? materialTotal / prodTotal : 0;

    const medLucroBase = prodBase > 0 ? (fatBase / prodBase) - custoProdUn - custoOpUn : 0;
    const medLucroAds = prodAds > 0 ? (fatAds / prodAds) - custoProdUn - custoOpUn - cpaUnAds : 0;
    const medLucroRep = prodRep > 0 ? (fatRep / prodRep) - custoProdUn - custoOpUn : 0;
    const medLucroGeral = prodTotal > 0 ? lucro / prodTotal : 0;

    setData({
      fatTotal, fatBase, fatAds, fatRep,
      custoTotal, custoAds, etiquetaTotal, logTotal, materialTotal,
      prodTotal, prodAds, prodBase, prodRep, prodFree, prodPendentes, prodTotalRealistico,
      lucro, margem, icm, cpaUnAds, custoOpUn, custoProdUn,
      medLucroBase, medLucroAds, medLucroRep, medLucroGeral,
    });
    setLoading(false);
  };

  const MetricCard = ({ label, value, color = 'bg-card' }: { label: string; value: string; color?: string }) => (
    <Card className={cn(color)}>
      <CardContent className="p-3">
        <p className="text-xs text-muted-foreground">{label}</p>
        <p className="text-lg font-bold">{value}</p>
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

      {/* Top 3 */}
      <div className="grid grid-cols-3 gap-4">
        <MetricCard label="💰 Faturamento Total" value={formatBRL(data.fatTotal)} color="bg-card border-l-4 border-l-primary" />
        <MetricCard label="📦 Total de Produtos" value={String(data.prodTotalRealistico ?? data.prodTotal)} color="bg-card border-l-4 border-l-primary" />
        <MetricCard label="💵 Lucro" value={formatBRL(data.lucro)} color="bg-card border-l-4 border-l-primary" />
      </div>

      {/* Métricas */}
      <div>
        <h2 className="font-bold mb-2 text-sf-gold">MÉTRICAS</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <MetricCard label="ICM" value={formatPercent(data.icm)} color="bg-card border-l-4 border-l-sf-gold" />
          <MetricCard label="CPA Un. ADS" value={formatBRL(data.cpaUnAds)} color="bg-card border-l-4 border-l-sf-gold" />
          <MetricCard label="Custo Operacional Un." value={formatBRL(data.custoOpUn)} color="bg-card border-l-4 border-l-sf-gold" />
          <MetricCard label="Custo Produto Un." value={formatBRL(data.custoProdUn)} color="bg-card border-l-4 border-l-sf-gold" />
        </div>
      </div>

      {/* Custos */}
      <div>
        <h2 className="font-bold mb-2 text-destructive">CUSTOS</h2>
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
          <MetricCard label="Custo Total" value={formatBRL(data.custoTotal)} color="bg-card border-l-4 border-l-destructive" />
          <MetricCard label="Custo ADS" value={formatBRL(data.custoAds)} color="bg-card border-l-4 border-l-destructive" />
          <MetricCard label="Etiqueta Total" value={formatBRL(data.etiquetaTotal)} color="bg-card border-l-4 border-l-destructive" />
          <MetricCard label="Log Total" value={formatBRL(data.logTotal)} color="bg-card border-l-4 border-l-destructive" />
          <MetricCard label="Material Total" value={formatBRL(data.materialTotal)} color="bg-card border-l-4 border-l-destructive" />
        </div>
      </div>

      {/* Faturamento */}
      <div>
        <h2 className="font-bold mb-2" style={{ color: '#7B1FA2' }}>FATURAMENTO</h2>
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
          <MetricCard label="Fat. Total" value={formatBRL(data.fatTotal)} color="bg-card border border-purple-200" />
          <Card className="bg-card border-2 border-purple-300">
            <CardContent className="p-3">
              <p className="text-xs text-muted-foreground">💳 Pendentes</p>
              <p className="text-lg font-bold text-purple-700">{formatBRL(pendentesTotal)}</p>
              <p className="text-[10px] text-muted-foreground">Global — independente do período</p>
            </CardContent>
          </Card>
          <MetricCard label="Fat. Base" value={formatBRL(data.fatBase)} color="bg-card border border-purple-200" />
          <MetricCard label="Fat. ADS" value={formatBRL(data.fatAds)} color="bg-card border border-purple-200" />
          <MetricCard label="Fat. Rep" value={formatBRL(data.fatRep)} color="bg-card border border-purple-200" />
        </div>
      </div>

      {/* Resultado */}
      <div>
        <h2 className="font-bold mb-2 text-primary">RESULTADO</h2>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
          <MetricCard label="Lucro" value={formatBRL(data.lucro)} color="bg-card border-l-4 border-l-primary" />
          <MetricCard label="Margem" value={formatPercent(data.margem)} color="bg-card border-l-4 border-l-primary" />
          <MetricCard label="Med. Lucro Un. Base" value={formatBRL(data.medLucroBase)} color="bg-card border-l-4 border-l-primary" />
          <MetricCard label="Med. Lucro Un. ADS" value={formatBRL(data.medLucroAds)} color="bg-card border-l-4 border-l-primary" />
          <MetricCard label="Med. Lucro Un. Rep" value={formatBRL(data.medLucroRep)} color="bg-card border-l-4 border-l-primary" />
          <MetricCard label="Med. Lucro Un. Geral" value={formatBRL(data.medLucroGeral)} color="bg-card border-l-4 border-l-primary" />
        </div>
      </div>

      {/* Produtos */}
      <div>
        <h2 className="font-bold mb-2" style={{ color: '#1976D2' }}>PRODUTOS</h2>
        <div className="grid grid-cols-2 md:grid-cols-6 gap-3">
          <MetricCard label="Total de Produtos" value={String(data.prodTotalRealistico ?? data.prodTotal)} color="bg-card border-l-4 border-l-blue-500" />
          <MetricCard label="Prod. ADS" value={String(data.prodAds)} color="bg-card border-l-4 border-l-blue-500" />
          <MetricCard label="Prod. Base" value={String(data.prodBase)} color="bg-card border-l-4 border-l-blue-500" />
          <MetricCard label="Prod. Rep" value={String(data.prodRep)} color="bg-card border-l-4 border-l-blue-500" />
          <MetricCard label="Prod. Pendentes" value={String(data.prodPendentes ?? 0)} color="bg-card border-l-4 border-l-amber-500" />
          <MetricCard label="Prod. Free" value={String(data.prodFree ?? 0)} color="bg-card border-l-4 border-l-sky-500" />
        </div>
      </div>
    </div>
  );
}

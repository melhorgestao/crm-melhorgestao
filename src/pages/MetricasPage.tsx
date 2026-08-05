import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { CANAL_HEX } from '@/lib/canal';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { ExternalLink, ArrowRight } from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { ChartContainer, ChartTooltip } from '@/components/ui/chart';
import { PieChart, Pie, Cell, LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, AreaChart, Area } from 'recharts';
import { Info, TrendingUp, TrendingDown, ChevronDown, ChevronUp } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { formatBRL, formatPercent } from '@/lib/format';
import { cn } from '@/lib/utils';

// Canal: cores canônicas (mesmas em Dashboard/Pedidos). Demais categorias locais.
const COLORS = {
  ADS: CANAL_HEX.ADS,   // azul
  BASE: CANAL_HEX.BASE, // laranja
  REP: CANAL_HEX.REP,   // verde-água
  FREE: '#0ea5e9',     // sky
  ETIQUETA: '#ef4444', // red
  LOGISTICA: '#dc2626',// red darker
  MATERIAL: '#f59e0b', // amber
} as const;

// Limiares dos insights automaticos — ajustar aqui muda comportamento global
const INSIGHT_THRESHOLDS = {
  icm_alerta: 20,           // % — ICM acima disso = atencao
  margem_alerta: 30,        // % — margem abaixo disso = atencao
  margem_excelente: 50,     // % — acima disso = destaque positivo
  variacao_minima: 5,       // % — Delta abaixo disso e ignorado
  variacao_critica: 25,     // % — Delta acima disso ganha prioridade
  pendentes_atencao: 1000,  // R$ — pendentes acima disso entram em insight
  taxa_recompra_baixa: 30,  // %
  taxa_recompra_otima: 60,  // %
  roi_excelente: 3,         // 1 ADS gera 3+ em receita
  roi_baixo: 1,             // ROI abaixo de 1 = prejuizo
};

type Insight = { id: string; emoji: string; title: string; description?: string; priority: number; tone: 'positive' | 'negative' | 'warning' | 'info' };

type DeltaInfo = { percent: number; direction: 'up' | 'down' | 'neutral' } | null;

export default function MetricasPage() {
  const [loading, setLoading] = useState(true);
  const [month, setMonth] = useState(new Date().getMonth() + 1);
  const [year, setYear] = useState(new Date().getFullYear());
  const [data, setData] = useState<any>({});
  // Custo/Lucro por grupo de produto
  type GrupoLinha = {
    grupo_id: string | null; nome: string; cor: string | null;
    receita: number; material: number; unidades: number;
    // rateio dos compartilhados detalhado (por receita)
    adsComp: number; etiquetaComp: number; logComp: number; influencerComp: number; infraComp: number;
    compartilhado: number; lucro: number;
    fracao: number;
  };
  const [perGrupo, setPerGrupo] = useState<GrupoLinha[]>([]);
  const [selectedGrupo, setSelectedGrupo] = useState<string>('todos'); // 'todos' | grupo_id | 'sem'
  // unidades por grupo (aba Operacional): grupo_id||'sem' → {ads,base,rep,free}
  type UnidGrp = { ads: number; base: number; rep: number; free: number };
  const [unidGrupo, setUnidGrupo] = useState<Map<string, UnidGrp>>(new Map());
  const [pendentesTotal, setPendentesTotal] = useState(0);
  const [deltas, setDeltas] = useState<{ fat: DeltaInfo; prod: DeltaInfo; lucro: DeltaInfo }>({ fat: null, prod: null, lucro: null });
  const [recompraMetrics, setRecompraMetrics] = useState<{
    ltvGeral: number; ltvBase: number; ltvRep: number;
    taxaRecompraPeriodo: number; taxaRecompraHistorica: number;
    tempoMedioRecompra: number;
    contatosBase: number; contatosRep: number; contatosTotal: number;
  } | null>(null);
  const [monthlyData, setMonthlyData] = useState<Array<{ mes: string; total: number; base: number; ads: number; rep: number }>>([]);
  const [detail, setDetail] = useState<
    | { type: 'formula'; title: string; body: React.ReactNode }
    | { type: 'pedidos'; title: string; filter: { canal?: string; isFreeOnly?: boolean; isPendente?: boolean; isPagoOnly?: boolean } }
    | { type: 'recebimentos'; title: string; filter: { canal?: string } }
    | { type: 'lancamentos'; title: string; categoria?: string; grupoId?: string | null }
    | null
  >(null);
  const navigate = useNavigate();
  const [insightsExpanded, setInsightsExpanded] = useState<boolean>(() => {
    if (typeof window === 'undefined') return true;
    return localStorage.getItem('metricas_insights_hidden') !== '1';
  });

  const toggleInsights = () => {
    setInsightsExpanded(v => {
      const next = !v;
      try { localStorage.setItem('metricas_insights_hidden', next ? '0' : '1'); } catch {}
      return next;
    });
  };

  useEffect(() => { fetchData(); fetchPendentes(); fetchRecompraMetrics(); fetchMonthlyData(); }, [month, year]);

  // Dados mensais (linha 12 meses + barra empilhada): faturamento por canal × mês.
  // Atribui ao mes de CRIACAO (data) - alinha com Pedidos>Lista e Fat. Total.
  const fetchMonthlyData = async () => {
    const yearStart = `${year}-01-01`;
    const yearEnd = `${year + 1}-01-01`;
    const { data } = await supabase.from('pedidos')
      .select('data, valor, valor_original, desconto_total, canal, status_pagamento, is_free')
      .neq('is_free', true)
      .in('status_pagamento', ['pago', 'pendente'])
      .gte('data', yearStart).lt('data', yearEnd);

    const meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    const agg = meses.map(m => ({ mes: m, total: 0, base: 0, ads: 0, rep: 0 }));

    (data || []).forEach((p: any) => {
      if (!p.data) return;
      const m = new Date(`${p.data}T00:00:00`).getMonth();
      const v = (Number(p.valor_original ?? p.valor) || 0) - (Number(p.desconto_total) || 0);
      agg[m].total += v;
      if (p.canal === 'BASE') agg[m].base += v;
      else if (p.canal === 'ADS') agg[m].ads += v;
      else if (p.canal === 'REP' || p.canal === 'C-REP') agg[m].rep += v;
    });
    setMonthlyData(agg);
  };

  // Motor de insights: gera lista priorizada a partir dos dados atuais.
  // Cada regra cria 0..N insights. Score final ordena.
  const generateInsights = (): Insight[] => {
    const out: Insight[] = [];
    if (!data || Object.keys(data).length === 0) return out;
    const T = INSIGHT_THRESHOLDS;

    // 1. Delta de Faturamento / Lucro / Produtos (vs mes anterior)
    if (deltas.fat && deltas.fat.direction !== 'neutral' && deltas.fat.percent >= T.variacao_minima) {
      const isUp = deltas.fat.direction === 'up';
      out.push({
        id: 'fat_delta',
        emoji: isUp ? '📈' : '📉',
        title: `Faturamento ${isUp ? 'cresceu' : 'caiu'} ${deltas.fat.percent.toFixed(0)}%`,
        description: 'vs mês anterior (mesmo período)',
        priority: isUp ? 5 : 8,
        tone: isUp ? 'positive' : 'negative',
      });
    }
    if (deltas.lucro && deltas.lucro.direction !== 'neutral' && deltas.lucro.percent >= T.variacao_minima) {
      const isUp = deltas.lucro.direction === 'up';
      out.push({
        id: 'lucro_delta',
        emoji: isUp ? '💎' : '💔',
        title: `Lucro ${isUp ? 'subiu' : 'caiu'} ${deltas.lucro.percent.toFixed(0)}%`,
        description: 'vs mês anterior',
        priority: isUp ? 6 : 9,
        tone: isUp ? 'positive' : 'negative',
      });
    }

    // 2. Alertas de eficiencia / margem
    if (data.icm > T.icm_alerta) {
      out.push({
        id: 'icm_alerta',
        emoji: '⚠️',
        title: `ICM em ${data.icm.toFixed(1)}%`,
        description: `Limite saudável: < ${T.icm_alerta}%`,
        priority: 10,
        tone: 'warning',
      });
    }
    if (data.margem > 0 && data.margem < T.margem_alerta && data.fatTotal > 0) {
      out.push({
        id: 'margem_baixa',
        emoji: '⚠️',
        title: `Margem em ${data.margem.toFixed(1)}%`,
        description: `Abaixo do alvo (${T.margem_alerta}%)`,
        priority: 9,
        tone: 'warning',
      });
    } else if (data.margem >= T.margem_excelente) {
      out.push({
        id: 'margem_excelente',
        emoji: '💎',
        title: `Margem excelente: ${data.margem.toFixed(1)}%`,
        description: `Acima de ${T.margem_excelente}%`,
        priority: 6,
        tone: 'positive',
      });
    }

    // 3. Canal dominante do mes
    const fatBase = data.fatBase || 0, fatAds = data.fatAds || 0, fatRep = data.fatRep || 0;
    const totalCanais = fatBase + fatAds + fatRep;
    if (totalCanais > 0) {
      const winner = [['BASE', fatBase], ['ADS', fatAds], ['REP', fatRep]].sort((a, b) => (b[1] as number) - (a[1] as number))[0];
      const pct = (winner[1] as number) / totalCanais * 100;
      if (pct >= 40) {
        out.push({
          id: 'canal_dominante',
          emoji: '🥇',
          title: `${winner[0]} foi seu maior canal`,
          description: `${pct.toFixed(0)}% do faturamento`,
          priority: 4,
          tone: 'info',
        });
      }
      if (fatRep > 0 && totalCanais > 0) {
        const pctRep = (fatRep / totalCanais) * 100;
        if (pctRep >= 20) {
          out.push({
            id: 'rep_destaque',
            emoji: '👥',
            title: `Representantes geraram ${pctRep.toFixed(0)}%`,
            description: 'do faturamento total',
            priority: 4,
            tone: 'info',
          });
        }
      }
    }

    // 4. Eficiencia ADS (ROI: receita ADS / custo ADS)
    if (data.custoAds > 0) {
      const roi = (data.fatAds || 0) / data.custoAds;
      if (roi >= T.roi_excelente) {
        out.push({
          id: 'roi_top',
          emoji: '🎯',
          title: `ROI ADS: ${roi.toFixed(1)}x`,
          description: `R$ 1 em ads → R$ ${roi.toFixed(2)} em receita`,
          priority: 7,
          tone: 'positive',
        });
      } else if (roi < T.roi_baixo) {
        out.push({
          id: 'roi_baixo',
          emoji: '🔥',
          title: `ROI ADS em ${roi.toFixed(2)}x`,
          description: 'Custo ADS supera receita ADS',
          priority: 10,
          tone: 'negative',
        });
      }
    }

    // 5. Recordes mensais (vs ultimos 11 meses)
    if (monthlyData.length === 12) {
      const currentMonthIdx = month - 1;
      const currentVal = monthlyData[currentMonthIdx]?.total || 0;
      if (currentVal > 0) {
        const otherMonths = monthlyData.filter((_, i) => i !== currentMonthIdx).map(m => m.total);
        const maxOthers = Math.max(...otherMonths, 0);
        if (currentVal > maxOthers && currentVal > 0) {
          out.push({
            id: 'recorde_mes',
            emoji: '🏆',
            title: 'Melhor mês do ano em faturamento!',
            description: `${formatBRL(currentVal)} — recorde de ${year}`,
            priority: 8,
            tone: 'positive',
          });
        }
      }
    }

    // 6. Pendentes (independente do periodo)
    if (pendentesTotal >= T.pendentes_atencao) {
      out.push({
        id: 'pendentes',
        emoji: '⏰',
        title: `${formatBRL(pendentesTotal)} em pendentes`,
        description: 'Atenção a recebimentos atrasados',
        priority: 6,
        tone: 'warning',
      });
    }

    // 7. Taxa de recompra (historica)
    if (recompraMetrics) {
      const tx = recompraMetrics.taxaRecompraHistorica;
      if (tx >= T.taxa_recompra_otima) {
        out.push({
          id: 'recompra_alta',
          emoji: '💚',
          title: `Recompra histórica em ${tx.toFixed(0)}%`,
          description: 'Excelente retenção de clientes',
          priority: 5,
          tone: 'positive',
        });
      } else if (tx > 0 && tx < T.taxa_recompra_baixa) {
        out.push({
          id: 'recompra_baixa',
          emoji: '⚠️',
          title: `Recompra histórica em ${tx.toFixed(0)}%`,
          description: 'Oportunidade de melhorar fidelização',
          priority: 7,
          tone: 'warning',
        });
      }
    }

    // 8. Med. Lucro Un. ADS negativa
    if (data.medLucroAds !== undefined && data.medLucroAds < 0 && data.prodAds > 0) {
      out.push({
        id: 'lucro_ads_neg',
        emoji: '🚨',
        title: 'Lucro Un. ADS negativo',
        description: `Você está pagando ${formatBRL(Math.abs(data.medLucroAds))} por unidade ADS`,
        priority: 11,
        tone: 'negative',
      });
    }

    // 9. ADS sem custo (gastou 0 mas vendeu pelo canal)
    if (data.custoAds === 0 && data.fatAds > 0) {
      out.push({
        id: 'ads_sem_custo',
        emoji: '🆓',
        title: `${formatBRL(data.fatAds)} em vendas ADS sem custo`,
        description: 'Confira se há lançamentos de ADS faltando',
        priority: 3,
        tone: 'info',
      });
    }

    return out.sort((a, b) => b.priority - a.priority).slice(0, 5);
  };

  const fetchPendentes = async () => {
    // Exclui pedidos FREE (sem impacto financeiro)
    const { data } = await supabase.from('pedidos').select('valor, is_free').eq('status_pagamento', 'pendente').neq('is_free', true);
    setPendentesTotal(data?.reduce((s, p) => s + (Number(p.valor) || 0), 0) || 0);
  };

  // LTV / Recompra / Tempo Médio — todas baseadas em comportamento REAL
  // (não em canal). Excluem FREE. Para taxas e tempo: excluem REP/C-REP.
  const fetchRecompraMetrics = async () => {
    const start = `${year}-${String(month).padStart(2, '0')}-01`;
    const nextM = month === 12 ? 1 : month + 1;
    const nextY = month === 12 ? year + 1 : year;
    const end = `${nextY}-${String(nextM).padStart(2, '0')}-01`;

    // Busca TODOS os pedidos pagos non-FREE com canal_origem do contato.
    // Pesado? Não — historico total da Santa Flor é pequeno.
    const { data: allPaid } = await supabase
      .from('pedidos')
      .select('contato_id, data, data_pago, valor, valor_original, desconto_total, contatos(canal_origem)')
      .eq('status_pagamento', 'pago')
      .neq('is_free', true)
      .not('contato_id', 'is', null)
      .order('data_pago', { ascending: true });

    if (!allPaid) return;

    // Agrupa por contato_id
    type ContatoStats = { pedidos: Array<{ data_pago: string; data_venda: string; valor_real: number }>; canal_origem: string | null };
    const byContato = new Map<string, ContatoStats>();
    (allPaid as any[]).forEach(p => {
      if (!p.contato_id || !p.data_pago) return;
      const valorReal = (Number(p.valor_original ?? p.valor) || 0) - (Number(p.desconto_total) || 0);
      const canal = p.contatos?.canal_origem || null;
      if (!byContato.has(p.contato_id)) byContato.set(p.contato_id, { pedidos: [], canal_origem: canal });
      byContato.get(p.contato_id)!.pedidos.push({ data_pago: p.data_pago, data_venda: p.data || p.data_pago, valor_real: valorReal });
    });

    const isDireto = (canal: string | null) => canal !== 'REP' && canal !== 'C-REP';

    // LTV Geral: avg(soma_revenue por contato) — todos os contatos com 1+ pedido pago
    const all = [...byContato.values()];
    const totalAll = all.reduce((s, c) => s + c.pedidos.reduce((ss, p) => ss + p.valor_real, 0), 0);
    const ltvGeral = all.length > 0 ? totalAll / all.length : 0;

    // LTV BASE
    const base = all.filter(c => c.canal_origem === 'BASE');
    const totalBase = base.reduce((s, c) => s + c.pedidos.reduce((ss, p) => ss + p.valor_real, 0), 0);
    const ltvBase = base.length > 0 ? totalBase / base.length : 0;

    // LTV REP (inclui C-REP)
    const rep = all.filter(c => c.canal_origem === 'REP' || c.canal_origem === 'C-REP');
    const totalRep = rep.reduce((s, c) => s + c.pedidos.reduce((ss, p) => ss + p.valor_real, 0), 0);
    const ltvRep = rep.length > 0 ? totalRep / rep.length : 0;

    // Clientes diretos (ADS + BASE — exclui REP/C-REP)
    const diretos: ContatoStats[] = [];
    const diretosMap: Array<{ id: string; stats: ContatoStats }> = [];
    byContato.forEach((stats, id) => {
      if (isDireto(stats.canal_origem)) {
        diretos.push(stats);
        diretosMap.push({ id, stats });
      }
    });

    // Taxa de Recompra Histórica: % de clientes diretos com 2+ pedidos pagos
    const comRecompra = diretos.filter(c => c.pedidos.length >= 2).length;
    const taxaRecompraHistorica = diretos.length > 0 ? (comRecompra / diretos.length) * 100 : 0;

    // Tempo Médio de Recompra: avg gaps entre pedidos consecutivos (todos clientes diretos 2+)
    let totalGaps = 0;
    let gapCount = 0;
    diretos.forEach(c => {
      if (c.pedidos.length < 2) return;
      for (let i = 1; i < c.pedidos.length; i++) {
        const d1 = new Date(c.pedidos[i - 1].data_pago);
        const d2 = new Date(c.pedidos[i].data_pago);
        const diffDays = Math.round((d2.getTime() - d1.getTime()) / 86400000);
        if (diffDays >= 0) { totalGaps += diffDays; gapCount += 1; }
      }
    });
    const tempoMedioRecompra = gapCount > 0 ? totalGaps / gapCount : 0;

    // Taxa de Recompra do Período: % dos clientes que fizeram uma VENDA no período
    // e que já eram clientes antes. Usa data da venda (não data_pago) — assim
    // pendências antigas quitadas agora não contam como "cliente do período".
    const contatosPeriodo = new Set<string>();
    const contatosComCompraAnterior = new Set<string>();
    diretosMap.forEach(({ id, stats }) => {
      const fezNoPeriodo = stats.pedidos.some(p => p.data_venda >= start && p.data_venda < end);
      if (!fezNoPeriodo) return;
      contatosPeriodo.add(id);
      const tinhaCompraAntes = stats.pedidos.some(p => p.data_venda < start);
      if (tinhaCompraAntes) contatosComCompraAnterior.add(id);
    });
    const taxaRecompraPeriodo = contatosPeriodo.size > 0
      ? (contatosComCompraAnterior.size / contatosPeriodo.size) * 100
      : 0;

    setRecompraMetrics({
      ltvGeral, ltvBase, ltvRep,
      taxaRecompraPeriodo, taxaRecompraHistorica,
      tempoMedioRecompra,
      contatosBase: base.length, contatosRep: rep.length, contatosTotal: all.length,
    });
  };

  // Calcula soma agregada (faturamento, produtos non-free, lucro) num range arbitrario.
  // Reusa a mesma logica de pagos+pendentes (non-free) e financeiro do periodo.
  const computeRangeMetrics = async (startISO: string, endISO: string) => {
    const [{ data: pedAll }, { data: fin }] = await Promise.all([
      supabase.from('pedidos').select('valor, valor_original, desconto_total, quantidade, canal')
        .neq('is_free', true)
        .in('status_pagamento', ['pago', 'pendente'])
        .gte('data', startISO).lt('data', endISO),
      supabase.from('financeiro').select('tipo, valor').gte('data', startISO).lt('data', endISO),
    ]);
    const ped = pedAll || [];
    // valor real da venda: valor_original − desconto (alinha com Pedidos > Lista)
    const fat = ped.reduce((s, p: any) => s + ((Number(p.valor_original ?? p.valor) || 0) - (Number(p.desconto_total) || 0)), 0);
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

    // Faturamento agora atribui pedidos ao MES DE CRIACAO (data), independente
    // de quando foi pago. Pedido criado em maio sempre conta em maio Fat. Total
    // — mesmo se for pago em junho. Historico estavel, nao muda com status.
    const { data: pedAll } = await supabase.from('pedidos').select('*')
      .neq('is_free', true)
      .in('status_pagamento', ['pago', 'pendente'])
      .gte('data', start).lt('data', end);

    // FREE do periodo (canal a parte — usa data_pago por convencao)
    const { data: pedFree } = await supabase.from('pedidos').select('quantidade, data_pago')
      .eq('is_free', true).gte('data_pago', start).lt('data_pago', end);

    const ped = pedAll || [];

    const { data: fin } = await supabase.from('financeiro').select('*').gte('data', start).lt('data', end);

    // Valor real da venda (faturamento bruto): valor_original − desconto_total.
    // Usar pedidos.valor estaria errado para pedidos com parcela paga (refletiria
    // o saldo restante e não o valor da venda). Alinha com Pedidos > Lista.
    const vendaReal = (p: any) => (Number(p.valor_original ?? p.valor) || 0) - (Number(p.desconto_total) || 0);

    const receitas = (ped || []).filter(p => vendaReal(p) > 0);
    const despesas = (fin || []).filter(f => f.tipo === 'despesa');

    const fatTotal = receitas.reduce((s, r) => s + vendaReal(r), 0);
    const fatBase = receitas.filter(r => r.canal === 'BASE').reduce((s, r) => s + vendaReal(r), 0);
    const fatAds = receitas.filter(r => r.canal === 'ADS').reduce((s, r) => s + vendaReal(r), 0);
    const fatRep = receitas.filter(r => r.canal === 'REP').reduce((s, r) => s + vendaReal(r), 0);

    const custoTotal = despesas.reduce((s, d) => s + Number(d.valor), 0);
    const custoAds = despesas.filter(d => d.categoria === 'ads').reduce((s, d) => s + Number(d.valor), 0);
    const etiquetaTotal = despesas.filter(d => d.categoria === 'etiqueta').reduce((s, d) => s + Number(d.valor), 0);
    const logTotal = despesas.filter(d => d.categoria === 'logistica').reduce((s, d) => s + Number(d.valor), 0);
    const materialTotal = despesas.filter(d => d.categoria === 'material').reduce((s, d) => s + Number(d.valor), 0);
    const influencerTotal = despesas.filter(d => d.categoria === 'influencer').reduce((s, d) => s + Number(d.valor), 0);
    const infraestruturaTotal = despesas.filter(d => d.categoria === 'infraestrutura').reduce((s, d) => s + Number(d.valor), 0);

    // ---------- CAIXA REAL DO MÊS ----------
    // Soma TUDO que entrou efetivamente no caixa neste mês, independente
    // de quando o pedido foi criado:
    //   - VENDA à vista (criada e paga no mês)
    //   - PARCELA_VENDA (parcela paga no mês, mesmo se o pedido é antigo)
    // Fonte: lancamentos_socios.data (data do recebimento).
    // Status_pagamento='pago' garante que é dinheiro confirmado.
    const { data: receb } = await supabase.from('lancamentos_socios')
      .select('valor, tipo, canal')
      .in('tipo', ['VENDA', 'PARCELA_VENDA'])
      .eq('status_pagamento', 'pago')
      .gte('data', start).lt('data', end);
    const caixaTotal = (receb || []).reduce((s, r) => s + (Number(r.valor) || 0), 0);
    const caixaBase  = (receb || []).filter(r => r.canal === 'BASE').reduce((s, r) => s + (Number(r.valor) || 0), 0);
    const caixaAds   = (receb || []).filter(r => r.canal === 'ADS' ).reduce((s, r) => s + (Number(r.valor) || 0), 0);
    const caixaRep   = (receb || []).filter(r => r.canal === 'REP' ).reduce((s, r) => s + (Number(r.valor) || 0), 0);

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
      caixaTotal, caixaBase, caixaAds, caixaRep,
      custoTotal, custoAds, etiquetaTotal, logTotal, materialTotal, influencerTotal, infraestruturaTotal,
      prodTotal, prodAds, prodBase, prodRep, prodFree, prodTotalRealistico, pedidosAds,
      lucro, margem, icm, cpaUnAds, cac, custoOpUn, custoProdUn,
      medLucroBase, medLucroAds, medLucroRep, medLucroGeral,
    });
    setLoading(false);

    // ---------- CUSTO E LUCRO POR GRUPO ----------
    // Material é direto por grupo (financeiro.grupo_id). ADS/etiqueta/log/
    // influencer/infra são COMPARTILHADOS e rateados por RECEITA. Assim
    // Σ lucro_grupo = lucro_total (rateio proporcional, sem inflar).
    (async () => {
      try {
        const { data: recGrp } = await supabase.rpc('receita_por_grupo', { p_inicio: start, p_fim: end });
        const linhasReceita = (recGrp || []) as Array<{ grupo_id: string | null; grupo_nome: string; receita: number; unidades: number }>;

        // material por grupo: COM grupo_id → direto pro grupo; SEM grupo_id
        // ("ambos"/geral, ex: caixa/fita) → compartilhado, rateado por receita.
        const matPorGrupo = new Map<string, number>();
        let materialGeralTotal = 0;
        despesas.filter(d => d.categoria === 'material').forEach((d: any) => {
          if (d.grupo_id) matPorGrupo.set(d.grupo_id, (matPorGrupo.get(d.grupo_id) || 0) + Number(d.valor));
          else materialGeralTotal += Number(d.valor);
        });

        const chaves = new Set<string>();
        const nomePorChave = new Map<string, string>();
        const corPorChave = new Map<string, string | null>();
        // Semeia TODOS os grupos cadastrados — mesmo sem receita/material no
        // período aparecem (zerados). Assim novos grupos entram automaticamente.
        const { data: gAll } = await supabase.from('produtos_grupos').select('id, nome, cor_grupo').order('ordem');
        (gAll || []).forEach((g: any) => { chaves.add(g.id); nomePorChave.set(g.id, g.nome); corPorChave.set(g.id, g.cor_grupo || null); });
        // grupos com receita/material (cobre o bucket "Sem grupo" também)
        linhasReceita.forEach(r => { const k = r.grupo_id || 'sem'; chaves.add(k); nomePorChave.set(k, r.grupo_nome || 'Sem grupo'); });
        matPorGrupo.forEach((_v, k) => { chaves.add(k); if (!nomePorChave.has(k)) nomePorChave.set(k, k === 'sem' ? 'Sem grupo' : 'Grupo'); });

        const receitaPorChave = new Map<string, number>();
        const unidadesPorChave = new Map<string, number>();
        linhasReceita.forEach(r => {
          const k = r.grupo_id || 'sem';
          receitaPorChave.set(k, (receitaPorChave.get(k) || 0) + Number(r.receita));
          unidadesPorChave.set(k, (unidadesPorChave.get(k) || 0) + Number(r.unidades));
        });

        const receitaBase = fatTotal > 0 ? fatTotal : 0;
        const unidadesTotal = Array.from(unidadesPorChave.values()).reduce((s, v) => s + v, 0);

        // Material geral ("ambos"): dividido IGUALMENTE entre os grupos reais e
        // somado ao Material de cada um (não é card de rateio). "Sem grupo" não recebe.
        const numRealGrupos = Array.from(chaves).filter(k => k !== 'sem').length;
        const materialGeralPorGrupo = numRealGrupos > 0 ? materialGeralTotal / numRealGrupos : 0;

        const linhas: GrupoLinha[] = Array.from(chaves).map(k => {
          const receita = receitaPorChave.get(k) || 0;
          const material = (matPorGrupo.get(k) || 0) + (k === 'sem' ? 0 : materialGeralPorGrupo);
          const unidades = unidadesPorChave.get(k) || 0;
          // rateio dos compartilhados: por receita; se não há receita no período,
          // rateia por unidades; se nem isso, fica 0 (fica no total, não alocado).
          const fracao = receitaBase > 0 ? receita / receitaBase
            : unidadesTotal > 0 ? unidades / unidadesTotal
            : 0;
          const adsComp = custoAds * fracao;
          const etiquetaComp = etiquetaTotal * fracao;
          const logComp = logTotal * fracao;
          const influencerComp = influencerTotal * fracao;
          const infraComp = infraestruturaTotal * fracao;
          const compartilhado = adsComp + etiquetaComp + logComp + influencerComp + infraComp;
          return {
            grupo_id: k === 'sem' ? null : k,
            nome: nomePorChave.get(k) || 'Sem grupo',
            cor: corPorChave.get(k) ?? null,
            receita, material, unidades, fracao,
            adsComp, etiquetaComp, logComp, influencerComp, infraComp,
            compartilhado,
            lucro: receita - material - compartilhado,
          };
          // ordena por maior atividade: receita, e como desempate o gasto
          // (material + rateio) — grupo mais relevante no topo.
        }).sort((a, b) => (b.receita - a.receita) || ((b.material + b.compartilhado) - (a.material + a.compartilhado)));

        setPerGrupo(linhas);
      } catch (e) {
        console.error('perGrupo erro:', e);
        setPerGrupo([]);
      }

      // unidades por grupo × canal × free (aba Operacional)
      try {
        const { data: u } = await supabase.rpc('unidades_por_grupo', { p_inicio: start, p_fim: end });
        const m = new Map<string, UnidGrp>();
        ((u || []) as any[]).forEach(r => {
          m.set(r.grupo_id || 'sem', {
            ads: Number(r.ads) || 0, base: Number(r.base) || 0,
            rep: Number(r.rep) || 0, free: Number(r.free) || 0,
          });
        });
        setUnidGrupo(m);
      } catch (e) {
        console.error('unidadesPorGrupo erro:', e);
        setUnidGrupo(new Map());
      }
    })();

    // Delta% em background — nao bloqueia render
    fetchDeltas(start, end).catch(console.error);
  };

  // ---------- Drill-down: formula display ----------
  const FormulaRow = ({ label, value, isResult }: { label: string; value: string; isResult?: boolean }) => (
    <div className={cn('flex justify-between items-center text-sm py-1.5', isResult && 'pt-2 mt-1 border-t font-bold text-base')}>
      <span className={cn('text-muted-foreground', isResult && 'text-foreground')}>{label}</span>
      <span className={cn('font-medium', isResult && 'text-primary')}>{value}</span>
    </div>
  );

  // ---------- Drill-down: lista de pedidos ----------
  const PedidosDetail = ({ filter }: { filter: { canal?: string; isFreeOnly?: boolean; isPendente?: boolean; isPagoOnly?: boolean } }) => {
    const [rows, setRows] = useState<any[] | null>(null);
    useEffect(() => {
      const start = `${year}-${String(month).padStart(2, '0')}-01`;
      const nextM = month === 12 ? 1 : month + 1;
      const nextY = month === 12 ? year + 1 : year;
      const end = `${nextY}-${String(nextM).padStart(2, '0')}-01`;
      const fetch = async () => {
        // Constroi a query base
        let q = supabase.from('pedidos').select('id, order_number, data, data_pago, valor, valor_original, desconto_total, canal, status_pagamento, quantidade, produto, is_free, contatos(nome)');
        if (filter.isFreeOnly) {
          q = q.eq('is_free', true).gte('data_pago', start).lt('data_pago', end);
        } else {
          q = q.neq('is_free', true);
          if (filter.isPendente) {
            q = q.eq('status_pagamento', 'pendente').gte('data', start).lt('data', end);
          } else {
            // Regra alinhada com os cards de Visão Geral / Faturamento Total:
            // atribuir pelo MES DE CRIAÇÃO (data) — regime de competência.
            // Pedido criado em mai pago em jun conta em mai (faturamento estável,
            // não muda com status). Caixa real (recebimento) é responsabilidade
            // do módulo Financeiro/Caixa, não desta tela.
            // isPagoOnly preserva semântica de "vendas que foram pagas no mês"
            // (caixa) e portanto usa data_pago — útil pra cruzar com caixa.
            if (filter.isPagoOnly) {
              const { data: pagos } = await supabase.from('pedidos')
                .select('id, order_number, data, data_pago, valor, valor_original, desconto_total, canal, status_pagamento, quantidade, produto, is_free, contatos(nome)')
                .eq('status_pagamento', 'pago').neq('is_free', true)
                .gte('data_pago', start).lt('data_pago', end);
              let arr = (pagos || []);
              if (filter.canal) arr = arr.filter((p: any) => p.canal === filter.canal);
              arr.sort((a: any, b: any) => (b.order_number || 0) - (a.order_number || 0));
              setRows(arr);
              return;
            }
            const { data: all } = await supabase.from('pedidos')
              .select('id, order_number, data, data_pago, valor, valor_original, desconto_total, canal, status_pagamento, quantidade, produto, is_free, contatos(nome)')
              .in('status_pagamento', ['pago', 'pendente']).neq('is_free', true)
              .gte('data', start).lt('data', end);
            let arr = (all || []);
            if (filter.canal) arr = arr.filter((p: any) => p.canal === filter.canal);
            arr.sort((a: any, b: any) => (b.order_number || 0) - (a.order_number || 0));
            setRows(arr);
            return;
          }
        }
        const { data } = await q;
        let arr = (data || []) as any[];
        if (filter.canal) arr = arr.filter(p => p.canal === filter.canal);
        arr.sort((a, b) => (b.order_number || 0) - (a.order_number || 0));
        setRows(arr);
      };
      fetch();
    }, [filter.canal, filter.isFreeOnly, filter.isPendente, filter.isPagoOnly]);

    if (rows === null) return <p className="text-center text-muted-foreground py-6 text-sm">Carregando...</p>;
    if (rows.length === 0) return <p className="text-center text-muted-foreground py-6 text-sm">Nenhum pedido encontrado neste filtro.</p>;

    const totalValor = rows.reduce((s, r) => s + (r.is_free ? 0 : Number((r.valor_original ?? r.valor) || 0) - Number(r.desconto_total || 0)), 0);
    const totalQtd = rows.reduce((s, r) => s + (Number(r.quantidade) || 0), 0);

    return (
      <div className="space-y-2">
        <div className="text-xs text-muted-foreground flex justify-between border-b pb-2">
          <span>{rows.length} pedido(s) · {totalQtd} unidade(s)</span>
          <span className="font-medium text-foreground">{formatBRL(totalValor)}</span>
        </div>
        <div className="max-h-[420px] overflow-y-auto space-y-1.5 pr-1">
          {rows.map((p: any) => (
            <button
              key={p.id}
              onClick={() => { setDetail(null); navigate('/pedidos'); }}
              className="w-full text-left flex justify-between items-center text-xs p-2 rounded hover:bg-muted/50 transition border border-transparent hover:border-border"
            >
              <div className="flex flex-col items-start min-w-0 flex-1">
                <span className="font-semibold">#{p.order_number} · {p.contatos?.nome || '—'}</span>
                <span className="text-muted-foreground text-[10px]">{p.canal} · {p.quantidade} un · {p.status_pagamento}</span>
              </div>
              <span className={cn('font-medium ml-2 shrink-0', p.is_free && 'text-sky-600')}>
                {p.is_free ? 'FREE' : formatBRL(Number((p.valor_original ?? p.valor) || 0) - Number(p.desconto_total || 0))}
              </span>
            </button>
          ))}
        </div>
      </div>
    );
  };

  // ---------- Drill-down: recebimentos do mês (CAIXA — vendas + parcelas) ----------
  const RecebimentosDetail = ({ filter }: { filter: { canal?: string } }) => {
    const [rows, setRows] = useState<any[] | null>(null);
    useEffect(() => {
      const start = `${year}-${String(month).padStart(2, '0')}-01`;
      const nextM = month === 12 ? 1 : month + 1;
      const nextY = month === 12 ? year + 1 : year;
      const end = `${nextY}-${String(nextM).padStart(2, '0')}-01`;
      const fetch = async () => {
        let q = supabase.from('lancamentos_socios')
          .select('id, tipo, valor, canal, descricao, data, pedido_id, status_pagamento')
          .in('tipo', ['VENDA', 'PARCELA_VENDA'])
          .eq('status_pagamento', 'pago')
          .gte('data', start).lt('data', end)
          .order('data', { ascending: false });
        if (filter.canal) q = q.eq('canal', filter.canal);
        const { data } = await q;
        setRows((data || []) as any[]);
      };
      fetch();
    }, [filter.canal]);

    if (rows === null) return <p className="text-center text-muted-foreground py-6 text-sm">Carregando...</p>;
    if (rows.length === 0) return <p className="text-center text-muted-foreground py-6 text-sm">Nenhum recebimento no período.</p>;

    const total = rows.reduce((s, r) => s + (Number(r.valor) || 0), 0);
    const nVendas = rows.filter(r => r.tipo === 'VENDA').length;
    const nParcelas = rows.filter(r => r.tipo === 'PARCELA_VENDA').length;

    return (
      <div className="space-y-2">
        <div className="text-xs text-muted-foreground flex justify-between border-b pb-2">
          <span>{rows.length} recebimento(s) — {nVendas} venda(s) à vista · {nParcelas} parcela(s)</span>
          <span className="font-medium text-foreground">{formatBRL(total)}</span>
        </div>
        <div className="max-h-[420px] overflow-y-auto space-y-1.5 pr-1">
          {rows.map((r: any) => (
            <button
              key={r.id}
              onClick={() => { setDetail(null); navigate('/financeiro'); }}
              className="w-full text-left flex justify-between items-center text-xs p-2 rounded hover:bg-muted/50 transition border border-transparent hover:border-border"
            >
              <div className="flex flex-col items-start min-w-0 flex-1">
                <span className="font-semibold truncate">
                  {r.tipo === 'PARCELA_VENDA' ? '🧾' : '💵'} {r.descricao || (r.tipo === 'VENDA' ? 'Venda à vista' : 'Parcela')}
                </span>
                <span className="text-muted-foreground text-[10px]">
                  {r.canal || '—'} · {r.data} · {r.tipo === 'PARCELA_VENDA' ? 'parcela' : 'à vista'}
                </span>
              </div>
              <span className="font-medium ml-2 shrink-0 text-emerald-700">{formatBRL(Number(r.valor) || 0)}</span>
            </button>
          ))}
        </div>
      </div>
    );
  };

  // ---------- Drill-down: lista de lançamentos do financeiro ----------
  const LancamentosDetail = ({ categoria, grupoId }: { categoria?: string; grupoId?: string | null }) => {
    const [rows, setRows] = useState<any[] | null>(null);
    useEffect(() => {
      const start = `${year}-${String(month).padStart(2, '0')}-01`;
      const nextM = month === 12 ? 1 : month + 1;
      const nextY = month === 12 ? year + 1 : year;
      const end = `${nextY}-${String(nextM).padStart(2, '0')}-01`;
      const fetch = async () => {
        let q = supabase.from('financeiro').select('id, tipo, valor, categoria, descricao, data, grupo_id')
          .eq('tipo', 'despesa')
          .gte('data', start).lt('data', end)
          .order('data', { ascending: false });
        if (categoria) q = q.eq('categoria', categoria);
        if (grupoId !== undefined) q = grupoId === null ? q.is('grupo_id', null) : q.eq('grupo_id', grupoId);
        const { data } = await q;
        setRows((data || []) as any[]);
      };
      fetch();
    }, [categoria]);

    if (rows === null) return <p className="text-center text-muted-foreground py-6 text-sm">Carregando...</p>;
    if (rows.length === 0) return <p className="text-center text-muted-foreground py-6 text-sm">Nenhum lançamento neste filtro.</p>;

    const total = rows.reduce((s, r) => s + Number(r.valor || 0), 0);

    return (
      <div className="space-y-2">
        <div className="text-xs text-muted-foreground flex justify-between border-b pb-2">
          <span>{rows.length} lançamento(s)</span>
          <span className="font-medium text-foreground">{formatBRL(total)}</span>
        </div>
        <div className="max-h-[380px] overflow-y-auto space-y-1.5 pr-1">
          {rows.map((r: any) => (
            <div key={r.id} className="flex justify-between items-center text-xs p-2 rounded bg-muted/30">
              <div className="flex flex-col items-start min-w-0 flex-1">
                <span className="font-semibold uppercase text-[10px] text-muted-foreground">{r.categoria}</span>
                <span className="truncate max-w-full">{r.descricao?.trim() || <span className="italic text-muted-foreground">sem descrição</span>}</span>
                <span className="text-[10px] text-muted-foreground">{new Date(r.data).toLocaleDateString('pt-BR')}</span>
              </div>
              <span className="font-medium text-destructive ml-2 shrink-0">{formatBRL(Number(r.valor))}</span>
            </div>
          ))}
        </div>
        <Button variant="outline" size="sm" className="w-full mt-2" onClick={() => { setDetail(null); navigate('/financeiro'); }}>
          <ExternalLink className="w-3.5 h-3.5 mr-1.5" />
          Abrir Financeiro pra editar
        </Button>
        <p className="text-[10px] text-center text-muted-foreground">Edição segue a regra de mesmo-dia já aplicada</p>
      </div>
    );
  };

  // ---------- Insight banner ----------
  const InsightCard = ({ insight }: { insight: Insight }) => {
    const tones: Record<Insight['tone'], string> = {
      positive: 'border-l-emerald-500 bg-emerald-50/40 dark:bg-emerald-900/10',
      negative: 'border-l-red-500 bg-red-50/40 dark:bg-red-900/10',
      warning: 'border-l-amber-500 bg-amber-50/40 dark:bg-amber-900/10',
      info: 'border-l-sky-500 bg-sky-50/40 dark:bg-sky-900/10',
    };
    return (
      <Card className={cn('rounded-2xl border-l-4 shadow-sm transition-all duration-200 hover:shadow-md hover:-translate-y-0.5', tones[insight.tone])}>
        <CardContent className="p-3">
          <div className="flex items-start gap-2">
            <span className="text-xl leading-none mt-0.5">{insight.emoji}</span>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold leading-tight">{insight.title}</p>
              {insight.description && <p className="text-[11px] text-muted-foreground mt-0.5 leading-tight">{insight.description}</p>}
            </div>
          </div>
        </CardContent>
      </Card>
    );
  };

  // ---------- Chart components ----------
  const PizzaChart = ({ title, items, formatter }: {
    title: string;
    items: Array<{ name: string; value: number; color: string }>;
    formatter: (v: number) => string;
  }) => {
    const total = items.reduce((s, i) => s + i.value, 0);
    const filtered = items.filter(i => i.value > 0);
    const config = items.reduce((acc, it) => ({ ...acc, [it.name]: { label: it.name, color: it.color } }), {} as any);
    return (
      <Card className="rounded-2xl border-border/60 shadow-sm">
        <CardContent className="p-4">
          <p className="font-display text-[15px] font-semibold mb-2">{title}</p>
          {total === 0 ? (
            <p className="text-center text-muted-foreground text-xs py-8">Sem dados no período</p>
          ) : (
            <ChartContainer config={config} className="aspect-square max-h-[260px] mx-auto">
              <PieChart>
                <ChartTooltip
                  cursor={false}
                  content={({ active, payload }: any) => {
                    if (!active || !payload?.[0]) return null;
                    const item = payload[0];
                    const pct = total > 0 ? (item.value / total * 100).toFixed(1) : '0';
                    return (
                      <div className="rounded-lg border bg-background px-3 py-2 shadow-sm text-xs">
                        <p className="font-semibold">{item.name}</p>
                        <p className="text-muted-foreground">{formatter(item.value)} <span className="opacity-60">({pct}%)</span></p>
                      </div>
                    );
                  }}
                />
                <Pie
                  data={filtered}
                  dataKey="value"
                  nameKey="name"
                  innerRadius={55}
                  outerRadius={90}
                  paddingAngle={2}
                  strokeWidth={2}
                >
                  {filtered.map((it, i) => (<Cell key={i} fill={it.color} />))}
                </Pie>
              </PieChart>
            </ChartContainer>
          )}
          {total > 0 && (
            <div className="flex flex-wrap gap-x-3 gap-y-1 justify-center text-[11px] mt-2">
              {filtered.map(it => (
                <div key={it.name} className="flex items-center gap-1">
                  <span className="w-2.5 h-2.5 rounded-sm inline-block" style={{ backgroundColor: it.color }} />
                  <span className="text-muted-foreground">{it.name}</span>
                  <span className="font-medium">{((it.value / total) * 100).toFixed(0)}%</span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    );
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

  // Fundo suave (gradiente discreto, nunca branco chapado). accent = cor da métrica.
  const softBg = (accent?: string) => accent
    ? `linear-gradient(140deg, ${accent}22, ${accent}0a 58%, transparent)`
    : 'linear-gradient(140deg, hsl(150 16% 95%), transparent 62%)';

  const MetricCard = ({ label, value, color = '', tip, onClick, accent }: { label: string; value: string; color?: string; tip?: React.ReactNode; onClick?: () => void; accent?: string }) => (
    <Card style={{ background: softBg(accent) }} className={cn('rounded-2xl border-border/60 shadow-sm transition-all duration-200', color, onClick && 'cursor-pointer hover:shadow-md hover:-translate-y-0.5')} onClick={onClick}>
      <CardContent className="p-3">
        <div className="flex items-center gap-1.5">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</p>
          {tip && <span onClick={e => e.stopPropagation()}><InfoTip>{tip}</InfoTip></span>}
        </div>
        <p className="font-display text-lg font-semibold tabular-nums mt-0.5">{value}</p>
      </CardContent>
    </Card>
  );

  const TopCard = ({ label, value, delta, color = '', tip, onClick, accent, hero }: { label: string; value: string; delta: DeltaInfo; color?: string; tip?: React.ReactNode; onClick?: () => void; accent?: string; hero?: boolean }) => {
    if (hero) {
      return (
        <Card onClick={onClick} style={{ background: 'linear-gradient(140deg, hsl(113 40% 27%), hsl(150 45% 15%))' }}
          className={cn('rounded-2xl border-0 text-white shadow-xl relative overflow-hidden transition-all duration-200', onClick && 'cursor-pointer hover:shadow-2xl hover:-translate-y-0.5')}>
          <div className="pointer-events-none absolute -right-8 -top-10 w-40 h-40 rounded-full bg-white/10 blur-2xl" />
          <CardContent className="relative p-4">
            <div className="flex items-center gap-1.5">
              <p className="text-[11px] uppercase tracking-wide text-white/70 font-medium">{label}</p>
              {tip && <span onClick={e => e.stopPropagation()}><InfoTip>{tip}</InfoTip></span>}
            </div>
            <p className="font-display text-[1.9rem] leading-none font-bold tabular-nums mt-1.5">{value}</p>
            {delta && delta.direction !== 'neutral' && (
              <div className="mt-2.5 inline-flex items-center gap-1 rounded-full bg-white/15 px-2.5 py-1 text-xs font-medium backdrop-blur">
                {delta.direction === 'up' ? <TrendingUp className="w-3.5 h-3.5" /> : <TrendingDown className="w-3.5 h-3.5" />}
                <span>{delta.percent.toFixed(0)}% vs mês anterior</span>
              </div>
            )}
          </CardContent>
        </Card>
      );
    }
    return (
    <Card style={{ background: softBg(accent) }} className={cn('rounded-2xl border-border/60 shadow-sm transition-all duration-200', color, onClick && 'cursor-pointer hover:shadow-md hover:-translate-y-0.5')} onClick={onClick}>
      <CardContent className="p-4">
        <div className="flex items-center gap-1.5">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground font-medium">{label}</p>
          {tip && <span onClick={e => e.stopPropagation()}><InfoTip>{tip}</InfoTip></span>}
        </div>
        <p className="font-display text-2xl font-semibold tabular-nums mt-1">{value}</p>
        {delta && delta.direction !== 'neutral' && (
          <div className={cn('flex items-center gap-1 text-xs mt-1 font-medium', delta.direction === 'up' ? 'text-emerald-600' : 'text-destructive')}>
            {delta.direction === 'up' ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
            <span>{delta.percent.toFixed(0)}% vs mês anterior</span>
          </div>
        )}
        {!delta && <p className="text-[10px] text-muted-foreground mt-1">— sem dado anterior pra comparar</p>}
      </CardContent>
    </Card>
    );
  };

  // Helpers para abrir o dialog
  const showFormula = (title: string, body: React.ReactNode) => setDetail({ type: 'formula', title, body });
  const showPedidos = (title: string, filter: { canal?: string; isFreeOnly?: boolean; isPendente?: boolean; isPagoOnly?: boolean }) => setDetail({ type: 'pedidos', title, filter });
  const showLancamentos = (title: string, categoria?: string, grupoId?: string | null) => setDetail({ type: 'lancamentos', title, categoria, grupoId });

  // Bodies de formula (pre-computados) — alguns sao usados varias vezes
  const formulaLucro = (
    <div className="text-sm">
      <FormulaRow label="Faturamento Total" value={formatBRL(data.fatTotal)} />
      <FormulaRow label="− Custo Total" value={formatBRL(-data.custoTotal)} />
      <FormulaRow label="Lucro" value={formatBRL(data.lucro)} isResult />
      <p className="text-xs text-muted-foreground mt-3">Faturamento (pagos + pendentes do período, exclui FREE) menos todas as despesas do período (financeiro tipo despesa).</p>
    </div>
  );
  const formulaMargem = (
    <div className="text-sm">
      <FormulaRow label="Lucro" value={formatBRL(data.lucro)} />
      <FormulaRow label="÷ Faturamento" value={formatBRL(data.fatTotal)} />
      <FormulaRow label="× 100" value="" />
      <FormulaRow label="Margem" value={`${data.margem?.toFixed(2)}%`} isResult />
      <p className="text-xs text-muted-foreground mt-3">% do faturamento que sobra como lucro líquido após custos.</p>
    </div>
  );
  const formulaIcm = (
    <div className="text-sm">
      <FormulaRow label="Custo ADS" value={formatBRL(data.custoAds)} />
      <FormulaRow label="÷ Margem total antes do ADS (Lucro + Custo ADS)" value={formatBRL((data.lucro || 0) + (data.custoAds || 0))} />
      <FormulaRow label="× 100" value="" />
      <FormulaRow label="ICM" value={`${data.icm?.toFixed(2)}%`} isResult />
      <p className="text-xs text-muted-foreground mt-3">Índice de Consumo de Margem — quanto da margem total (antes do custo de ADS) o marketing consome. Quanto menor, melhor. Alerta acima de 20%.</p>
    </div>
  );
  const formulaCpa = (
    <div className="text-sm">
      <FormulaRow label="Custo ADS" value={formatBRL(data.custoAds)} />
      <FormulaRow label="÷ Unidades ADS" value={String(data.prodAds)} />
      <FormulaRow label="CPA Un. ADS" value={formatBRL(data.cpaUnAds)} isResult />
      <p className="text-xs text-muted-foreground mt-3">Custo de anúncio por unidade vendida no canal ADS.</p>
    </div>
  );
  const formulaCac = (
    <div className="text-sm">
      <FormulaRow label="Custo ADS" value={formatBRL(data.custoAds)} />
      <FormulaRow label="÷ Pedidos ADS" value={String(data.pedidosAds)} />
      <FormulaRow label="CAC" value={formatBRL(data.cac)} isResult />
      <p className="text-xs text-muted-foreground mt-3">Custo de Aquisição: quanto custou cada venda (transação) ADS.</p>
    </div>
  );
  const formulaCustoOp = (
    <div className="text-sm">
      <FormulaRow label="Etiqueta Total" value={formatBRL(data.etiquetaTotal)} />
      <FormulaRow label="+ Logística Total" value={formatBRL(data.logTotal)} />
      <FormulaRow label="÷ Total de unidades (inclui FREE)" value={String(data.prodTotalRealistico)} />
      <FormulaRow label="Custo Operacional Un." value={formatBRL(data.custoOpUn)} isResult />
      <p className="text-xs text-muted-foreground mt-3">Custos operacionais (etiqueta + logística) diluídos por unidade efetivamente movimentada.</p>
    </div>
  );
  const formulaCustoProd = (
    <div className="text-sm">
      <FormulaRow label="Material Total" value={formatBRL(data.materialTotal)} />
      <FormulaRow label="÷ Total de unidades (inclui FREE)" value={String(data.prodTotalRealistico)} />
      <FormulaRow label="Custo Produto Un." value={formatBRL(data.custoProdUn)} isResult />
      <p className="text-xs text-muted-foreground mt-3">Material de produção diluído por unidade efetivamente movimentada.</p>
    </div>
  );
  const medLucroFormula = (canal: 'BASE' | 'ADS' | 'REP', fat: number, prod: number, valor: number) => (
    <div className="text-sm">
      <FormulaRow label={`Fat. ${canal}`} value={formatBRL(fat)} />
      <FormulaRow label={`÷ Prod. ${canal}`} value={String(prod)} />
      <FormulaRow label="Ticket médio unitário" value={prod > 0 ? formatBRL(fat / prod) : '—'} />
      <FormulaRow label="− Custo Produto Un." value={formatBRL(-data.custoProdUn)} />
      <FormulaRow label="− Custo Operacional Un." value={formatBRL(-data.custoOpUn)} />
      {canal === 'ADS' && <FormulaRow label="− CPA Un. ADS" value={formatBRL(-data.cpaUnAds)} />}
      <FormulaRow label={`Med. Lucro Un. ${canal}`} value={formatBRL(valor)} isResult />
    </div>
  );
  const formulaMedLucroGeral = (
    <div className="text-sm">
      <FormulaRow label="Lucro" value={formatBRL(data.lucro)} />
      <FormulaRow label="÷ Produtos non-FREE" value={String(data.prodTotal)} />
      <FormulaRow label="Med. Lucro Un. Geral" value={formatBRL(data.medLucroGeral)} isResult />
      <p className="text-xs text-muted-foreground mt-3">Lucro total dividido pelas unidades comercializadas (exclui FREE).</p>
    </div>
  );

  // Valores da aba OPERACIONAL por grupo (null quando "Todos os grupos").
  // CAC e CLIENTE&RECOMPRA ficam geral (por decisão — métricas de pedido/cliente
  // não dividem limpo por grupo).
  const opG = (() => {
    if (selectedGrupo === 'todos') return null;
    const g = perGrupo.find(x => (x.grupo_id || 'sem') === selectedGrupo);
    if (!g) return null;
    const u = unidGrupo.get(selectedGrupo) || { ads: 0, base: 0, rep: 0, free: 0 };
    const paid = u.ads + u.base + u.rep;
    const total = paid + u.free;
    const denom = total > 0 ? total : 1;   // custo/un divide por unidades (inclui free)
    return {
      nome: g.nome,
      custoProdUn: g.material / denom,
      custoOpUn: (g.etiquetaComp + g.logComp) / denom,
      icm: (g.lucro + g.adsComp) > 0 ? (g.adsComp / (g.lucro + g.adsComp)) * 100 : 0,
      cpaUnAds: u.ads > 0 ? g.adsComp / u.ads : 0,
      ads: u.ads, base: u.base, rep: u.rep, free: u.free, total,
      // brutos p/ os popups de fórmula
      material: g.material, adsComp: g.adsComp, etiquetaComp: g.etiquetaComp, logComp: g.logComp, lucro: g.lucro,
    };
  })();

  if (loading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-3xl font-semibold tracking-tight">Métricas</h1>
        <div className="flex gap-2">
          <Select value={String(month)} onValueChange={v => setMonth(Number(v))}>
            <SelectTrigger className="w-24"><SelectValue /></SelectTrigger>
            <SelectContent>{Array.from({ length: 12 }, (_, i) => <SelectItem key={i} value={String(i + 1)}>Mês {i + 1}</SelectItem>)}</SelectContent>
          </Select>
          <Select value={String(year)} onValueChange={v => setYear(Number(v))}>
            <SelectTrigger className="w-20"><SelectValue /></SelectTrigger>
            <SelectContent>{[2024, 2025, 2026].map(y => <SelectItem key={y} value={String(y)}>{y}</SelectItem>)}</SelectContent>
          </Select>
          {/* Grupo de produto — Todos ou um grupo específico (afeta a seção POR GRUPO) */}
          <Select value={selectedGrupo} onValueChange={setSelectedGrupo}>
            <SelectTrigger className="w-40"><SelectValue placeholder="Grupo" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos os grupos</SelectItem>
              {perGrupo.map(g => (
                <SelectItem key={g.grupo_id || 'sem'} value={g.grupo_id || 'sem'}>{g.nome}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <Tabs defaultValue="visao" className="space-y-6">
        <TabsList className="grid grid-cols-3 w-full md:w-auto md:inline-flex rounded-full bg-muted/60 p-1 h-auto">
          <TabsTrigger value="visao" className="rounded-full text-xs px-4 h-7 data-[state=active]:bg-primary data-[state=active]:text-primary-foreground data-[state=active]:shadow-sm">📊 Visão Geral</TabsTrigger>
          <TabsTrigger value="financeiro" className="rounded-full text-xs px-4 h-7 data-[state=active]:bg-primary data-[state=active]:text-primary-foreground data-[state=active]:shadow-sm">💰 Financeiro</TabsTrigger>
          <TabsTrigger value="operacional" className="rounded-full text-xs px-4 h-7 data-[state=active]:bg-primary data-[state=active]:text-primary-foreground data-[state=active]:shadow-sm">📦 Operacional</TabsTrigger>
        </TabsList>

        {/* ========================= VISÃO GERAL ========================= */}
        <TabsContent value="visao" className="space-y-6">
          {/* Top 3 com delta */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <TopCard
              label="💰 Faturamento Total (vendas no período)"
              value={formatBRL(data.fatTotal)}
              delta={deltas.fat}
              accent="#2D5A27"
              tip="Soma de pedidos do mês de criação (pagos + pendentes, exclui FREE). Atribui a venda ao mês em que foi feita."
              onClick={() => showPedidos('Pedidos do período (Faturamento)', {})}
            />
            <TopCard
              label="📦 Total de Produtos"
              value={String(data.prodTotalRealistico ?? data.prodTotal)}
              delta={deltas.prod}
              accent="#0ea5e9"
              tip="Unidades movimentadas no período: pagos + pendentes + FREE. Reflete operação real."
              onClick={() => showPedidos('Pedidos do período (Produtos)', {})}
            />
            <TopCard
              label="💵 Lucro"
              value={formatBRL(data.lucro)}
              delta={deltas.lucro}
              hero
              tip="Faturamento (com pendentes) − Custos do período."
              onClick={() => showFormula('Lucro do período', formulaLucro)}
            />
          </div>

          {/* === INSIGHTS AUTOMÁTICOS === */}
          {(() => {
            const insights = generateInsights();
            return (
              <div>
                <div className="flex items-center justify-between mb-2">
                  <h2 className="font-display font-semibold text-sm uppercase tracking-wider text-muted-foreground">
                    💡 Alertas e Destaques {insights.length > 0 && <span className="text-xs font-normal">({insights.length})</span>}
                  </h2>
                  {insights.length > 0 && (
                    <Button variant="ghost" size="sm" onClick={toggleInsights} className="h-7 text-xs">
                      {insightsExpanded ? <><ChevronUp className="w-3.5 h-3.5 mr-1" /> Esconder</> : <><ChevronDown className="w-3.5 h-3.5 mr-1" /> Mostrar</>}
                    </Button>
                  )}
                </div>
                {insightsExpanded && (
                  insights.length === 0 ? (
                    <Card className="border-dashed">
                      <CardContent className="p-4 text-center text-muted-foreground text-xs">
                        Tudo dentro da normalidade neste período 👌
                      </CardContent>
                    </Card>
                  ) : (
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-2">
                      {insights.map(ins => <InsightCard key={ins.id} insight={ins} />)}
                    </div>
                  )
                )}
              </div>
            );
          })()}

          {/* === GRÁFICOS PIZZA === */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <PizzaChart
              title="💰 Faturamento por Canal"
              items={[
                { name: 'BASE', value: data.fatBase || 0, color: COLORS.BASE },
                { name: 'ADS', value: data.fatAds || 0, color: COLORS.ADS },
                { name: 'REP', value: data.fatRep || 0, color: COLORS.REP },
              ]}
              formatter={formatBRL}
            />
            <PizzaChart
              title="💸 Custos por Categoria"
              items={[
                { name: 'ADS', value: data.custoAds || 0, color: COLORS.ADS },
                { name: 'Etiqueta', value: data.etiquetaTotal || 0, color: COLORS.ETIQUETA },
                { name: 'Logística', value: data.logTotal || 0, color: COLORS.LOGISTICA },
                { name: 'Material', value: data.materialTotal || 0, color: COLORS.MATERIAL },
              ]}
              formatter={formatBRL}
            />
            <PizzaChart
              title="📦 Produtos por Canal"
              items={[
                { name: 'BASE', value: data.prodBase || 0, color: COLORS.BASE },
                { name: 'ADS', value: data.prodAds || 0, color: COLORS.ADS },
                { name: 'REP', value: data.prodRep || 0, color: COLORS.REP },
                { name: 'FREE', value: data.prodFree || 0, color: COLORS.FREE },
              ]}
              formatter={(v) => `${v} un`}
            />
          </div>

          {/* === LINHA: FATURAMENTO MENSAL === */}
          <Card className="rounded-2xl border-border/60 shadow-sm">
            <CardContent className="p-4">
              <div className="flex items-center justify-between mb-3">
                <p className="font-display text-[15px] font-semibold">📈 Faturamento Mensal · {year}</p>
                <span className="text-[10px] text-muted-foreground uppercase tracking-wider">Pagos non-FREE</span>
              </div>
              <ChartContainer
                config={{ total: { label: 'Faturamento', color: 'hsl(var(--primary))' } }}
                className="aspect-[3/1] w-full"
              >
                <AreaChart data={monthlyData} margin={{ top: 8, right: 10, left: 0, bottom: 5 }}>
                  <defs>
                    <linearGradient id="metFatArea" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity={0.28} />
                      <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity={0} />
                    </linearGradient>
                    <filter id="metLineShadow" x="-20%" y="-40%" width="140%" height="180%">
                      <feDropShadow dx="0" dy="4" stdDeviation="4" floodColor="hsl(113 40% 22%)" floodOpacity="0.35" />
                    </filter>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} />
                  <XAxis dataKey="mes" tickLine={false} axisLine={false} fontSize={11} />
                  <YAxis tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} tickLine={false} axisLine={false} fontSize={11} width={40} />
                  <ChartTooltip
                    content={({ active, payload, label }: any) => {
                      if (!active || !payload?.[0]) return null;
                      return (
                        <div className="rounded-lg border bg-background px-3 py-2 shadow-sm text-xs">
                          <p className="font-semibold mb-1">{label}/{year}</p>
                          <p className="text-muted-foreground">Total: <span className="font-medium text-foreground">{formatBRL(payload[0].value)}</span></p>
                        </div>
                      );
                    }}
                  />
                  <Area type="monotone" dataKey="total" stroke="hsl(var(--primary))" strokeWidth={2.5} fill="url(#metFatArea)" dot={{ fill: 'hsl(var(--primary))', r: 3 }} activeDot={{ r: 6 }} style={{ filter: 'url(#metLineShadow)' }} />
                </AreaChart>
              </ChartContainer>
            </CardContent>
          </Card>

          {/* === BARRA EMPILHADA: FATURAMENTO POR CANAL × MÊS === */}
          <Card className="rounded-2xl border-border/60 shadow-sm">
            <CardContent className="p-4">
              <div className="flex items-center justify-between mb-3">
                <p className="font-display text-[15px] font-semibold">📊 Faturamento por Canal · {year}</p>
                <span className="text-[10px] text-muted-foreground uppercase tracking-wider">Composição mensal</span>
              </div>
              <ChartContainer
                config={{
                  base: { label: 'BASE', color: COLORS.BASE },
                  ads: { label: 'ADS', color: COLORS.ADS },
                  rep: { label: 'REP', color: COLORS.REP },
                }}
                className="aspect-[3/1] w-full"
              >
                <BarChart data={monthlyData} margin={{ top: 5, right: 10, left: 0, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} />
                  <XAxis dataKey="mes" tickLine={false} axisLine={false} fontSize={11} />
                  <YAxis tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} tickLine={false} axisLine={false} fontSize={11} width={40} />
                  <ChartTooltip
                    content={({ active, payload, label }: any) => {
                      if (!active || !payload?.length) return null;
                      const total = payload.reduce((s: number, p: any) => s + (Number(p.value) || 0), 0);
                      return (
                        <div className="rounded-lg border bg-background px-3 py-2 shadow-sm text-xs space-y-0.5">
                          <p className="font-semibold mb-1">{label}/{year}</p>
                          {payload.map((p: any) => (
                            <div key={p.dataKey} className="flex items-center justify-between gap-3">
                              <div className="flex items-center gap-1.5">
                                <span className="w-2 h-2 rounded-sm" style={{ backgroundColor: p.color }} />
                                <span className="text-muted-foreground capitalize">{p.dataKey}</span>
                              </div>
                              <span className="font-medium">{formatBRL(p.value)}</span>
                            </div>
                          ))}
                          <div className="pt-1 border-t mt-1 flex justify-between gap-3">
                            <span className="text-muted-foreground">Total</span>
                            <span className="font-bold">{formatBRL(total)}</span>
                          </div>
                        </div>
                      );
                    }}
                  />
                  <Bar dataKey="base" stackId="a" fill={COLORS.BASE} radius={[0, 0, 0, 0]} />
                  <Bar dataKey="ads" stackId="a" fill={COLORS.ADS} radius={[0, 0, 0, 0]} />
                  <Bar dataKey="rep" stackId="a" fill={COLORS.REP} radius={[4, 4, 0, 0]} />
                </BarChart>
              </ChartContainer>
              <div className="flex gap-3 justify-center text-[11px] mt-2">
                <div className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-sm" style={{ backgroundColor: COLORS.BASE }} /><span className="text-muted-foreground">BASE</span></div>
                <div className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-sm" style={{ backgroundColor: COLORS.ADS }} /><span className="text-muted-foreground">ADS</span></div>
                <div className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-sm" style={{ backgroundColor: COLORS.REP }} /><span className="text-muted-foreground">REP</span></div>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        {/* ========================= FINANCEIRO ========================= */}
        <TabsContent value="financeiro" className="space-y-6">
          {/* Faturamento */}
          <div>
            <h2 className="font-display font-semibold mb-2" style={{ color: '#7B1FA2' }}>FATURAMENTO</h2>
            <div className="grid grid-cols-2 md:grid-cols-6 gap-3">
              <MetricCard
                label="Fat. Total (vendas no período)"
                value={formatBRL(data.fatTotal)}
                accent="#8b5cf6"
                tip="Soma de pedidos do mês de criação (pagos + pendentes, exclui FREE). Atribui a venda ao mês em que foi feita, independente do pagamento."
                onClick={() => showPedidos('Faturamento Total (pagos + pendentes)', {})}
              />
              <Card style={{ background: softBg('#10b981') }} className="border-2 border-emerald-300 cursor-pointer hover:shadow-md hover:-translate-y-0.5 transition-all rounded-2xl" onClick={() => setDetail({ type: 'recebimentos', title: 'Recebimentos do mês (vendas + parcelas)', filter: {} })}>
                <CardContent className="p-3">
                  <div className="flex items-center gap-1.5">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">💰 Em Caixa</p>
                    <span onClick={e => e.stopPropagation()}><InfoTip>Dinheiro que entrou no mês — vendas à vista pagas no mês + parcelas pagas no mês (mesmo de pedidos criados antes). Fonte: lancamentos_socios. Regime de CAIXA, independente do mês de criação do pedido.</InfoTip></span>
                  </div>
                  <p className="font-display text-lg font-semibold tabular-nums text-emerald-700 mt-0.5">{formatBRL(data.caixaTotal || 0)}</p>
                  <p className="text-[10px] text-muted-foreground">Recebido (à vista + parcelas)</p>
                </CardContent>
              </Card>
              <Card style={{ background: softBg('#8b5cf6') }} className="border-2 border-purple-300 cursor-pointer hover:shadow-md hover:-translate-y-0.5 transition-all rounded-2xl" onClick={() => showPedidos('Pedidos Pendentes (todos)', { isPendente: true })}>
                <CardContent className="p-3">
                  <div className="flex items-center gap-1.5">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">💳 Pendentes</p>
                    <span onClick={e => e.stopPropagation()}><InfoTip>Saldo a receber dos pedidos pendentes (todos os períodos). Apenas visualização — já está incluso no Fat. Total acima.</InfoTip></span>
                  </div>
                  <p className="font-display text-lg font-semibold tabular-nums text-purple-700 mt-0.5">{formatBRL(pendentesTotal)}</p>
                  <p className="text-[10px] text-muted-foreground">Global — independente do período</p>
                </CardContent>
              </Card>
              <MetricCard label="Fat. Base" value={formatBRL(data.fatBase)} accent={CANAL_HEX.BASE} tip="Soma valor de pedidos do canal BASE no período." onClick={() => showPedidos('Faturamento BASE', { canal: 'BASE' })} />
              <MetricCard label="Fat. ADS" value={formatBRL(data.fatAds)} accent={CANAL_HEX.ADS} tip="Soma valor de pedidos do canal ADS no período." onClick={() => showPedidos('Faturamento ADS', { canal: 'ADS' })} />
              <MetricCard label="Fat. Rep" value={formatBRL(data.fatRep)} accent={CANAL_HEX.REP} tip="Soma valor de pedidos do canal REP no período." onClick={() => showPedidos('Faturamento REP', { canal: 'REP' })} />
            </div>
          </div>

          {/* ===================== POR GRUPO (só quando um grupo é escolhido) ===================== */}
          {selectedGrupo !== 'todos' && (
          <div>
            <h2 className="font-display font-semibold mb-1 text-indigo-600 dark:text-indigo-400">POR GRUPO</h2>
            <p className="text-xs text-muted-foreground mb-3">
              Material específico vai direto pro grupo; material geral ("ambos") é dividido igualmente e somado ao Material de cada grupo. ADS, etiqueta, logística, influencer e infra são rateados por receita — por isso a soma dos lucros por grupo bate com o Lucro total. Cards clicáveis.
            </p>

            {perGrupo.length === 0 ? (
              <div className="text-sm text-muted-foreground border rounded-lg p-4 bg-muted/20">
                Sem dados de grupo neste período.
              </div>
            ) : (
              <div className="space-y-5">
                {perGrupo.filter(g => (g.grupo_id || 'sem') === selectedGrupo).map(g => {
                  const margem = g.receita > 0 ? (g.lucro / g.receita) * 100 : 0;
                  const pct = g.fracao * 100;
                  const shareTip = (catLabel: string, total: number, valor: number) => (
                    <div className="text-sm">
                      <FormulaRow label={`${catLabel} (total do período)`} value={formatBRL(total)} />
                      <FormulaRow label={`× fatia de receita do grupo (${pct.toFixed(1)}%)`} value={formatPercent(pct)} />
                      <FormulaRow label="= rateado a este grupo" value={formatBRL(valor)} isResult />
                      <p className="text-xs text-muted-foreground mt-3">Custos compartilhados são rateados pela participação do grupo na receita total.</p>
                    </div>
                  );
                  return (
                    <div key={g.grupo_id || 'sem'} className="rounded-xl border p-3 bg-muted/10">
                      {/* cabeçalho do grupo */}
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <span className="w-3 h-3 rounded-full border shrink-0" style={{ backgroundColor: g.cor || '#e5e7eb' }} />
                          <h3 className="font-bold text-sm">{g.nome}</h3>
                        </div>
                        <span className={cn('text-xs font-semibold px-2 py-0.5 rounded', g.lucro >= 0 ? 'bg-primary/10 text-primary' : 'bg-destructive/10 text-destructive')}>
                          Margem {formatPercent(margem)}
                        </span>
                      </div>

                      {/* topo do cenário — Lucro primeiro (resultado do grupo) */}
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                        <MetricCard label="Lucro" value={formatBRL(g.lucro)} color="bg-card border-l-4 border-l-primary"
                          tip="Receita − Material − Rateio compartilhado."
                          onClick={() => showFormula(`Lucro · ${g.nome}`, (
                            <div className="text-sm">
                              <FormulaRow label="Receita" value={formatBRL(g.receita)} />
                              <FormulaRow label="− Material" value={formatBRL(g.material)} />
                              <FormulaRow label="− Rateio compartilhado" value={formatBRL(g.compartilhado)} />
                              <FormulaRow label="= Lucro do grupo" value={formatBRL(g.lucro)} isResult />
                            </div>
                          ))} />
                        <MetricCard label="Faturamento" value={formatBRL(g.receita)} color="bg-card border-l-4 border-l-purple-500"
                          tip="Faturamento atribuído ao grupo (peso preço×qtd dos itens; desconto rateado)."
                          onClick={() => showFormula(`Faturamento · ${g.nome}`, (
                            <div className="text-sm">
                              <FormulaRow label="Faturamento total" value={formatBRL(data.fatTotal)} />
                              <FormulaRow label={`× fatia de receita do grupo (${pct.toFixed(1)}%)`} value={formatPercent(pct)} />
                              <FormulaRow label="= Faturamento do grupo" value={formatBRL(g.receita)} isResult />
                              <p className="text-xs text-muted-foreground mt-3">O faturamento de cada pedido é distribuído entre grupos pelo peso preço×qtd dos itens.</p>
                            </div>
                          ))} />
                        <MetricCard label="Material" value={formatBRL(g.material)} color="bg-card border-l-4 border-l-destructive"
                          tip='Material específico do grupo + parte igual do material geral ("Ambos os grupos"). O clique mostra os lançamentos diretos do grupo.'
                          onClick={() => showLancamentos(`Material · ${g.nome}`, 'material', g.grupo_id)} />
                        <MetricCard label="Unidades" value={String(g.unidades)} color="bg-card border-l-4 border-l-sf-gold"
                          tip="Unidades vendidas atribuídas ao grupo no período." />
                      </div>

                      {/* rateio compartilhado detalhado */}
                      <p className="text-[11px] uppercase tracking-wide text-muted-foreground mt-3 mb-1">Rateio compartilhado — {formatBRL(g.compartilhado)}</p>
                      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                        <MetricCard label="ADS comp." value={formatBRL(g.adsComp)} color="bg-card border-l-4 border-l-destructive" tip="Fatia do grupo no Custo ADS total." onClick={() => showFormula(`ADS compartilhado · ${g.nome}`, shareTip('Custo ADS', data.custoAds, g.adsComp))} />
                        <MetricCard label="Etiqueta comp." value={formatBRL(g.etiquetaComp)} color="bg-card border-l-4 border-l-destructive" tip="Fatia do grupo na Etiqueta total." onClick={() => showFormula(`Etiqueta compartilhada · ${g.nome}`, shareTip('Etiqueta', data.etiquetaTotal, g.etiquetaComp))} />
                        <MetricCard label="Log comp." value={formatBRL(g.logComp)} color="bg-card border-l-4 border-l-destructive" tip="Fatia do grupo na Logística total." onClick={() => showFormula(`Logística compartilhada · ${g.nome}`, shareTip('Logística', data.logTotal, g.logComp))} />
                        <MetricCard label="Influencer comp." value={formatBRL(g.influencerComp)} color="bg-card border-l-4 border-l-destructive" tip="Fatia do grupo no Influencer total." onClick={() => showFormula(`Influencer compartilhado · ${g.nome}`, shareTip('Influencer', data.influencerTotal, g.influencerComp))} />
                        <MetricCard label="Infra comp." value={formatBRL(g.infraComp)} color="bg-card border-l-4 border-l-destructive" tip="Fatia do grupo na Infraestrutura total." onClick={() => showFormula(`Infraestrutura compartilhada · ${g.nome}`, shareTip('Infraestrutura', data.infraestruturaTotal, g.infraComp))} />
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
          )}

          {/* Resultado (geral — todos os grupos) */}
          <div>
            <h2 className="font-display font-semibold mb-2 text-primary">
              RESULTADO <span className="text-xs font-medium text-muted-foreground">· todos os grupos</span>
            </h2>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
              <MetricCard label="Lucro" value={formatBRL(data.lucro)} color="bg-card border-l-4 border-l-primary" tip="Faturamento − Custo Total (todos os grupos)." onClick={() => showFormula('Lucro do período', formulaLucro)} />
              <MetricCard label="Margem" value={formatPercent(data.margem)} color="bg-card border-l-4 border-l-primary" tip="(Lucro ÷ Faturamento) × 100" onClick={() => showFormula('Margem', formulaMargem)} />
              <MetricCard label="Med. Lucro Un. Base" value={formatBRL(data.medLucroBase)} color="bg-card border-l-4 border-l-primary" tip="(Fat. Base ÷ Prod. Base) − Custo Produto Un. − Custo Operacional Un." onClick={() => showFormula('Med. Lucro Un. Base', medLucroFormula('BASE', data.fatBase, data.prodBase, data.medLucroBase))} />
              <MetricCard label="Med. Lucro Un. ADS" value={formatBRL(data.medLucroAds)} color="bg-card border-l-4 border-l-primary" tip="(Fat. ADS ÷ Prod. ADS) − Custo Produto Un. − Custo Operacional Un. − CPA Un. ADS" onClick={() => showFormula('Med. Lucro Un. ADS', medLucroFormula('ADS', data.fatAds, data.prodAds, data.medLucroAds))} />
              <MetricCard label="Med. Lucro Un. Rep" value={formatBRL(data.medLucroRep)} color="bg-card border-l-4 border-l-primary" tip="(Fat. Rep ÷ Prod. Rep) − Custo Produto Un. − Custo Operacional Un." onClick={() => showFormula('Med. Lucro Un. Rep', medLucroFormula('REP', data.fatRep, data.prodRep, data.medLucroRep))} />
              <MetricCard label="Med. Lucro Un. Geral" value={formatBRL(data.medLucroGeral)} color="bg-card border-l-4 border-l-primary" tip="Lucro ÷ Produtos (pagos + pendentes, exclui FREE)." onClick={() => showFormula('Med. Lucro Un. Geral', formulaMedLucroGeral)} />
            </div>
          </div>

          {/* Custos (todos os grupos) */}
          <div>
            <h2 className="font-display font-semibold mb-2 text-destructive">
              CUSTOS <span className="text-xs font-medium text-muted-foreground">· todos os grupos</span>
            </h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <MetricCard label="Custo Total" value={formatBRL(data.custoTotal)} color="bg-card border-l-4 border-l-destructive" tip="Soma de todos os lançamentos tipo 'despesa' em Financeiro no período (todos os grupos)." onClick={() => showLancamentos('Custo Total — Lançamentos')} />
              <MetricCard label="Custo ADS" value={formatBRL(data.custoAds)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'ads' em Financeiro." onClick={() => showLancamentos('Custo ADS — Lançamentos', 'ads')} />
              <MetricCard label="Etiqueta Total" value={formatBRL(data.etiquetaTotal)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'etiqueta' em Financeiro." onClick={() => showLancamentos('Etiqueta — Lançamentos', 'etiqueta')} />
              <MetricCard label="Log Total" value={formatBRL(data.logTotal)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'logistica' em Financeiro." onClick={() => showLancamentos('Logística — Lançamentos', 'logistica')} />
              <MetricCard label="Material Total" value={formatBRL(data.materialTotal)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'material' em Financeiro (todos os grupos)." onClick={() => showLancamentos('Material — Lançamentos', 'material')} />
              <MetricCard label="Influencer" value={formatBRL(data.influencerTotal)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'influencer'. Reduz lucro mas NÃO entra em custo operacional/produção unitário." onClick={() => showLancamentos('Influencer — Lançamentos', 'influencer')} />
              <MetricCard label="Infraestrutura" value={formatBRL(data.infraestruturaTotal)} color="bg-card border-l-4 border-l-destructive" tip="Lançamentos categoria 'infraestrutura'. Reduz lucro mas NÃO entra em custo operacional/produção unitário." onClick={() => showLancamentos('Infraestrutura — Lançamentos', 'infraestrutura')} />
            </div>
          </div>

        </TabsContent>

        {/* ========================= OPERACIONAL ========================= */}
        <TabsContent value="operacional" className="space-y-6">
          {/* Indicadores */}
          <div>
            <h2 className="font-display font-semibold mb-2 text-sf-gold">
              INDICADORES <span className="text-xs font-medium text-muted-foreground">· {opG ? opG.nome : 'todos os grupos'}</span>
            </h2>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              <MetricCard label="ICM" value={formatPercent(opG ? opG.icm : data.icm)} accent="#C9A84C" tip={opG ? 'ICM do grupo: ADS rateado ÷ (Lucro do grupo + ADS rateado) × 100.' : 'Índice de Consumo de Margem: quanto da margem (antes do ADS) o custo de ADS consome. Custo ADS ÷ (Lucro + Custo ADS) × 100. Quanto menor, melhor.'}
                onClick={() => opG
                  ? showFormula(`ICM · ${opG.nome}`, (
                      <div className="text-sm">
                        <FormulaRow label="ADS rateado do grupo" value={formatBRL(opG.adsComp)} />
                        <FormulaRow label="÷ (Lucro do grupo + ADS rateado)" value={formatBRL(opG.lucro + opG.adsComp)} />
                        <FormulaRow label="× 100" value="" />
                        <FormulaRow label="ICM do grupo" value={formatPercent(opG.icm)} isResult />
                      </div>
                    ))
                  : showFormula('ICM — Índice de Consumo de Margem', formulaIcm)} />
              <MetricCard label="CPA Un. ADS" value={formatBRL(opG ? opG.cpaUnAds : data.cpaUnAds)} color="bg-card border-l-4 border-l-sf-gold" tip={opG ? 'CPA do grupo: ADS rateado do grupo ÷ unidades ADS do grupo.' : 'Custo ADS por unidade vendida ADS: Custo ADS ÷ Unidades ADS.'}
                onClick={() => opG
                  ? showFormula(`CPA Un. ADS · ${opG.nome}`, (
                      <div className="text-sm">
                        <FormulaRow label="ADS rateado do grupo" value={formatBRL(opG.adsComp)} />
                        <FormulaRow label="÷ Unidades ADS do grupo" value={String(opG.ads)} />
                        <FormulaRow label="CPA Un. ADS do grupo" value={formatBRL(opG.cpaUnAds)} isResult />
                        {opG.ads === 0 && <p className="text-xs text-muted-foreground mt-3">Sem unidades ADS no grupo neste período.</p>}
                      </div>
                    ))
                  : showFormula('CPA Un. ADS', formulaCpa)} />
              <MetricCard label={opG ? 'CAC · geral' : 'CAC'} value={formatBRL(data.cac)} color="bg-card border-l-4 border-l-sf-gold" tip="Custo de Aquisição por venda ADS: Custo ADS ÷ Nº de pedidos ADS. Sempre GERAL — um pedido pode ter itens de mais de um grupo." onClick={() => showFormula('CAC — Custo de Aquisição', formulaCac)} />
              <MetricCard label="Custo Operacional Un." value={formatBRL(opG ? opG.custoOpUn : data.custoOpUn)} color="bg-card border-l-4 border-l-sf-gold" tip={opG ? '(Etiqueta + Logística rateados do grupo) ÷ unidades do grupo (inclui free).' : '(Etiqueta + Logística) ÷ Total de unidades (inclui FREE).'}
                onClick={() => opG
                  ? showFormula(`Custo Operacional Un. · ${opG.nome}`, (
                      <div className="text-sm">
                        <FormulaRow label="Etiqueta rateada do grupo" value={formatBRL(opG.etiquetaComp)} />
                        <FormulaRow label="+ Logística rateada do grupo" value={formatBRL(opG.logComp)} />
                        <FormulaRow label="÷ Unidades do grupo (inclui free)" value={String(opG.total)} />
                        <FormulaRow label="Custo Operacional Un." value={formatBRL(opG.custoOpUn)} isResult />
                      </div>
                    ))
                  : showFormula('Custo Operacional Un.', formulaCustoOp)} />
              <MetricCard label="Custo Produto Un." value={formatBRL(opG ? opG.custoProdUn : data.custoProdUn)} color="bg-card border-l-4 border-l-sf-gold" tip={opG ? 'Material do grupo ÷ unidades do grupo (inclui free).' : 'Material ÷ Total de unidades (inclui FREE).'}
                onClick={() => opG
                  ? showFormula(`Custo Produto Un. · ${opG.nome}`, (
                      <div className="text-sm">
                        <FormulaRow label="Material do grupo" value={formatBRL(opG.material)} />
                        <FormulaRow label="÷ Unidades do grupo (inclui free)" value={String(opG.total)} />
                        <FormulaRow label="Custo Produto Un." value={formatBRL(opG.custoProdUn)} isResult />
                        <p className="text-xs text-muted-foreground mt-3">Material do grupo inclui a parte igual do material geral ("Ambos os grupos").</p>
                      </div>
                    ))
                  : showFormula('Custo Produto Un.', formulaCustoProd)} />
            </div>
          </div>

          {/* Produtos */}
          <div>
            <h2 className="font-display font-semibold mb-2" style={{ color: '#1976D2' }}>
              PRODUTOS <span className="text-xs font-medium text-muted-foreground">· {opG ? opG.nome : 'todos os grupos'}</span>
            </h2>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              <MetricCard label="Total de Produtos" value={String(opG ? opG.total : (data.prodTotalRealistico ?? data.prodTotal))} color="bg-card border-l-4 border-l-blue-500" tip="Pagos + Pendentes + FREE. Reflete unidades efetivamente movimentadas." onClick={() => !opG && showPedidos('Pedidos do período (Produtos)', {})} />
              <MetricCard label="Prod. ADS" value={String(opG ? opG.ads : data.prodAds)} color="bg-card border-l-4 border-l-blue-500" tip="Unidades vendidas (não-free) do canal ADS." onClick={() => !opG && showPedidos('Pedidos ADS', { canal: 'ADS' })} />
              <MetricCard label="Prod. Base" value={String(opG ? opG.base : data.prodBase)} color="bg-card border-l-4 border-l-blue-500" tip="Unidades vendidas (não-free) do canal BASE." onClick={() => !opG && showPedidos('Pedidos BASE', { canal: 'BASE' })} />
              <MetricCard label="Prod. Rep" value={String(opG ? opG.rep : data.prodRep)} color="bg-card border-l-4 border-l-blue-500" tip="Unidades vendidas (não-free) do canal REP." onClick={() => !opG && showPedidos('Pedidos REP', { canal: 'REP' })} />
              <MetricCard label="Prod. Free" value={String(opG ? opG.free : (data.prodFree ?? 0))} color="bg-card border-l-4 border-l-sky-500" tip="Unidades FREE: reposições (item free) + pedidos FREE da Logística. Não afeta lucro." onClick={() => !opG && showPedidos('Pedidos FREE', { isFreeOnly: true })} />
            </div>
          </div>

          {/* Cliente & Recompra */}
          <div>
            <h2 className="font-display font-semibold mb-2 text-emerald-700 flex items-center gap-2 flex-wrap">
              👥 CLIENTE &amp; RECOMPRA
              {opG && <span className="text-[11px] font-medium text-muted-foreground bg-muted rounded px-1.5 py-0.5">geral · não divide por grupo</span>}
            </h2>

            {/* Sub-bloco 1: Valor do Cliente */}
            <p className="text-xs text-muted-foreground uppercase tracking-wider mb-2 mt-3">Valor do Cliente</p>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3 mb-4">
              <MetricCard
                label="LTV Geral"
                value={recompraMetrics ? formatBRL(recompraMetrics.ltvGeral) : '—'}
                color="bg-card border-l-4 border-l-emerald-500"
                tip="Lifetime Value Geral — valor médio acumulado por cliente em toda história. Σ(receita líquida de todos pedidos pagos não-FREE) ÷ nº de contatos únicos. Histórico, independe do período selecionado."
                onClick={() => recompraMetrics && showFormula('LTV Geral', (
                  <div className="text-sm">
                    <FormulaRow label="Receita total (histórica)" value={formatBRL(recompraMetrics.ltvGeral * recompraMetrics.contatosTotal)} />
                    <FormulaRow label="÷ Contatos únicos" value={String(recompraMetrics.contatosTotal)} />
                    <FormulaRow label="LTV Geral" value={formatBRL(recompraMetrics.ltvGeral)} isResult />
                    <p className="text-xs text-muted-foreground mt-3">Receita líquida (valor_original − desconto_total) de todos pedidos pagos não-FREE, dividido pelo número de contatos únicos.</p>
                  </div>
                ))}
              />
              <MetricCard
                label="LTV BASE"
                value={recompraMetrics ? formatBRL(recompraMetrics.ltvBase) : '—'}
                color="bg-card border-l-4 border-l-emerald-500"
                tip={`LTV dos clientes diretos recorrentes (canal_origem = BASE). Base: ${recompraMetrics?.contatosBase ?? 0} contatos.`}
                onClick={() => recompraMetrics && showFormula('LTV BASE', (
                  <div className="text-sm">
                    <FormulaRow label="Receita total BASE" value={formatBRL(recompraMetrics.ltvBase * recompraMetrics.contatosBase)} />
                    <FormulaRow label="÷ Contatos BASE" value={String(recompraMetrics.contatosBase)} />
                    <FormulaRow label="LTV BASE" value={formatBRL(recompraMetrics.ltvBase)} isResult />
                  </div>
                ))}
              />
              <MetricCard
                label="LTV REP"
                value={recompraMetrics ? formatBRL(recompraMetrics.ltvRep) : '—'}
                color="bg-card border-l-4 border-l-emerald-500"
                tip={`LTV dos clientes vindos por representante (canal_origem = REP ou C-REP). Base: ${recompraMetrics?.contatosRep ?? 0} contatos. Tende a ser alto porque há poucos contatos REP com muito faturamento.`}
                onClick={() => recompraMetrics && showFormula('LTV REP', (
                  <div className="text-sm">
                    <FormulaRow label="Receita total REP/C-REP" value={formatBRL(recompraMetrics.ltvRep * recompraMetrics.contatosRep)} />
                    <FormulaRow label="÷ Contatos REP/C-REP" value={String(recompraMetrics.contatosRep)} />
                    <FormulaRow label="LTV REP" value={formatBRL(recompraMetrics.ltvRep)} isResult />
                  </div>
                ))}
              />
            </div>

            {/* Sub-bloco 2: Comportamento */}
            <p className="text-xs text-muted-foreground uppercase tracking-wider mb-2 mt-3">Comportamento</p>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <MetricCard
                label="Taxa Recompra (Período)"
                value={recompraMetrics ? formatPercent(recompraMetrics.taxaRecompraPeriodo) : '—'}
                color="bg-card border-l-4 border-l-emerald-500"
                tip="% de clientes diretos do período (ADS+BASE) que JÁ tinham comprado antes do período. Não usa canal_origem como proxy — usa histórico real de pedidos pagos. Exclui REP/C-REP."
                onClick={() => recompraMetrics && showFormula('Taxa de Recompra do Período', (
                  <div className="text-sm">
                    <p className="text-xs text-muted-foreground mb-2">Clientes diretos do período (ADS + BASE), excluindo REP/C-REP.</p>
                    <FormulaRow label="Clientes que JÁ tinham pedido pago antes" value="numerador" />
                    <FormulaRow label="÷ Total clientes únicos do período" value="denominador" />
                    <FormulaRow label="× 100" value="" />
                    <FormulaRow label="Taxa Recompra (Período)" value={formatPercent(recompraMetrics.taxaRecompraPeriodo)} isResult />
                    <p className="text-xs text-muted-foreground mt-3">Usa histórico real de pedidos pagos, não o campo canal_origem (que pode ter BASE em primeira compra de indicação).</p>
                  </div>
                ))}
              />
              <MetricCard
                label="Taxa Recompra (Histórica)"
                value={recompraMetrics ? formatPercent(recompraMetrics.taxaRecompraHistorica) : '—'}
                color="bg-card border-l-4 border-l-emerald-500"
                tip="% de todos os clientes diretos (excluindo REP/C-REP) que fizeram 2+ pedidos pagos ao longo da história. Métrica estável — não oscila por período."
                onClick={() => recompraMetrics && showFormula('Taxa de Recompra Histórica', (
                  <div className="text-sm">
                    <p className="text-xs text-muted-foreground mb-2">Contatos diretos (excluindo REP/C-REP).</p>
                    <FormulaRow label="Contatos com 2+ pedidos pagos" value="numerador" />
                    <FormulaRow label="÷ Contatos com 1+ pedido pago" value="denominador" />
                    <FormulaRow label="× 100" value="" />
                    <FormulaRow label="Taxa Recompra (Histórica)" value={formatPercent(recompraMetrics.taxaRecompraHistorica)} isResult />
                  </div>
                ))}
              />
              <MetricCard
                label="Tempo Médio de Recompra"
                value={recompraMetrics
                  ? `${recompraMetrics.tempoMedioRecompra.toFixed(0)} dias`
                  : '—'}
                color="bg-card border-l-4 border-l-emerald-500"
                tip="Intervalo médio (em dias) entre compras consecutivas de clientes diretos que recompraram. Calculado sobre TODOS os gaps de TODOS os clientes com 2+ pedidos pagos. Exclui REP/C-REP e FREE."
                onClick={() => recompraMetrics && showFormula('Tempo Médio de Recompra', (
                  <div className="text-sm">
                    <p className="text-xs text-muted-foreground mb-2">Calculado em todos os clientes diretos com 2+ pedidos pagos.</p>
                    <FormulaRow label="Σ (dias entre pedidos consecutivos)" value="totalGaps" />
                    <FormulaRow label="÷ Nº de intervalos" value="gapCount" />
                    <FormulaRow label="Tempo Médio" value={`${recompraMetrics.tempoMedioRecompra.toFixed(0)} dias`} isResult />
                    <p className="text-xs text-muted-foreground mt-3">Para cada cliente com N pedidos, calcula N-1 gaps. Soma todos os gaps de todos os clientes e tira a média global. Métrica histórica.</p>
                  </div>
                ))}
              />
            </div>
          </div>
        </TabsContent>
      </Tabs>

      {/* === DRILL-DOWN DIALOG === */}
      <Dialog open={!!detail} onOpenChange={(o) => { if (!o) setDetail(null); }}>
        <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{detail?.title}</DialogTitle>
          </DialogHeader>
          {detail?.type === 'formula' && detail.body}
          {detail?.type === 'pedidos' && <PedidosDetail filter={detail.filter} />}
          {detail?.type === 'recebimentos' && <RecebimentosDetail filter={detail.filter} />}
          {detail?.type === 'lancamentos' && <LancamentosDetail categoria={detail.categoria} grupoId={detail.grupoId} />}
        </DialogContent>
      </Dialog>
    </div>
  );
}

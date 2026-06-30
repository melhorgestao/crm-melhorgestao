import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Sparkles, Repeat, TrendingUp, Clock, Send, ChevronRight, Megaphone, ChevronDown } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';

type PeriodoKey = 'hoje' | 'ontem' | '7d' | '30d';
const PERIODOS: Array<{ key: PeriodoKey; label: string }> = [
  { key: 'hoje',  label: 'hoje' },
  { key: 'ontem', label: 'ontem' },
  { key: '7d',    label: 'últimos 7 dias' },
  { key: '30d',   label: 'últimos 30 dias' },
];

/** Retorna [inicioISO, fimISO?] do período. ontem tem teto, demais só piso. */
function rangePeriodo(p: PeriodoKey): { startIso: string; endIso?: string } {
  const now = new Date();
  const today = new Date(now); today.setHours(0, 0, 0, 0);
  if (p === 'hoje') {
    return { startIso: today.toISOString() };
  }
  if (p === 'ontem') {
    const yesterday = new Date(today); yesterday.setDate(today.getDate() - 1);
    return { startIso: yesterday.toISOString(), endIso: today.toISOString() };
  }
  const dias = p === '7d' ? 7 : 30;
  const start = new Date(today); start.setDate(today.getDate() - (dias - 1));
  return { startIso: start.toISOString() };
}

export interface CampanhaRow {
  id: string;
  nome: string;
  tipo: 'ativacao' | 'followup' | 'rmkt' | 'marketing';
  ativa: boolean;
  pausa_global: boolean;
  horario_inicio: string;
  horario_fim: string;
  cooldown_dias: number;
  dias_inativo_min: number | null;
  dias_sem_envio: number | null;
  max_tentativas_categoria: number | null;
  coffee_break_inicio: string | null;
  coffee_break_fim: string | null;
  skip_rate: number;
  intervalo_minutos: number;
  ultima_execucao_em: string | null;
  // marketing
  marketing_dispara_cliente?: boolean;
  marketing_dispara_wait_followup?: boolean;
  marketing_cooldown_dias?: number;
  marketing_prioridade?: 'sem_prioridade' | 'clientes';
}

interface Props {
  campanha: CampanhaRow;
  onOpenDetails: (c: CampanhaRow) => void;
  onToggleAtiva: (c: CampanhaRow) => void;
}

const TIPO_META: Record<CampanhaRow['tipo'], { icon: any; label: string; color: string }> = {
  ativacao:  { icon: Sparkles,    label: 'Ativação',  color: 'text-amber-500'   },
  followup:  { icon: Repeat,      label: 'Follow-up', color: 'text-blue-500'    },
  rmkt:      { icon: TrendingUp,  label: 'RMKT',      color: 'text-purple-500'  },
  marketing: { icon: Megaphone,   label: 'Marketing', color: 'text-emerald-500' },
};

export function CampanhaCard({ campanha, onOpenDetails, onToggleAtiva }: Props) {
  const c = campanha;
  const meta = TIPO_META[c.tipo];
  const Icon = meta.icon;
  const [expandido, setExpandido] = useState(false);

  // stats: templates ativos + envios hoje (total e por instância) + instâncias ON/total
  const { data: stats } = useQuery({
    queryKey: ['campanha_stats', c.id],
    queryFn: async () => {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const todayIso = today.toISOString();

      const [tpls, envios, insts, enviosPorInst, instNomes] = await Promise.all([
        supabase.from('templates_msg').select('id', { count: 'exact', head: true }).eq('campanha_id', c.id).eq('ativo', true),
        supabase.from('campanha_envios' as any).select('id', { count: 'exact', head: true }).eq('campanha_id', c.id).gte('enviado_em', todayIso),
        supabase.from('campanha_instancia' as any).select('instancia_id, ativa, limite_diario_instancia').eq('campanha_id', c.id),
        supabase.from('campanha_envios' as any).select('instancia_id').eq('campanha_id', c.id).gte('enviado_em', todayIso),
        supabase.from('instancias').select('id, nome').eq('ativo', true),
      ]);

      const ciRows = (insts.data || []) as any[];
      const ativas = ciRows.filter((i: any) => i.ativa).length;
      const total = ciRows.length;

      const enviosMap = new Map<string, number>();
      for (const e of ((enviosPorInst.data || []) as any[])) {
        enviosMap.set(e.instancia_id, (enviosMap.get(e.instancia_id) || 0) + 1);
      }

      const nomeMap = new Map<string, string>(
        ((instNomes.data || []) as any[]).map((i: any) => [i.id, i.nome])
      );

      const porInstancia = ciRows
        .map((ci: any) => ({
          instancia_id: ci.instancia_id,
          nome: nomeMap.get(ci.instancia_id) || '?',
          ativa: ci.ativa !== false,
          limite: ci.limite_diario_instancia as number | null,
          enviados: enviosMap.get(ci.instancia_id) || 0,
        }))
        .filter(r => r.nome !== 'Instancia ADMIN' && r.nome !== '?')
        .sort((a, b) => a.nome.localeCompare(b.nome));

      return {
        templates: tpls.count || 0,
        envios_hoje: envios.count || 0,
        inst_ativas: ativas,
        inst_total: total,
        por_instancia: porInstancia,
      };
    },
    refetchInterval: 60_000,
  });

  return (
    <div className={cn(
      'border rounded-2xl p-4 transition-all',
      c.ativa && !c.pausa_global ? 'bg-card hover:shadow-md' : 'bg-muted/30 opacity-70'
    )}>
      {/* Header */}
      <div className="flex items-start justify-between gap-2 mb-3">
        <div className="flex items-center gap-2 min-w-0 flex-1">
          <div className={cn('rounded-lg p-2', `${meta.color.replace('text-', 'bg-')}/15`)}>
            <Icon className={cn('w-4 h-4', meta.color)} />
          </div>
          <div className="min-w-0">
            <h3 className="font-bold truncate">{c.nome}</h3>
          </div>
        </div>
        <Switch checked={c.ativa} onCheckedChange={() => onToggleAtiva(c)} />
      </div>

      {/* Stats — Enviados hoje (somatório, com chevron pra expandir) */}
      <div className="space-y-1.5 text-sm mb-3">
        {(() => {
          const totalEnv = (stats?.por_instancia || []).reduce((s, p) => s + p.enviados, 0);
          const totalLim = (stats?.por_instancia || []).reduce((s, p) => s + (p.limite || 0), 0);
          const limStr = totalLim > 0 ? `${totalEnv} / ${totalLim}` : `${totalEnv}`;
          return (
            <button
              type="button"
              className="w-full flex items-center justify-between hover:bg-muted/50 rounded px-1 py-0.5 transition-colors"
              onClick={() => setExpandido(e => !e)}
            >
              <span className="text-muted-foreground flex items-center gap-1.5">
                <ChevronRight className={cn('w-3.5 h-3.5 transition-transform', expandido && 'rotate-90')} />
                <Send className="w-3.5 h-3.5" />
                Enviados hoje
              </span>
              <span className="tabular-nums font-medium">{limStr}</span>
            </button>
          );
        })()}
        {expandido && stats?.por_instancia?.map((p) => (
          <div key={p.instancia_id} className={cn('flex items-center justify-between pl-7 text-xs', !p.ativa && 'opacity-50')}>
            <span className="text-muted-foreground truncate">{p.nome}</span>
            <span className="tabular-nums shrink-0 ml-2">
              {p.limite != null ? `${p.enviados} / ${p.limite}` : `${p.enviados}`}
            </span>
          </div>
        ))}
        <Row icon={Repeat} label="Templates" value={`${stats?.templates ?? '—'} ${stats?.templates === 1 ? 'variação' : 'variações'}`} />
        <Row icon={Clock} label="Janela" value={`${c.horario_inicio.slice(0, 5)} → ${c.horario_fim.slice(0, 5)}`} />
      </div>

      {/* Instâncias */}
      <div className="bg-muted/40 rounded-lg px-3 py-2 mb-3 text-xs flex items-center justify-between">
        <span className="text-muted-foreground">Instâncias ativas</span>
        <span className="tabular-nums font-semibold">{stats?.inst_ativas ?? '—'} / {stats?.inst_total ?? '—'}</span>
      </div>

      <Button variant="outline" size="sm" className="w-full" onClick={() => onOpenDetails(c)}>
        Detalhes e Templates
      </Button>
    </div>
  );
}

function Row({ icon: Icon, label, value, dim }: { icon: any; label: string; value: any; dim?: boolean }) {
  return (
    <div className={cn('flex items-center justify-between', dim && 'opacity-50')}>
      <span className="text-muted-foreground flex items-center gap-1.5 min-w-0">
        <Icon className="w-3.5 h-3.5 shrink-0" />
        <span className="truncate">{label}</span>
      </span>
      <span className="tabular-nums shrink-0 ml-2">{value}</span>
    </div>
  );
}

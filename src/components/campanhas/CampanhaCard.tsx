import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Sparkles, Repeat, TrendingUp, Clock, Send } from 'lucide-react';
import { cn } from '@/lib/utils';

export interface CampanhaRow {
  id: string;
  nome: string;
  tipo: 'ativacao' | 'followup' | 'rmkt';
  ativa: boolean;
  pausa_global: boolean;
  horario_inicio: string;
  horario_fim: string;
  limite_diario_total: number | null;
  cooldown_dias: number;
  dias_inativo_min: number | null;
  dias_sem_envio: number | null;
  max_tentativas_categoria: number | null;
  coffee_break_inicio: string | null;
  coffee_break_fim: string | null;
  skip_rate: number;
  intervalo_minutos: number;
  ultima_execucao_em: string | null;
  observacao: string | null;
}

interface Props {
  campanha: CampanhaRow;
  onOpenDetails: (c: CampanhaRow) => void;
  onToggleAtiva: (c: CampanhaRow) => void;
}

const TIPO_META: Record<CampanhaRow['tipo'], { icon: any; label: string; color: string }> = {
  ativacao: { icon: Sparkles,    label: 'Ativação', color: 'text-amber-500'  },
  followup: { icon: Repeat,      label: 'Follow-up', color: 'text-blue-500' },
  rmkt:     { icon: TrendingUp,  label: 'RMKT',      color: 'text-purple-500' },
};

export function CampanhaCard({ campanha, onOpenDetails, onToggleAtiva }: Props) {
  const c = campanha;
  const meta = TIPO_META[c.tipo];
  const Icon = meta.icon;

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
            {c.observacao && <p className="text-[10px] text-muted-foreground truncate">{c.observacao}</p>}
          </div>
        </div>
        <Switch checked={c.ativa} onCheckedChange={() => onToggleAtiva(c)} />
      </div>

      {/* Stats */}
      <div className="space-y-1.5 text-sm mb-3">
        <Row icon={Send} label="Enviados hoje (total)" value={stats?.envios_hoje ?? '—'} />
        {stats?.por_instancia?.map((p) => (
          <Row
            key={p.instancia_id}
            icon={Send}
            label={`Enviados hoje (${p.nome})`}
            value={p.limite != null ? `${p.enviados} / ${p.limite}` : `${p.enviados}`}
            dim={!p.ativa}
          />
        ))}
        <Row icon={Repeat} label="Templates" value={`${stats?.templates ?? '—'} ${stats?.templates === 1 ? 'variação' : 'variações'}`} />
        <Row icon={Clock} label="Janela" value={`${c.horario_inicio.slice(0, 5)} → ${c.horario_fim.slice(0, 5)}`} />
        {c.limite_diario_total !== null && (
          <Row icon={TrendingUp} label="Limite/dia Geral" value={`${stats?.envios_hoje ?? '—'} / ${c.limite_diario_total}`} />
        )}
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

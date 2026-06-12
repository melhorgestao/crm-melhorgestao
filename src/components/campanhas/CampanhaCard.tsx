import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
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

  // stats: templates ativos + envios hoje + instâncias ON/total
  const { data: stats } = useQuery({
    queryKey: ['campanha_stats', c.id],
    queryFn: async () => {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const [tpls, envios, insts] = await Promise.all([
        supabase.from('templates_msg').select('id', { count: 'exact', head: true }).eq('campanha_id', c.id).eq('ativo', true),
        supabase.from('campanha_envios' as any).select('id', { count: 'exact', head: true }).eq('campanha_id', c.id).gte('enviado_em', today.toISOString()),
        supabase.from('campanha_instancia' as any).select('ativa', { count: 'exact' }).eq('campanha_id', c.id),
      ]);
      const ativas = ((insts.data || []) as any[]).filter((i: any) => i.ativa).length;
      const total = insts.count || 0;
      return {
        templates: tpls.count || 0,
        envios_hoje: envios.count || 0,
        inst_ativas: ativas,
        inst_total: total,
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
            <Badge variant="outline" className="text-[10px] mt-0.5">{meta.label}</Badge>
          </div>
        </div>
        <Switch checked={c.ativa} onCheckedChange={() => onToggleAtiva(c)} />
      </div>

      {/* Stats */}
      <div className="space-y-1.5 text-sm mb-3">
        <Row icon={Send} label="Enviados hoje" value={stats?.envios_hoje ?? '—'} />
        <Row icon={Repeat} label="Templates" value={`${stats?.templates ?? '—'} ${stats?.templates === 1 ? 'variação' : 'variações'}`} />
        <Row icon={Clock} label="Janela" value={`${c.horario_inicio.slice(0, 5)} → ${c.horario_fim.slice(0, 5)}`} />
        {c.limite_diario_total !== null && (
          <Row icon={TrendingUp} label="Limite/dia" value={`${stats?.envios_hoje ?? '—'} / ${c.limite_diario_total}`} />
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

function Row({ icon: Icon, label, value }: { icon: any; label: string; value: any }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-muted-foreground flex items-center gap-1.5"><Icon className="w-3.5 h-3.5" /> {label}</span>
      <span className="tabular-nums">{value}</span>
    </div>
  );
}

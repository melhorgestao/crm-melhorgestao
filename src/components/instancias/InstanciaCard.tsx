import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Crown, Settings, Pause, Play, MessageCircleMore, MessageSquare, ArrowDown, Send } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { cn } from '@/lib/utils';
import { getConnectionState } from '@/lib/evolutionApi';

export interface InstanciaRow {
  id: string;
  nome: string;
  evolution_instance: string | null;
  evolution_url: string | null;
  evolution_apikey: string | null;
  status: 'ativo' | 'desconectado' | 'banido' | 'pausado_admin';
  pausado_ate: string | null;
  motivo_pausa: string | null;
  alerta_admin: boolean;
  alerta_telefone: string | null;
  ativo: boolean;
  chatwoot_inbox_id: string | null;
  chatwoot_integrated: boolean;
  numero: string | null;
  agente_mudo: boolean;
}

interface Props {
  instancia: InstanciaRow;
  onOpenDetails: (i: InstanciaRow) => void;
  onTogglePause: (i: InstanciaRow) => void;
  onToggleMudo: (i: InstanciaRow) => void;
}

const STATUS_LABEL: Record<string, string> = {
  ativo: 'Ativa',
  desconectado: 'Desconectada',
  banido: 'Banida',
  pausado_admin: 'Pausada (admin)',
};

type Periodo = 'hoje' | 'ontem' | 'semana' | 'mes';

export function InstanciaCard({ instancia, onOpenDetails, onTogglePause, onToggleMudo }: Props) {
  const i = instancia;
  const [periodo, setPeriodo] = useState<Periodo>('hoje');

  // métricas
  const { data: metricas } = useQuery({
    queryKey: ['instancia_metricas', i.id, periodo],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('instancia_metricas' as any, { p_id: i.id, p_periodo: periodo });
      if (error) throw error;
      return data as { clientes: number; ads: number; base: number; rep: number; conv_in: number; conv_out: number; disparos: number };
    },
    refetchInterval: 60_000,
    staleTime: 30_000,
  });

  // pre-flight Evolution state
  const { data: evoState } = useQuery({
    queryKey: ['evo_state', i.id],
    enabled: !!i.evolution_apikey && !!i.evolution_instance,
    queryFn: async () => {
      return getConnectionState({
        evolution_url: i.evolution_url || '',
        evolution_instance: i.evolution_instance || '',
        evolution_apikey: i.evolution_apikey || '',
      });
    },
    refetchInterval: 60_000,
    staleTime: 30_000,
  });

  // cor do dot
  const dotClass = (() => {
    if (i.status !== 'ativo') {
      if (i.status === 'pausado_admin') return 'bg-gray-400';
      return 'bg-red-500';
    }
    if (evoState === 'open') return 'bg-green-500 animate-pulse';
    if (evoState === 'connecting') return 'bg-yellow-400 animate-pulse';
    if (evoState === 'close') return 'bg-red-500';
    return 'bg-gray-300';
  })();

  const statusText = i.status === 'ativo'
    ? (evoState === 'open' ? 'Conectada' : evoState === 'connecting' ? 'Conectando…' : evoState === 'close' ? 'Sem conexão' : STATUS_LABEL[i.status])
    : STATUS_LABEL[i.status];

  const isOn = i.status === 'ativo';

  return (
    <div className="border rounded-2xl p-4 bg-card hover:shadow-md transition-shadow">
      {/* Header */}
      <div className="flex items-start justify-between gap-2 mb-3">
        <div className="flex items-center gap-2 min-w-0 flex-1">
          <span className={cn('w-3 h-3 rounded-full shrink-0', dotClass)} />
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-bold truncate">Instância {i.nome}</h3>
              {i.alerta_admin && (
                <span title="Destino dos alertas" className="shrink-0">
                  <Crown className="w-4 h-4 text-sf-gold" />
                </span>
              )}
              {i.chatwoot_integrated && (
                <span title="Conectada ao Chatwoot" className="shrink-0">
                  <MessageSquare className="w-4 h-4 text-blue-500" />
                </span>
              )}
            </div>
            <p className="text-xs text-muted-foreground truncate font-mono">
              {i.evolution_instance || '—'}
            </p>
          </div>
        </div>
        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => onOpenDetails(i)}>
          <Settings className="w-4 h-4" />
        </Button>
      </div>

      {/* Status text */}
      <p className="text-xs text-muted-foreground mb-3">{statusText}</p>

      {/* Counts contatos */}
      <div className="space-y-1 text-sm mb-3">
        <Row label="Clientes" value={metricas?.clientes ?? '—'} valueClass="text-sf-green font-semibold" />
        <Row label="ADS" value={metricas?.ads ?? '—'} />
        <Row label="BASE" value={metricas?.base ?? '—'} />
        <Row label="REP/C-REP" value={metricas?.rep ?? '—'} />
      </div>

      {/* Conversas por período */}
      <div className="bg-muted/50 rounded-lg px-3 py-2 mb-3 flex items-center justify-between text-sm">
        <div className="flex items-center gap-1.5 min-w-0">
          <MessageCircleMore className="w-4 h-4 text-muted-foreground shrink-0" />
          <span className="text-muted-foreground">Conversas</span>
          <Select value={periodo} onValueChange={(v) => setPeriodo(v as Periodo)}>
            <SelectTrigger className="h-6 w-[104px] text-xs px-2 py-0 border-none bg-transparent hover:bg-muted focus:ring-0">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="hoje">Hoje</SelectItem>
              <SelectItem value="ontem">Ontem</SelectItem>
              <SelectItem value="semana">Essa semana</SelectItem>
              <SelectItem value="mes">Esse mês</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="flex gap-3 font-semibold tabular-nums shrink-0">
          <span className="flex items-center gap-0.5 text-emerald-600" title="Recebidas — o lead te escreveu (1 por conversa, mesmo respondendo)">
            <ArrowDown className="w-3.5 h-3.5" />{metricas?.conv_in ?? '—'}
          </span>
          <span className="flex items-center gap-0.5 text-violet-600" title="Disparos — follow-up / RMKT / fechamento custom enviados no período (volume real, independente de o lead ter respondido)">
            <Send className="w-3 h-3" />{metricas?.disparos ?? '—'}
          </span>
        </div>
      </div>

      {/* Agente Mudo — chip restrito: escuta comandos, não envia nada */}
      <div className={cn(
        'rounded-lg px-3 py-2 mb-3 border',
        i.agente_mudo ? 'border-amber-400 bg-amber-50 dark:bg-amber-950/30' : 'bg-muted/30'
      )}>
        <div className="flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="text-sm font-medium flex items-center gap-1.5">
              🤫 Agente Mudo
              {i.agente_mudo && (
                <span className="text-[10px] font-bold uppercase bg-amber-500 text-white rounded px-1.5 py-0.5">ativo</span>
              )}
            </p>
            <p className="text-[10px] text-muted-foreground leading-snug mt-0.5">
              Escuta e salva tudo + executa comandos <span className="font-mono">/</span> — mas <strong>não envia nada</strong>.
            </p>
          </div>
          <Switch checked={!!i.agente_mudo} onCheckedChange={() => onToggleMudo(i)} />
        </div>
      </div>

      {/* Actions */}
      <div className="flex gap-2">
        <Button
          variant={isOn ? 'outline' : 'default'}
          size="sm"
          className={cn('flex-1', isOn ? '' : 'bg-sf-green hover:bg-sf-green/90')}
          onClick={() => onTogglePause(i)}
        >
          {isOn ? <><Pause className="w-3.5 h-3.5 mr-1" /> Pausar</> : <><Play className="w-3.5 h-3.5 mr-1" /> Reativar</>}
        </Button>
        <Button variant="outline" size="sm" onClick={() => onOpenDetails(i)}>
          Detalhes
        </Button>
      </div>
    </div>
  );
}

function Row({ label, value, valueClass }: { label: string; value: any; valueClass?: string }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-muted-foreground">{label}:</span>
      <span className={cn('tabular-nums', valueClass)}>{value}</span>
    </div>
  );
}

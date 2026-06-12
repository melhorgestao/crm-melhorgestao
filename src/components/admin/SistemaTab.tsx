import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { toast } from 'sonner';
import { Loader2, Play, RefreshCw, AlertTriangle, CheckCircle2, Clock, ChevronRight } from 'lucide-react';
import { cn } from '@/lib/utils';

interface CronStatus {
  jobid: number;
  jobname: string;
  schedule: string;
  command: string;
  active: boolean;
  last_run_id: number | null;
  last_start: string | null;
  last_end: string | null;
  last_status: string | null;
  last_message: string | null;
  duration_ms: number | null;
  runs_24h: number;
  failures_24h: number;
}

interface CronExecucao {
  runid: number;
  start_time: string;
  end_time: string | null;
  status: string;
  return_message: string | null;
  duration_ms: number | null;
}

const SCHEDULE_LABELS: Record<string, string> = {
  '0 3 * * *':  'Diário às 00:00 BRT',
  '0 * * * *':  'A cada hora (00 min)',
  '*/30 * * * *': 'A cada 30 minutos',
  '*/10 * * * *': 'A cada 10 minutos',
};

function humanSchedule(s: string): string {
  return SCHEDULE_LABELS[s] || s;
}

function timeAgo(date: string | null): string {
  if (!date) return '—';
  const d = new Date(date).getTime();
  const now = Date.now();
  const diff = now - d;
  if (diff < 60_000) return 'agora há pouco';
  if (diff < 3_600_000) return `há ${Math.floor(diff / 60_000)}min`;
  if (diff < 86_400_000) return `há ${Math.floor(diff / 3_600_000)}h`;
  return `há ${Math.floor(diff / 86_400_000)}d`;
}

export function SistemaTab() {
  const qc = useQueryClient();
  const [selected, setSelected] = useState<CronStatus | null>(null);
  const [running, setRunning] = useState<string | null>(null);

  const { data: crons, isLoading, error, refetch } = useQuery({
    queryKey: ['cron_status_list'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('listar_crons_status');
      if (error) throw error;
      return (data || []) as CronStatus[];
    },
    refetchInterval: 30_000,
    retry: 1,
  });

  const totalFails = crons?.reduce((s, c) => s + (c.failures_24h || 0), 0) || 0;

  const runNow = async (jobname: string) => {
    if (!confirm(`Executar "${jobname}" agora? Roda o comando imediatamente.`)) return;
    setRunning(jobname);
    const { data, error } = await supabase.rpc('executar_cron_agora', { p_jobname: jobname });
    setRunning(null);
    if (error) { toast.error(error.message); return; }
    if (!(data as any)?.ok) { toast.error((data as any)?.error || 'falhou'); return; }
    toast.success(`${jobname} executado`);
    qc.invalidateQueries({ queryKey: ['cron_status_list'] });
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div>
          <h2 className="text-lg font-semibold">⏰ Cron jobs</h2>
          <p className="text-xs text-muted-foreground">
            {isLoading ? 'carregando…' : `${crons?.length || 0} jobs · ${totalFails} falha${totalFails !== 1 ? 's' : ''} nas últimas 24h`}
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={() => refetch()}>
          <RefreshCw className="w-4 h-4 mr-1" /> Atualizar
        </Button>
      </div>

      {totalFails > 0 && (
        <div className="border border-amber-300 bg-amber-50 dark:bg-amber-950/30 text-amber-900 dark:text-amber-200 rounded-lg p-3 flex items-center gap-2 text-sm">
          <AlertTriangle className="w-4 h-4 shrink-0" />
          <span>{totalFails} execução{totalFails !== 1 ? 'ões' : ''} falharam nas últimas 24h. Alertas WhatsApp já foram enviados pra instância admin.</span>
        </div>
      )}

      {error ? (
        <div className="text-center py-16 bg-destructive/10 rounded-2xl border-2 border-dashed border-destructive/30 text-destructive">
          <p className="font-semibold">Erro ao carregar crons</p>
          <p className="text-xs mt-1">{(error as any).message}</p>
          <p className="text-xs mt-2 text-muted-foreground">Verifique se a migration <code>20260615000000_sistema_cron_view</code> foi rodada.</p>
        </div>
      ) : isLoading ? (
        <div className="space-y-2">
          {Array(3).fill(0).map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)}
        </div>
      ) : (crons?.length || 0) === 0 ? (
        <p className="text-sm text-muted-foreground text-center py-8">Nenhum cron job cadastrado</p>
      ) : (
        <div className="space-y-2">
          {crons!.map(c => (
            <CronRow
              key={c.jobid}
              cron={c}
              onClick={() => setSelected(c)}
              onRun={() => runNow(c.jobname)}
              running={running === c.jobname}
            />
          ))}
        </div>
      )}

      {/* Step 2 placeholder */}
      <div className="mt-8 border-2 border-dashed rounded-lg p-4 text-center text-xs text-muted-foreground">
        🛠 <strong>Em breve</strong>: status dos workflows n8n + erros recentes do sistema + saúde do VPS
      </div>

      <CronDetailDrawer
        cron={selected}
        open={!!selected}
        onClose={() => setSelected(null)}
        onRun={(name) => runNow(name)}
        running={running}
      />
    </div>
  );
}

function CronRow({ cron, onClick, onRun, running }: { cron: CronStatus; onClick: () => void; onRun: () => void; running: boolean }) {
  const isHealthy = !cron.last_status || cron.last_status === 'succeeded';
  const hasFails = cron.failures_24h > 0;

  return (
    <div className="border rounded-xl p-3 hover:bg-muted/30 transition-colors">
      <div className="flex items-start gap-3">
        <div className={cn(
          'rounded-lg p-2 shrink-0',
          isHealthy ? 'bg-sf-green/15 text-sf-green' : 'bg-destructive/15 text-destructive'
        )}>
          {isHealthy ? <CheckCircle2 className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-semibold truncate">{cron.jobname}</span>
            {!cron.active && <Badge variant="outline" className="text-[10px]">desativado</Badge>}
            {hasFails && <Badge className="text-[10px] bg-destructive text-destructive-foreground">{cron.failures_24h} falha{cron.failures_24h !== 1 ? 's' : ''}/24h</Badge>}
          </div>
          <div className="flex items-center gap-3 text-xs text-muted-foreground mt-0.5 flex-wrap">
            <span className="flex items-center gap-1"><Clock className="w-3 h-3" /> {humanSchedule(cron.schedule)}</span>
            <span>Última: {timeAgo(cron.last_start)}</span>
            {cron.last_status && <span className={cn(cron.last_status === 'succeeded' ? 'text-sf-green' : 'text-destructive')}>
              {cron.last_status === 'succeeded' ? '✓' : '✗'} {cron.last_status}
            </span>}
            {cron.duration_ms !== null && <span>{cron.duration_ms < 1000 ? `${cron.duration_ms}ms` : `${(cron.duration_ms / 1000).toFixed(1)}s`}</span>}
          </div>
        </div>

        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={onRun} disabled={running}>
            {running ? <Loader2 className="w-4 h-4 animate-spin" /> : <Play className="w-4 h-4" />}
          </Button>
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={onClick}>
            <ChevronRight className="w-4 h-4" />
          </Button>
        </div>
      </div>
    </div>
  );
}

function CronDetailDrawer({ cron, open, onClose, onRun, running }: { cron: CronStatus | null; open: boolean; onClose: () => void; onRun: (name: string) => void; running: string | null }) {
  const { data: execs } = useQuery({
    queryKey: ['cron_execs', cron?.jobid],
    enabled: !!cron?.jobid && open,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('listar_cron_execucoes', { p_jobid: cron!.jobid, p_limit: 20 });
      if (error) throw error;
      return (data || []) as CronExecucao[];
    },
  });

  if (!cron) return null;

  return (
    <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
      <SheetContent className="w-full sm:max-w-xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{cron.jobname}</SheetTitle>
        </SheetHeader>

        <div className="space-y-5 py-4">
          <section className="space-y-2">
            <p className="text-xs uppercase text-muted-foreground tracking-wide">Configuração</p>
            <div className="border rounded-lg p-3 space-y-1.5 text-sm">
              <Row label="Schedule" value={`${humanSchedule(cron.schedule)} (${cron.schedule})`} />
              <Row label="Ativo" value={cron.active ? '✓ Sim' : '✗ Não'} />
              <Row label="Última" value={cron.last_start ? new Date(cron.last_start).toLocaleString('pt-BR') : '—'} />
              <Row label="Status" value={cron.last_status || '—'} />
              <Row label="Duração" value={cron.duration_ms !== null ? `${cron.duration_ms}ms` : '—'} />
              <Row label="24h: execuções" value={`${cron.runs_24h} (${cron.failures_24h} falhas)`} />
            </div>
          </section>

          <section className="space-y-2">
            <p className="text-xs uppercase text-muted-foreground tracking-wide">Comando SQL</p>
            <pre className="bg-muted/40 p-3 rounded-lg text-xs font-mono whitespace-pre-wrap break-words overflow-x-auto">{cron.command}</pre>
          </section>

          <section className="space-y-2">
            <Button className="w-full bg-sf-green hover:bg-sf-green/90" onClick={() => onRun(cron.jobname)} disabled={running === cron.jobname}>
              {running === cron.jobname ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Play className="w-4 h-4 mr-2" />}
              Rodar agora
            </Button>
          </section>

          <section className="space-y-2">
            <p className="text-xs uppercase text-muted-foreground tracking-wide">Últimas execuções</p>
            {!execs || execs.length === 0 ? (
              <p className="text-xs text-muted-foreground italic">Sem histórico</p>
            ) : (
              <div className="space-y-1">
                {execs.map(e => (
                  <div key={e.runid} className="flex items-start gap-2 border-l-2 border-muted pl-2 py-1 text-xs">
                    <span className={cn('shrink-0', e.status === 'succeeded' ? 'text-sf-green' : 'text-destructive')}>
                      {e.status === 'succeeded' ? '✓' : '✗'}
                    </span>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="tabular-nums">{new Date(e.start_time).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}</span>
                        {e.duration_ms !== null && <span className="text-muted-foreground">{e.duration_ms}ms</span>}
                      </div>
                      {e.return_message && e.status !== 'succeeded' && (
                        <p className="text-muted-foreground mt-0.5 break-words">{e.return_message}</p>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      </SheetContent>
    </Sheet>
  );
}

function Row({ label, value }: { label: string; value: any }) {
  return (
    <div className="flex justify-between gap-2">
      <span className="text-muted-foreground">{label}:</span>
      <span className="tabular-nums font-mono text-xs">{value}</span>
    </div>
  );
}

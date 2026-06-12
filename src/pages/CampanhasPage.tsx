import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { PauseOctagon, PlayCircle } from 'lucide-react';
import { CampanhaCard, type CampanhaRow } from '@/components/campanhas/CampanhaCard';
import { CampanhaDrawer } from '@/components/campanhas/CampanhaDrawer';

export default function CampanhasPage() {
  const { isAdmin } = useAuth();
  const qc = useQueryClient();
  const [selected, setSelected] = useState<CampanhaRow | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);

  // pausa global
  const { data: pausaGlobal } = useQuery({
    queryKey: ['campanhas_pausa_global'],
    enabled: isAdmin,
    queryFn: async () => {
      const { data } = await supabase.from('configuracoes').select('valor').eq('chave', 'campanhas_pausa_global').maybeSingle();
      return (data?.valor === 'true');
    },
    refetchInterval: 30_000,
  });

  // campanhas
  const { data: campanhas, isLoading, error: campanhasError } = useQuery({
    queryKey: ['campanhas_list'],
    enabled: isAdmin,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('campanhas')
        .select('id, nome, tipo, ativa, pausa_global, horario_inicio, horario_fim, limite_diario_total, cooldown_dias, dias_inativo_min, dias_sem_envio, max_tentativas_categoria, coffee_break_inicio, coffee_break_fim, skip_rate, intervalo_minutos, ultima_execucao_em, observacao')
        .order('tipo')
        .order('nome');
      if (error) {
        console.error('[campanhas_list] erro:', error);
        toast.error(`Erro ao carregar campanhas: ${error.message}`);
        throw error;
      }
      return (data || []) as any[] as CampanhaRow[];
    },
    refetchInterval: 60_000,
    retry: 1,
  });

  if (!isAdmin) {
    return <div className="text-center py-12 text-muted-foreground">Acesso restrito a administradores.</div>;
  }

  const ativas = campanhas?.filter(c => c.ativa).length || 0;
  const total = campanhas?.length || 0;

  const togglePausaGlobal = async () => {
    const novo = !pausaGlobal;
    if (novo && !confirm('⚠️ Pausar TODAS as campanhas? Nenhum disparo automatizado será feito até reativar.')) return;
    const { error } = await supabase.from('configuracoes').upsert(
      { chave: 'campanhas_pausa_global', valor: novo ? 'true' : 'false' },
      { onConflict: 'chave' }
    );
    if (error) { toast.error(error.message); return; }
    toast.success(novo ? '🛑 Todas as campanhas pausadas' : '▶️ Campanhas reativadas');
    qc.invalidateQueries({ queryKey: ['campanhas_pausa_global'] });
  };

  const toggleCampanhaAtiva = async (c: CampanhaRow) => {
    const { error } = await supabase.from('campanhas').update({ ativa: !c.ativa, updated_at: new Date().toISOString() }).eq('id', c.id);
    if (error) { toast.error(error.message); return; }
    toast.success(c.ativa ? 'Campanha pausada' : 'Campanha ativada');
    qc.invalidateQueries({ queryKey: ['campanhas_list'] });
  };

  const openDrawer = (c: CampanhaRow) => { setSelected(c); setDrawerOpen(true); };

  return (
    <div className="space-y-4 pb-24">
      {/* Header */}
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold">Campanhas</h1>
          <p className="text-xs text-muted-foreground">
            {isLoading ? 'carregando…' : `${ativas} ativas · ${total} total`}
          </p>
        </div>
        <Button
          variant={pausaGlobal ? 'default' : 'outline'}
          size="sm"
          onClick={togglePausaGlobal}
          className={pausaGlobal ? 'bg-sf-green hover:bg-sf-green/90' : ''}
        >
          {pausaGlobal ? <><PlayCircle className="w-4 h-4 mr-1" /> Retomar todas</> : <><PauseOctagon className="w-4 h-4 mr-1" /> Pausar todas</>}
        </Button>
      </div>

      {pausaGlobal && (
        <div className="border border-amber-300 bg-amber-50 dark:bg-amber-950/30 text-amber-900 dark:text-amber-200 rounded-lg p-3 flex items-center gap-2">
          <PauseOctagon className="w-4 h-4 shrink-0" />
          <span className="text-sm font-medium">Pausa global ativa — nenhuma campanha está disparando.</span>
        </div>
      )}

      {/* Lista */}
      {isLoading ? (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {Array(3).fill(0).map((_, i) => <Skeleton key={i} className="h-64 rounded-2xl" />)}
        </div>
      ) : campanhasError ? (
        <div className="text-center py-16 bg-destructive/10 rounded-2xl border-2 border-dashed border-destructive/30 text-destructive">
          <p className="font-semibold">Erro ao carregar campanhas</p>
          <p className="text-xs mt-1">{(campanhasError as any).message}</p>
          <p className="text-xs mt-2 text-muted-foreground">Provavelmente faltou rodar uma migration no Supabase.</p>
        </div>
      ) : total === 0 ? (
        <div className="text-center py-16 bg-muted/20 rounded-2xl border-2 border-dashed text-muted-foreground">
          <p>Nenhuma campanha cadastrada</p>
        </div>
      ) : (
        <div className="space-y-6">
          {(['ativacao', 'followup', 'rmkt'] as const).map(tipo => {
            const grupo = campanhas!.filter(c => c.tipo === tipo);
            if (grupo.length === 0) return null;
            return (
              <div key={tipo} className="space-y-3">
                <h2 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground flex items-center gap-2">
                  {tipo}
                  <Badge variant="outline" className="text-[10px]">{grupo.length}</Badge>
                </h2>
                <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
                  {grupo.map(c => (
                    <CampanhaCard
                      key={c.id}
                      campanha={c}
                      onOpenDetails={openDrawer}
                      onToggleAtiva={toggleCampanhaAtiva}
                    />
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* FAB removido — criação de campanha exige redesenho de RPCs e workflows
          (atualmente apenas 5 campanhas fixas, 1 por tipo). Quando habilitar
          múltiplas campanhas por tipo, reativar com fluxo completo. */}

      <CampanhaDrawer
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        campanha={selected}
      />
    </div>
  );
}

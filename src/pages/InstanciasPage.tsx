import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { Plus, Settings2 } from 'lucide-react';
import { InstanciaCard, type InstanciaRow } from '@/components/instancias/InstanciaCard';
import { InstanciaDrawer } from '@/components/instancias/InstanciaDrawer';
import { InstanciaCreateModal } from '@/components/instancias/InstanciaCreateModal';
import { GlobalConfigModal } from '@/components/instancias/GlobalConfigModal';

export default function InstanciasPage() {
  const { isAdmin } = useAuth();
  const qc = useQueryClient();
  const [selected, setSelected] = useState<InstanciaRow | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  const [configOpen, setConfigOpen] = useState(false);

  const { data: instancias, isLoading } = useQuery({
    queryKey: ['instancias_list'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('instancias')
        .select('id, nome, evolution_instance, evolution_url, evolution_apikey, status, pausado_ate, motivo_pausa, alerta_admin, alerta_telefone, ativo, chatwoot_inbox_id, chatwoot_integrated, numero, agente_mudo')
        .order('nome');
      if (error) throw error;
      return ((data || []) as any[])
        .filter((i: any) => i.nome !== 'Instancia ADMIN') as InstanciaRow[];
    },
    refetchInterval: 30_000,
    enabled: isAdmin,
  });

  if (!isAdmin) {
    return (
      <div className="text-center py-12 text-muted-foreground">
        <p>Acesso restrito a administradores.</p>
      </div>
    );
  }

  const ativas = instancias?.filter(i => i.status === 'ativo').length || 0;
  const pausadas = (instancias?.length || 0) - ativas;

  // Agente Mudo: instância continua escutando/salvando e executando comandos
  // fromMe, mas o bot para de enviar. Uso com o chip restrito pelo WhatsApp.
  const handleToggleMudo = async (i: InstanciaRow) => {
    const novo = !i.agente_mudo;
    // NÃO setar updated_at: a tabela instancias não tem essa coluna.
    const { error } = await supabase.from('instancias')
      .update({ agente_mudo: novo })
      .eq('id', i.id);
    if (error) { toast.error(error.message); return; }
    toast.success(novo
      ? `Instância ${i.nome}: MODO MUDO ligado — não envia nada, só escuta e obedece comandos.`
      : `Instância ${i.nome}: modo mudo desligado — bot voltou a responder.`);
    qc.invalidateQueries({ queryKey: ['instancias_list'] });
  };

  const handleTogglePause = async (i: InstanciaRow) => {
    if (i.status === 'ativo') {
      if (!confirm(`Pausar Instância ${i.nome}? Workflows pararão de usá-la até reativação.`)) return;
      const { error } = await supabase.rpc('pausar_instancia', {
        p_id: i.id, p_motivo: 'admin: pausa manual via card', p_horas: 24,
      });
      if (error) { toast.error(error.message); return; }
      toast.success(`Instância ${i.nome} pausada por 24h`);
    } else {
      const { error } = await supabase.rpc('reativar_instancia', { p_id: i.id });
      if (error) { toast.error(error.message); return; }
      toast.success(`Instância ${i.nome} reativada`);
    }
    qc.invalidateQueries({ queryKey: ['instancias_list'] });
  };

  const handleOpenDetails = (i: InstanciaRow) => {
    setSelected(i);
    setDrawerOpen(true);
  };

  return (
    <div className="space-y-4 pb-24">
      <div className="flex items-center justify-between gap-2">
        <div className="flex flex-col gap-1.5">
          <h1 className="text-2xl font-display font-bold tracking-tight">Instâncias</h1>
          {!isLoading && (
            <div className="flex items-center gap-2 text-xs">
              <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 border border-emerald-200 px-2 py-0.5 font-medium text-emerald-700">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" /> {ativas} ativa{ativas !== 1 ? 's' : ''}
              </span>
              <span className="inline-flex items-center gap-1.5 rounded-full bg-muted border border-border/60 px-2 py-0.5 font-medium text-muted-foreground">
                <span className="w-1.5 h-1.5 rounded-full bg-muted-foreground/50" /> {pausadas} pausada{pausadas !== 1 ? 's' : ''}
              </span>
            </div>
          )}
        </div>
        <Button variant="outline" size="sm" className="rounded-full" onClick={() => setConfigOpen(true)}>
          <Settings2 className="w-4 h-4 mr-1" /> Configurações
        </Button>
      </div>

      {isLoading ? (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {Array(2).fill(0).map((_, i) => <Skeleton key={i} className="h-72 rounded-2xl" />)}
        </div>
      ) : (instancias?.length || 0) === 0 ? (
        <div className="text-center py-16 bg-muted/20 rounded-2xl border-2 border-dashed text-muted-foreground">
          <p>Nenhuma instância cadastrada</p>
          <Button variant="link" onClick={() => setCreateOpen(true)}>Criar primeira instância</Button>
        </div>
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {instancias!.map(i => (
            <InstanciaCard
              key={i.id}
              instancia={i}
              onOpenDetails={handleOpenDetails}
              onTogglePause={handleTogglePause}
              onToggleMudo={handleToggleMudo}
            />
          ))}
        </div>
      )}

      {/* FAB */}
      <Button
        onClick={() => setCreateOpen(true)}
        className="fixed bottom-6 right-6 rounded-full h-14 w-14 shadow-xl shadow-emerald-900/25 text-white z-50 transition-transform hover:scale-105 active:scale-95 border-0"
        style={{ background: 'linear-gradient(140deg, #2f7d4a, #1f5c36)' }}
        size="icon"
      >
        <Plus className="w-6 h-6" />
      </Button>

      <InstanciaDrawer
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        instancia={selected}
      />
      <InstanciaCreateModal
        open={createOpen}
        onClose={() => setCreateOpen(false)}
      />
      <GlobalConfigModal
        open={configOpen}
        onClose={() => setConfigOpen(false)}
      />
    </div>
  );
}

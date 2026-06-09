import { useState, useEffect, useCallback } from 'react';
import { Bell } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';

interface Alert {
  message: string;
  link: string;
  type: string;
}

export function NotificationBell() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [lastSeenAlerts, setLastSeenAlerts] = useState<string[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const navigate = useNavigate();
  const { user } = useAuth();

  // Load seen alerts from DB per user
  useEffect(() => {
    if (!user) return;
    const loadSeen = async () => {
      const { data } = await supabase.from('configuracoes')
        .select('valor')
        .eq('chave', `seen_alerts_${user.id}`)
        .maybeSingle();
      if (data?.valor) {
        try { setLastSeenAlerts(JSON.parse(data.valor)); } catch { /* ignore */ }
      }
      setLoaded(true);
    };
    loadSeen();
  }, [user]);

  const fetchAlerts = useCallback(async () => {
    const a: Alert[] = [];

    const { data: produtos } = await supabase.from('produtos').select('nome_oficial, estoque_atual').lt('estoque_atual', 5);
    produtos?.forEach(p => a.push({ message: `📦 ${p.nome_oficial} — apenas ${p.estoque_atual} unidades restantes`, link: '/estoque', type: 'estoque' }));

    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString().split('T')[0];
    const { data: vips } = await supabase.from('contatos').select('id, nome').eq('tag_kanban', 'VIP');
    if (vips) {
      for (const v of vips) {
        const { count } = await supabase.from('pedidos').select('id', { count: 'exact', head: true }).eq('contato_id', v.id).gte('data', thirtyDaysAgo);
        if (!count || count === 0) a.push({ message: `⚠️ Cliente VIP sem comprar — ${v.nome}`, link: '/contatos', type: 'vip' });
      }
    }

    const threeDaysAgo = new Date(Date.now() - 3 * 86400000).toISOString();
    const { data: sumiu } = await supabase.from('contatos').select('nome').ilike('status_kanban', '%Sumiu%').lt('updated_at', threeDaysAgo);
    sumiu?.forEach(c => a.push({ message: `⚠️ Card Sumiu sem abordagem — ${c.nome}`, link: '/kanban', type: 'sumiu' }));

    const fourDaysAgo = new Date(Date.now() - 4 * 86400000).toISOString().split('T')[0];
    const { data: pedidos } = await supabase.from('pedidos').select('id').eq('status_pedido', 'aguardando_rastreio').lt('data', fourDaysAgo);
    if (pedidos?.length) a.push({ message: `⚠️ ${pedidos.length} pedidos aguardando postagem há mais de 4 dias`, link: '/pedidos', type: 'pedidos' });

    setAlerts(a);
  }, []);

  useEffect(() => { fetchAlerts(); const i = setInterval(fetchAlerts, 60000); return () => clearInterval(i); }, [fetchAlerts]);

  const unreadCount = loaded ? alerts.filter(a => !lastSeenAlerts.includes(`${a.type}-${a.message}`)).length : 0;

  const handleOpenChange = async (open: boolean) => {
    setIsOpen(open);
    if (open && user) {
      const allIds = alerts.map(a => `${a.type}-${a.message}`);
      setLastSeenAlerts(allIds);
      // Persist to DB
      await supabase.from('configuracoes').upsert(
        { chave: `seen_alerts_${user.id}`, valor: JSON.stringify(allIds) },
        { onConflict: 'chave' }
      );
    }
  };

  return (
    <Popover open={isOpen} onOpenChange={handleOpenChange}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="relative">
          <Bell className="w-5 h-5" />
          {unreadCount > 0 && (
            <span className="absolute -top-1 -right-1 bg-destructive text-destructive-foreground text-xs rounded-full w-5 h-5 flex items-center justify-center font-bold">
              {unreadCount}
            </span>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 max-h-96 overflow-y-auto" align="end">
        <h4 className="font-bold text-sm mb-2">Notificações</h4>
        {alerts.length === 0 ? (
          <p className="text-muted-foreground text-sm">Nenhuma notificação</p>
        ) : (
          <div className="space-y-2">
            {alerts.map((a, i) => (
              <button key={i} onClick={() => { navigate(a.link); setIsOpen(false); }} className="w-full text-left text-sm p-2 rounded hover:bg-muted transition-colors">
                {a.message}
              </button>
            ))}
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}

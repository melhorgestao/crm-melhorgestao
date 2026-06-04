import { useEffect, useState, memo } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { timeAgo, daysSince } from '@/lib/format';
import { Copy, MoreVertical, Trash2, Trophy, Phone, RotateCcw, CheckCircle } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { cn, copyToClipboard } from '@/lib/utils';

// Todas as stages visíveis por instância (mescla funnel ADS + funnel BASE).
// Cada contato fica em UMA stage por vez (não duplica).
const KANBAN_COLUMNS = [
  'Perguntou', 'Preencheu Endereço', 'Pagou', 'Clientes', 'Suporte',
  'Sumiu (Pergunta)', 'Sumiu (Endereço)'
];
const NO_DELETE_COLUMNS = ['Preencheu Endereço', 'Pagou'];

const ARCHIVE_MAP: Record<string, string> = {
  'Sumiu (Pergunta)': 'arquivado_sumiu',
  'Sumiu (Endereço)': 'arquivado_sumiu',
  'Clientes': 'arquivado',
};

const RESTORE_MAP: Record<string, string> = {
  'arquivado_sumiu': 'Sumiu (Pergunta)',
  'arquivado': 'Clientes',
};

interface Contact {
  id: string;
  nome: string;
  telefone: string;
  status_kanban: string;
  tag_vip: boolean;
  canal_origem: string;
  canal_atual?: string | null;
  instancia_id: string;
  created_at: string;
  updated_at: string;
  is_novo?: boolean | null;
  novo_ate?: string | null;
  ultima_venda_em?: string | null;
  instancias?: { nome: string; numero_final: string } | null;
}

interface Instancia {
  id: string;
  nome: string;
  ativo: boolean;
}

const KanbanCard = memo(({
  contact, col, isArchived, canDelete, isDraggable, pulsingBorder,
  draggedCard, setDraggedCard, handleReactivate, setDeleteTarget, setSuporteTarget, copyPhone
}: {
  contact: Contact; col: string; isArchived: boolean; canDelete: boolean; isDraggable: boolean; pulsingBorder: boolean;
  draggedCard: string | null; setDraggedCard: (id: string | null) => void;
  handleReactivate: (c: Contact) => void;
  setDeleteTarget: (c: Contact) => void;
  setSuporteTarget: (c: Contact) => void;
  copyPhone: (p: string) => void;
}) => {
  const showNewTag = contact.canal_origem === 'ADS';

  return (
    <Card
      key={contact.id}
      draggable={isDraggable}
      onDragStart={e => {
        if (!isDraggable) { e.preventDefault(); return; }
        e.dataTransfer.setData('contactId', contact.id);
        setDraggedCard(contact.id);
      }}
      onDragEnd={() => setDraggedCard(null)}
      className={cn(
        'cursor-grab active:cursor-grabbing mb-2',
        draggedCard === contact.id && 'opacity-50',
        !isDraggable && 'cursor-default',
        isArchived && 'opacity-50 bg-muted',
        pulsingBorder && 'animate-pulse border-2 border-destructive'
      )}
    >
      <CardContent className="p-3">
        <div className="flex items-start justify-between">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5">
              {showNewTag && (
                <Badge className="bg-blue-500 text-white text-[10px] px-1.5 py-0 font-bold">NEW</Badge>
              )}
              <p className="font-bold text-sm truncate">{contact.nome}</p>
              {contact.tag_vip && <Badge className="bg-sf-gold text-foreground text-[10px] px-1 py-0"><Trophy className="w-3 h-3" /></Badge>}
            </div>
            <div className="flex items-center gap-1 mt-1 text-xs text-muted-foreground">
              <Phone className="w-3 h-3" />
              <span>Linha: {contact.instancias?.numero_final || '—'}</span>
            </div>
            {col.includes('Sumiu') && !isArchived && <p className="text-xs text-amber-600 mt-1">{timeAgo(contact.updated_at)}</p>}
            {col === 'Clientes' && !isArchived && <p className="text-xs text-muted-foreground mt-1">Há {daysSince(contact.updated_at)} dias</p>}
          </div>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => copyPhone(contact.telefone || '')}><Copy className="w-3 h-3" /></Button>
            {isArchived ? (
              <Button variant="ghost" size="icon" className="h-7 w-7 text-primary" onClick={() => handleReactivate(contact)}>
                <RotateCcw className="w-3 h-3" />
              </Button>
            ) : canDelete && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild><Button variant="ghost" size="icon" className="h-7 w-7"><MoreVertical className="w-3 h-3" /></Button></DropdownMenuTrigger>
                <DropdownMenuContent>
                  <DropdownMenuItem onClick={() => setDeleteTarget(contact)} className="text-destructive"><Trash2 className="w-3 h-3 mr-2" /> Excluir card</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            )}
          </div>
        </div>
        {col === 'Suporte' && !isArchived && (
          <Button size="sm" className="mt-2 w-full min-h-[44px] bg-sf-green hover:bg-sf-green/90 text-primary-foreground" onClick={() => setSuporteTarget(contact)}>
            <CheckCircle className="w-4 h-4 mr-1" /> Suporte Realizado
          </Button>
        )}
      </CardContent>
    </Card>
  );
});

export default function KanbanPage() {
  const { profile } = useAuth();
  const queryClient = useQueryClient();
  const [filter, setFilter] = useState<string>(''); // instancia_id selecionada (vazio = primeira ao carregar)
  const [deleteTarget, setDeleteTarget] = useState<Contact | null>(null);
  const [suporteTarget, setSuporteTarget] = useState<Contact | null>(null);
  const [draggedCard, setDraggedCard] = useState<string | null>(null);
  const [showArchived, setShowArchived] = useState<Record<string, boolean>>({});
  const [clientesShowAll, setClientesShowAll] = useState(false);

  const canDeleteCard = (profile as any)?.pode_excluir_card !== false;
  const columns = KANBAN_COLUMNS;
  const canSwitch = profile?.acesso_kanban === 'todos';

  // Carrega instâncias ativas (exclui admin) — popula o dropdown.
  const { data: instancias = [] } = useQuery({
    queryKey: ['instancias-ativas'],
    queryFn: async () => {
      const { data } = await supabase
        .from('instancias')
        .select('id, nome, ativo')
        .eq('ativo', true)
        .order('nome', { ascending: true });
      return (data || []).filter((i: any) => i.nome !== 'Instancia ADMIN') as Instancia[];
    },
    staleTime: 10 * 60 * 1000,
  });

  // Define filtro inicial assim que instâncias carregam
  useEffect(() => {
    if (!filter && instancias.length > 0) {
      setFilter(instancias[0].id);
    }
  }, [instancias, filter]);

  const { data: kanbanData, isLoading: loading } = useQuery({
    queryKey: ['kanban', filter],
    enabled: !!filter, // Aguarda filtro carregar
    queryFn: async () => {
      const { data } = await supabase.from('contatos').select('id, nome, telefone, status_kanban, tag_vip, canal_origem, canal_atual, instancia_id, created_at, updated_at, is_novo, novo_ate, ultima_venda_em, instancias(nome, numero_final)').not('status_kanban', 'is', null);
      if (!data) return { active: [], archived: [] };
      const allContacts = data as unknown as Contact[];

      // Filtra por instância: pega contatos atribuídos a ela OU sem dono (null = livre/competido)
      const filtered = allContacts.filter(c =>
        c.instancia_id === filter || c.instancia_id === null
      );

      return {
        active: filtered.filter(c => KANBAN_COLUMNS.includes(c.status_kanban)),
        archived: filtered.filter(c => c.status_kanban === 'arquivado_sumiu' || c.status_kanban === 'arquivado')
      };
    },
    staleTime: 5 * 60 * 1000,
  });

  const contacts = kanbanData?.active || [];
  const archivedContacts = kanbanData?.archived || [];

  // Sort Clientes column by updated_at DESC (newest first)
  const getColumnContacts = (col: string) => {
    const filtered = contacts.filter(c => c.status_kanban === col);
    if (col === 'Clientes') {
      return filtered.sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());
    }
    return filtered;
  };

  useEffect(() => {
    const channel = supabase.channel('kanban-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'contatos' }, () => {
        queryClient.invalidateQueries({ queryKey: ['kanban'] });
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [queryClient]);

  // Auto-delete Suporte cards > 7 days + Auto-archive Clientes > 60 days
  useEffect(() => {
    const cleanup = async () => {
      const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString();
      const sixtyDaysAgo = new Date(Date.now() - 60 * 86400000).toISOString();

      // Suporte cards > 7 days
      const suporteCards = contacts.filter(c => c.status_kanban === 'Suporte' && c.updated_at < sevenDaysAgo);
      for (const card of suporteCards) {
        await supabase.from('contatos').update({ status_kanban: null }).eq('id', card.id);
        await supabase.from('log_atividades').insert({
          usuario: 'Sistema', acao: 'Card auto-excluído após 7 dias em Suporte', tabela_afetada: 'contatos', registro_id: card.id, detalhe: card.nome,
        });
      }

      // Clientes > 60 days sem atividade -> arquivado
      const staleClientes = contacts.filter(c => c.status_kanban === 'Clientes' && c.updated_at < sixtyDaysAgo);
      for (const card of staleClientes) {
        await supabase.from('contatos').update({ status_kanban: 'arquivado' }).eq('id', card.id);
        await supabase.from('log_atividades').insert({
          usuario: 'Sistema', acao: 'Card arquivado após 60 dias de inatividade', tabela_afetada: 'contatos', registro_id: card.id, detalhe: card.nome,
        });
      }
    };
    cleanup();
  }, [contacts]);

  const handleDrop = async (contactId: string, newColumn: string) => {
    const contact = contacts.find(c => c.id === contactId);
    if (!contact) return;
    if (contact.status_kanban === 'Pagou') { toast.info('Este card será movido automaticamente'); return; }
    await supabase.from('contatos').update({ status_kanban: newColumn, updated_at: new Date().toISOString() }).eq('id', contactId);
    toast.success('Card movido!');
    queryClient.invalidateQueries({ queryKey: ['kanban'] });
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    await supabase.from('contatos').update({ status_kanban: null }).eq('id', deleteTarget.id);
    await supabase.from('log_atividades').insert({
      usuario: profile?.nome || 'Desconhecido', acao: 'Excluiu card Kanban', tabela_afetada: 'contatos', registro_id: deleteTarget.id, detalhe: deleteTarget.nome,
    });
    toast.success('Card removido do Kanban');
    setDeleteTarget(null);
    queryClient.invalidateQueries({ queryKey: ['kanban'] });
  };

  const handleSuporteRealizado = async () => {
    if (!suporteTarget) return;
    try {
      // Determine return column based on contact's canal_atual
      // BASE-like (BASE/REP/C-REP) → 'Clientes'
      // ADS → 'Perguntou' (first column / origin)
      const canalVisual = (suporteTarget.canal_atual || suporteTarget.canal_origem || '').toUpperCase();
      const returnColumn = ['BASE', 'REP', 'C-REP'].includes(canalVisual) ? 'Clientes' : 'Perguntou';

      // 1. Move back to origin column
      await supabase.from('contatos')
        .update({ status_kanban: returnColumn, updated_at: new Date().toISOString() })
        .eq('id', suporteTarget.id);

      // 2. Insert follow_up record
      await supabase.from('follow_up').insert({
        contato_id: suporteTarget.id,
        tipo: 'SUPORTE',
        mensagem: 'Suporte Realizado via botão Kanban',
        status: 'realizado',
        data_envio: new Date().toISOString()
      });

      // 3. Log activity
      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Desconhecido',
        acao: `Suporte realizado - card retornou para ${returnColumn}`,
        tabela_afetada: 'contatos',
        registro_id: suporteTarget.id,
        detalhe: suporteTarget.nome,
      });

      toast.success(`Suporte finalizado! Card retornou para ${returnColumn}`);
      setSuporteTarget(null);
      queryClient.invalidateQueries({ queryKey: ['kanban'] });
    } catch (err: any) {
      toast.error('Erro ao processar suporte: ' + err.message);
    }
  };

  const handleReactivate = async (contact: Contact) => {
    const restoreTo = RESTORE_MAP[contact.status_kanban] || 'Perguntou';
    await supabase.from('contatos').update({ status_kanban: restoreTo, updated_at: new Date().toISOString() }).eq('id', contact.id);
    toast.success(`${contact.nome} reativado!`);
    queryClient.invalidateQueries({ queryKey: ['kanban'] });
  };

  const copyPhone = (phone: string) => {
    copyToClipboard(phone).then(success => {
      if (success) toast.success('Número Copiado!');
      else toast.error('Falha ao copiar');
    });
  };

  const getArchivedForColumn = (col: string) => {
    const archiveStatus = ARCHIVE_MAP[col];
    if (!archiveStatus) return [];
    return archivedContacts.filter(c => c.status_kanban === archiveStatus);
  };

  const hasArchiveToggle = (col: string) => !!ARCHIVE_MAP[col];

  const getColumnAccent = (col: string) => {
    if (col === 'Pagou') return 'border-t-4 border-t-primary';
    if (col.includes('Sumiu')) return 'border-t-4 border-t-amber-400';
    if (col === 'Suporte') return 'border-t-4 border-t-blue-400';
    return 'border-t-4 border-t-border';
  };

  const isSuporteOver24h = (contact: Contact) => {
    if (contact.status_kanban !== 'Suporte') return false;
    const hoursSince = (Date.now() - new Date(contact.updated_at).getTime()) / (1000 * 60 * 60);
    return hoursSince > 24;
  };

  if (loading) return <Skeleton className="h-96" />;

  const renderCardItem = (contact: Contact, col: string, isArchived = false) => {
    const canDelete = canDeleteCard && !NO_DELETE_COLUMNS.includes(col) && !isArchived;
    const isDraggable = contact.status_kanban !== 'Pagou' && !isArchived;
    const pulsingBorder = isSuporteOver24h(contact);
    return (
      <KanbanCard
        key={contact.id}
        contact={contact} col={col} isArchived={isArchived}
        canDelete={canDelete} isDraggable={isDraggable} pulsingBorder={pulsingBorder}
        draggedCard={draggedCard} setDraggedCard={setDraggedCard}
        handleReactivate={handleReactivate} setDeleteTarget={setDeleteTarget}
        setSuporteTarget={setSuporteTarget} copyPhone={copyPhone}
      />
    );
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Kanban</h1>
        {canSwitch && instancias.length > 0 && (
          <Select value={filter} onValueChange={setFilter}>
            <SelectTrigger className="w-40"><SelectValue placeholder="Instância" /></SelectTrigger>
            <SelectContent>
              {instancias.map(i => (
                <SelectItem key={i.id} value={i.id}>
                  Instância {i.nome}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}
      </div>

      <div className="flex gap-4 overflow-x-auto kanban-scroll pb-4" style={{ minHeight: 500 }}>
        {columns.map(col => {
          const allColContacts = getColumnContacts(col);
          const isClientes = col === 'Clientes';
          const colContacts = isClientes && !clientesShowAll ? allColContacts.slice(0, 100) : allColContacts;
          const archived = getArchivedForColumn(col);
          const showArch = showArchived[col] || false;
          return (
            <div
              key={col}
              className={cn('flex-shrink-0 w-72 bg-muted/50 rounded-lg', getColumnAccent(col))}
              onDragOver={e => e.preventDefault()}
              onDrop={e => { e.preventDefault(); const id = e.dataTransfer.getData('contactId'); if (id) handleDrop(id, col); }}
            >
              <div className="p-3 border-b border-border">
                <div className="flex items-center justify-between">
                  <h3 className="font-bold text-sm">{col}</h3>
                  <Badge variant="secondary" className="text-xs">{allColContacts.length}</Badge>
                </div>
                {hasArchiveToggle(col) && archived.length > 0 && (
                  <div className="flex items-center gap-2 mt-2">
                    <Switch id={`arch-${col}`} checked={showArch} onCheckedChange={v => setShowArchived(p => ({ ...p, [col]: v }))} />
                    <Label htmlFor={`arch-${col}`} className="text-xs text-muted-foreground cursor-pointer">Ver Arquivados ({archived.length})</Label>
                  </div>
                )}
              </div>
              <div className="p-2 space-y-2 max-h-[60vh] overflow-y-auto">
                {colContacts.length === 0 && !showArch && <p className="text-xs text-muted-foreground text-center py-4">Nenhum card</p>}
                {colContacts.map(contact => renderCardItem(contact, col))}
                {isClientes && allColContacts.length > 100 && !clientesShowAll && (
                  <Button variant="ghost" size="sm" className="w-full text-xs text-muted-foreground" onClick={() => setClientesShowAll(true)}>
                    Ver mais {allColContacts.length - 100} contatos
                  </Button>
                )}
                {showArch && archived.length > 0 && (
                  <>
                    <div className="border-t border-border/50 my-2" />
                    <p className="text-xs text-muted-foreground text-center">Arquivados</p>
                    {archived.map(contact => renderCardItem(contact, col, true))}
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>

      <AlertDialog open={!!deleteTarget} onOpenChange={() => setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir card</AlertDialogTitle>
            <AlertDialogDescription>Tem certeza que deseja remover {deleteTarget?.nome} do Kanban? O contato não será excluído.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-destructive text-destructive-foreground">Excluir</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={!!suporteTarget} onOpenChange={() => setSuporteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Suporte Realizado</AlertDialogTitle>
            <AlertDialogDescription>Marcar suporte como realizado para {suporteTarget?.nome}?</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleSuporteRealizado} className="bg-sf-green text-primary-foreground">Confirmar</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

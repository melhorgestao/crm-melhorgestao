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
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { toast } from 'sonner';
import { timeAgo, daysSince } from '@/lib/format';
import { Copy, MoreVertical, Trash2, Trophy, Phone, RotateCcw, CheckCircle, Plus } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { cn, copyToClipboard } from '@/lib/utils';

const ADS_COLUMNS = ['Perguntou', 'Preencheu Endereço', 'Pagou', 'Suporte', 'Sumiu (Pergunta)', 'Sumiu (Endereço)'];
const BASE_COLUMNS = ['Clientes', 'Pagou', 'Suporte'];
const NO_DELETE_COLUMNS = ['Preencheu Endereço', 'Pagou'];

const ARCHIVE_MAP: Record<string, string> = {
  'Sumiu (Pergunta)': 'arquivado_sumiu',
  'Sumiu (Endereço)': 'arquivado_sumiu',
  'Clientes': 'arquivado',
};

const RESTORE_MAP: Record<string, string> = {
  'arquivado_sumiu': 'Perguntou',
  'arquivado': 'Clientes',
};

interface Contact {
  id: string;
  nome: string;
  telefone: string;
  status_kanban: string;
  canal_origem: string;
  canal_atual?: string | null;
  created_at: string;
  updated_at: string;
  tag_kanban?: string | null;
  tag_kanban_ate?: string | null;
  ultima_venda_em?: string | null;
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
  const activeTag = contact.tag_kanban && (!contact.tag_kanban_ate || new Date(contact.tag_kanban_ate) > new Date()) ? contact.tag_kanban : null;

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
            <div className="flex items-center gap-1.5 flex-wrap">
              {activeTag === 'NEW' && (
                <Badge className="bg-blue-500 text-white text-[10px] px-1.5 py-0 font-bold">NEW</Badge>
              )}
              {activeTag === 'VIP' && (
                <Badge className="bg-yellow-500 text-black text-[10px] px-1.5 py-0 font-bold">VIP</Badge>
              )}
              {activeTag === 'REP' && (
                <Badge className="bg-orange-500 text-white text-[10px] px-1.5 py-0 font-bold">REP</Badge>
              )}
              {activeTag === 'OFF' && (
                <Badge className="bg-gray-400 text-white text-[10px] px-1.5 py-0 font-bold">OFF</Badge>
              )}
              <p className="font-bold text-sm truncate">{contact.nome}</p>
            </div>
            <div className="flex items-center gap-1 mt-1 text-xs text-muted-foreground">
              <Phone className="w-3 h-3" />
              <span>{contact.telefone || '—'}</span>
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

export default function KanbanRepPage() {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState('base');
  const [deleteTarget, setDeleteTarget] = useState<Contact | null>(null);
  const [suporteTarget, setSuporteTarget] = useState<Contact | null>(null);
  const [draggedCard, setDraggedCard] = useState<string | null>(null);
  const [showArchived, setShowArchived] = useState<Record<string, boolean>>({});
  const [showCreate, setShowCreate] = useState(false);
  const [formNome, setFormNome] = useState('');
  const [formTelefone, setFormTelefone] = useState('');
  const [creating, setCreating] = useState(false);

  const columns = activeTab === 'ads' ? ADS_COLUMNS : BASE_COLUMNS;

  const { data: kanbanData, isLoading: loading } = useQuery({
    queryKey: ['kanban-rep', activeTab, user?.id],
    queryFn: async () => {
      const { data } = await supabase
        .from('contatos')
        .select('id, nome, telefone, status_kanban, canal_origem, canal_atual, created_at, updated_at, tag_kanban, tag_kanban_ate, ultima_venda_em, representante_id')
        .eq('representante_id', user?.id)
        .not('status_kanban', 'is', null);
      if (!data) return { active: [], archived: [] };
      const allContacts = data as unknown as Contact[];

      const filtered = allContacts.filter(c => {
        const canal = (c.canal_atual || c.canal_origem).toUpperCase();
        if (activeTab === 'ads') return canal === 'ADS';
        return canal === 'BASE';
      });

      return {
        active: filtered.filter(c => columns.includes(c.status_kanban)),
        archived: filtered.filter(c => c.status_kanban === 'arquivado_sumiu' || c.status_kanban === 'arquivado')
      };
    },
    staleTime: 5 * 60 * 1000,
  });

  const contacts = kanbanData?.active || [];
  const archivedContacts = kanbanData?.archived || [];

  useEffect(() => {
    const channel = supabase.channel('kanban-rep-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'contatos' }, () => {
        queryClient.invalidateQueries({ queryKey: ['kanban-rep'] });
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [queryClient]);

  useEffect(() => {
    const cleanup = async () => {
      const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString();
      const suporteCards = contacts.filter(c => c.status_kanban === 'Suporte' && c.updated_at < sevenDaysAgo);
      for (const card of suporteCards) {
        await supabase.from('contatos').update({ status_kanban: null }).eq('id', card.id);
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
    queryClient.invalidateQueries({ queryKey: ['kanban-rep'] });
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    await supabase.from('contatos').update({ status_kanban: null }).eq('id', deleteTarget.id);
    toast.success('Card removido do Kanban');
    setDeleteTarget(null);
    queryClient.invalidateQueries({ queryKey: ['kanban-rep'] });
  };

  const handleSuporteRealizado = async () => {
    if (!suporteTarget) return;
    try {
      const returnColumn = activeTab === 'base' ? 'Clientes' : 'Perguntou';
      await supabase.from('contatos').update({ status_kanban: returnColumn, updated_at: new Date().toISOString() }).eq('id', suporteTarget.id);
      await supabase.from('follow_up').insert({
        contato_id: suporteTarget.id, tipo: 'SUPORTE', mensagem: 'Suporte Realizado via Kanban', status: 'realizado', data_envio: new Date().toISOString()
      });
      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Desconhecido',
        acao: `Suporte realizado - card retornou para ${returnColumn}`,
        tabela_afetada: 'contatos',
        registro_id: suporteTarget.id,
        detalhe: suporteTarget.nome,
      });
      toast.success(`Suporte finalizado! Card retornou para ${returnColumn}`);
      setSuporteTarget(null);
      queryClient.invalidateQueries({ queryKey: ['kanban-rep'] });
    } catch (err: any) {
      toast.error('Erro ao processar suporte: ' + err.message);
    }
  };

  const handleReactivate = async (contact: Contact) => {
    const restoreTo = RESTORE_MAP[contact.status_kanban] || 'Perguntou';
    await supabase.from('contatos').update({ status_kanban: restoreTo, updated_at: new Date().toISOString() }).eq('id', contact.id);
    toast.success(`${contact.nome} reativado!`);
    queryClient.invalidateQueries({ queryKey: ['kanban-rep'] });
  };

  const handleCreateContact = async () => {
    if (!formNome.trim()) { toast.error('Nome é obrigatório'); return; }
    setCreating(true);
    try {
      const { error } = await supabase.from('contatos').insert({
        nome: formNome.trim(),
        telefone: formTelefone || null,
        canal_origem: activeTab === 'ads' ? 'ADS' : 'BASE',
        canal_atual: activeTab === 'ads' ? 'ADS' : 'BASE',
        status_kanban: 'Perguntou',
        representante_id: user?.id,
      });
      if (error) throw error;
      toast.success('Contato criado!');
      setShowCreate(false);
      setFormNome('');
      setFormTelefone('');
      queryClient.invalidateQueries({ queryKey: ['kanban-rep'] });
    } catch (err: any) {
      toast.error(err.message || 'Erro ao criar contato');
    } finally {
      setCreating(false);
    }
  };

  const copyPhone = (phone: string) => {
    copyToClipboard(phone).then(success => {
      if (success) toast.success('Número Copiado!');
      else toast.error('Falha ao copiar');
    });
  };

  const getColumnContacts = (col: string) => contacts.filter(c => c.status_kanban === col);
  const getArchivedForColumn = (col: string) => {
    const archiveStatus = ARCHIVE_MAP[col];
    if (!archiveStatus) return [];
    return archivedContacts.filter(c => c.status_kanban === archiveStatus);
  };

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
    const canDelete = !NO_DELETE_COLUMNS.includes(col) && !isArchived;
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
        <Button onClick={() => setShowCreate(true)} className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground">
          <Plus className="w-4 h-4 mr-1" /> Novo Contato
        </Button>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="base">BASE</TabsTrigger>
          <TabsTrigger value="ads">ADS</TabsTrigger>
        </TabsList>

        <TabsContent value={activeTab} className="mt-4">
          <div className="flex gap-4 overflow-x-auto kanban-scroll pb-4" style={{ minHeight: 500 }}>
            {columns.map(col => {
              const colContacts = getColumnContacts(col);
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
                      <Badge variant="secondary" className="text-xs">{colContacts.length}</Badge>
                    </div>
                  </div>
                  <div className="p-2 space-y-2 max-h-[60vh] overflow-y-auto">
                    {colContacts.length === 0 && !showArch && <p className="text-xs text-muted-foreground text-center py-4">Nenhum card</p>}
                    {colContacts.map(contact => renderCardItem(contact, col))}
                  </div>
                </div>
              );
            })}
          </div>
        </TabsContent>
      </Tabs>

      <AlertDialog open={!!deleteTarget} onOpenChange={() => setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir card</AlertDialogTitle>
            <AlertDialogDescription>Tem certeza que deseja remover {deleteTarget?.nome} do Kanban?</AlertDialogDescription>
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

      <Dialog open={showCreate} onOpenChange={setShowCreate}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Novo Contato</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Nome</Label>
              <Input value={formNome} onChange={e => setFormNome(e.target.value)} placeholder="Nome do cliente" className="min-h-[44px]" />
            </div>
            <div>
              <Label>Telefone</Label>
              <Input value={formTelefone} onChange={e => setFormTelefone(e.target.value)} placeholder="(XX) XXXXX-XXXX" className="min-h-[44px]" />
            </div>
            <Button onClick={handleCreateContact} disabled={creating} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px]">
              {creating ? 'Criando...' : 'Criar'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

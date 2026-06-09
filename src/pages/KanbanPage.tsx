import { useEffect, useState, memo } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { timeAgo } from '@/lib/format';
import { Copy, MoreVertical, Trash2, Phone, CheckCircle, AlertCircle, Clock } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { cn, copyToClipboard } from '@/lib/utils';

// 5 colunas do Kanban derivadas de ultima_interacao
// Mapping: column key (estado interno) → label visual
const KANBAN_COLUMNS = [
  { key: 'wait_follow_up', label: 'WAIT F-UP', accent: 'border-t-amber-400' },
  { key: 'follow_up',      label: 'F-UP',      accent: 'border-t-orange-500' },
  { key: 'rmkt',           label: 'RMKT',      accent: 'border-t-purple-500' },
  { key: 'em_fechamento',  label: 'FECHAMENTO', accent: 'border-t-primary' },
  { key: 'suporte',        label: 'SUPORTE',   accent: 'border-t-blue-500' },
] as const;

type ColumnKey = typeof KANBAN_COLUMNS[number]['key'];

interface Contact {
  id: string;
  nome: string;
  telefone: string;
  canal_origem: string;
  canal_atual?: string | null;
  instancia_id: string;
  created_at: string;
  updated_at: string;
  tag_kanban?: string | null;
  tag_kanban_ate?: string | null;
  ultima_interacao?: string | null;
  ja_comprou?: boolean | null;
  follow_up_tentativas?: number | null;
  ativacao_tentativas?: number | null;
  data_start?: string | null;
  data_wait_follow_up?: string | null;
  data_ultimo_follow_up?: string | null;
  data_em_fechamento?: string | null;
  data_ultimo_rmkt?: string | null;
  data_suporte?: string | null;
  suporte_motivo?: string | null;
  instancias?: { nome: string; numero_final: string } | null;
}

interface Instancia {
  id: string;
  nome: string;
  ativo: boolean;
}

// Define qual estado o contato retorna ao sair de Suporte/Fechamento
const computeReturnState = (contact: Contact): string => {
  if (contact.ja_comprou) return 'cliente';
  if (contact.canal_atual && ['REP', 'C-REP'].includes(contact.canal_atual)) return 'suporte';
  if (contact.canal_atual === 'ADS') return 'wait_follow_up';
  return 'ativacao_contatos'; // BASE, SCRAP, demais
};

const formatTentativa = (atual: number | null | undefined, max = 3) => {
  if (!atual) return null;
  return `${atual}/${max}`;
};

const KanbanCard = memo(({
  contact, column, canDelete, isDraggable,
  draggedCard, setDraggedCard, setDeleteTarget, setSuporteTarget, copyPhone
}: {
  contact: Contact;
  column: ColumnKey;
  canDelete: boolean;
  isDraggable: boolean;
  draggedCard: string | null;
  setDraggedCard: (id: string | null) => void;
  setDeleteTarget: (c: Contact) => void;
  setSuporteTarget: (c: Contact) => void;
  copyPhone: (p: string) => void;
}) => {
  const activeTag = contact.tag_kanban &&
    (!contact.tag_kanban_ate || new Date(contact.tag_kanban_ate) > new Date())
    ? contact.tag_kanban : null;

  // Determina tempo "no estado" e tentativa pra exibir
  const stateInfo = (() => {
    switch (column) {
      case 'wait_follow_up':
        return {
          time: contact.data_wait_follow_up ? timeAgo(contact.data_wait_follow_up) : null,
          tentativa: formatTentativa(contact.follow_up_tentativas, 3),
          label: 'no aguardo',
        };
      case 'follow_up':
        return {
          time: contact.data_ultimo_follow_up ? timeAgo(contact.data_ultimo_follow_up) : null,
          tentativa: formatTentativa(contact.follow_up_tentativas, 3),
          label: 'disparado',
        };
      case 'rmkt':
        return {
          time: contact.data_ultimo_rmkt ? timeAgo(contact.data_ultimo_rmkt) : null,
          tentativa: null,
          label: 'disparado',
        };
      case 'em_fechamento':
        return {
          time: contact.data_em_fechamento ? timeAgo(contact.data_em_fechamento) : null,
          tentativa: null,
          label: 'em negociação',
        };
      case 'suporte':
        return {
          time: contact.data_suporte ? timeAgo(contact.data_suporte) : null,
          tentativa: null,
          label: contact.suporte_motivo || 'suporte',
        };
      default:
        return { time: null, tentativa: null, label: null };
    }
  })();

  // Card pulsante se em suporte há mais de 24h
  const isUrgent = column === 'suporte' && contact.data_suporte
    && (Date.now() - new Date(contact.data_suporte).getTime()) > 24 * 3600 * 1000;

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
        isUrgent && 'animate-pulse border-2 border-destructive'
      )}
    >
      <CardContent className="p-3">
        <div className="flex items-start justify-between">
          <div className="flex-1 min-w-0">
            {/* Tags + nome */}
            <div className="flex items-center gap-1 flex-wrap">
              {activeTag === 'NEW' && <Badge className="bg-blue-500 text-white text-[10px] px-1.5 py-0 font-bold">NEW</Badge>}
              {activeTag === 'VIP' && <Badge className="bg-yellow-500 text-black text-[10px] px-1.5 py-0 font-bold">VIP</Badge>}
              {activeTag === 'BUYER' && <Badge className="bg-emerald-500 text-white text-[10px] px-1.5 py-0 font-bold">BUYER</Badge>}
              {activeTag === 'REP' && <Badge className="bg-orange-500 text-white text-[10px] px-1.5 py-0 font-bold">REP</Badge>}
              {activeTag === 'ADS' && <Badge className="bg-purple-500 text-white text-[10px] px-1.5 py-0 font-bold">ADS</Badge>}
              <p className="font-bold text-sm truncate">{contact.nome}</p>
            </div>

            {/* Telefone + instância */}
            <div className="flex items-center gap-1 mt-1 text-xs text-muted-foreground">
              <Phone className="w-3 h-3" />
              <span>Linha: {contact.instancias?.numero_final || '—'}</span>
            </div>

            {/* Tempo no estado + tentativa */}
            {(stateInfo.time || stateInfo.tentativa) && (
              <div className="flex items-center gap-2 mt-1.5 text-xs">
                {stateInfo.time && (
                  <span className="flex items-center gap-1 text-muted-foreground">
                    <Clock className="w-3 h-3" /> {stateInfo.time}
                  </span>
                )}
                {stateInfo.tentativa && (
                  <Badge variant="outline" className="text-[10px] px-1.5 py-0">
                    {stateInfo.tentativa}
                  </Badge>
                )}
              </div>
            )}

            {/* Motivo do suporte */}
            {column === 'suporte' && contact.suporte_motivo && (
              <p className="text-xs text-blue-600 mt-1 flex items-center gap-1">
                <AlertCircle className="w-3 h-3" /> {contact.suporte_motivo}
              </p>
            )}
          </div>

          {/* Ações */}
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => copyPhone(contact.telefone || '')}>
              <Copy className="w-3 h-3" />
            </Button>
            {canDelete && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="h-7 w-7"><MoreVertical className="w-3 h-3" /></Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent>
                  <DropdownMenuItem onClick={() => setDeleteTarget(contact)} className="text-destructive">
                    <Trash2 className="w-3 h-3 mr-2" /> Banir (NUNCA_MAIS)
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            )}
          </div>
        </div>

        {/* Botão Suporte Realizado (apenas coluna suporte) */}
        {column === 'suporte' && (
          <Button
            size="sm"
            className="mt-2 w-full min-h-[36px] bg-sf-green hover:bg-sf-green/90 text-primary-foreground"
            onClick={() => setSuporteTarget(contact)}
          >
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
  const [filter, setFilter] = useState<string>('');
  const [deleteTarget, setDeleteTarget] = useState<Contact | null>(null);
  const [suporteTarget, setSuporteTarget] = useState<Contact | null>(null);
  const [draggedCard, setDraggedCard] = useState<string | null>(null);

  const canDeleteCard = (profile as any)?.pode_excluir_card !== false;
  const canSwitch = profile?.acesso_kanban === 'todos';

  // Instâncias ativas (exclui admin)
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

  // Define filtro inicial
  useEffect(() => {
    if (!filter && instancias.length > 0) {
      setFilter(instancias[0].id);
    }
  }, [instancias, filter]);

  // Visible states (mapeados nas 5 colunas)
  const VISIBLE_STATES = KANBAN_COLUMNS.map(c => c.key) as readonly string[];

  const { data: contacts = [], isLoading: loading } = useQuery({
    queryKey: ['kanban-v2', filter],
    enabled: !!filter,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('contatos')
        .select(`
          id, nome, telefone, canal_origem, canal_atual, instancia_id,
          created_at, updated_at, tag_kanban, tag_kanban_ate,
          ultima_interacao, ja_comprou,
          follow_up_tentativas, ativacao_tentativas,
          data_start, data_wait_follow_up, data_ultimo_follow_up,
          data_em_fechamento, data_ultimo_rmkt, data_suporte, suporte_motivo,
          instancias(nome, numero_final)
        `)
        .in('ultima_interacao', VISIBLE_STATES as string[]);

      if (error) {
        console.error('Erro ao carregar kanban:', error);
        return [];
      }

      const list = (data || []) as unknown as Contact[];
      // Filtra por instância: pega contatos atribuídos OU sem dono
      return list.filter(c => c.instancia_id === filter || c.instancia_id === null);
    },
    staleTime: 5 * 60 * 1000,
  });

  // Realtime subscription
  useEffect(() => {
    const channel = supabase.channel('kanban-v2-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'contatos' }, () => {
        queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [queryClient]);

  const getColumnContacts = (col: ColumnKey) => {
    return contacts.filter(c => c.ultima_interacao === col);
  };

  // Drag-and-drop entre colunas → UPDATE ultima_interacao
  const handleDrop = async (contactId: string, newColumn: ColumnKey) => {
    const contact = contacts.find(c => c.id === contactId);
    if (!contact || contact.ultima_interacao === newColumn) return;

    // Monta updates específicos baseado em transição
    const updates: any = {
      ultima_interacao: newColumn,
      updated_at: new Date().toISOString(),
    };

    // Atualiza data do estado de destino quando faz sentido
    const now = new Date().toISOString();
    switch (newColumn) {
      case 'wait_follow_up':
        updates.data_wait_follow_up = now;
        break;
      case 'em_fechamento':
        updates.data_em_fechamento = now;
        break;
      case 'suporte':
        updates.data_suporte = now;
        updates.suporte_motivo = 'manual_kanban';
        break;
    }

    await supabase.from('contatos').update(updates).eq('id', contactId);
    toast.success(`${contact.nome} → ${KANBAN_COLUMNS.find(c => c.key === newColumn)?.label}`);
    queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
  };

  // Banir contato (NUNCA_MAIS)
  const handleDelete = async () => {
    if (!deleteTarget) return;
    await supabase.from('contatos').update({
      ultima_interacao: 'NUNCA_MAIS',
      data_nunca_mais: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq('id', deleteTarget.id);
    await supabase.from('log_atividades').insert({
      usuario: profile?.nome || 'Desconhecido',
      acao: 'Baniu contato via Kanban (NUNCA_MAIS)',
      tabela_afetada: 'contatos',
      registro_id: deleteTarget.id,
      detalhe: deleteTarget.nome,
    });
    toast.success(`${deleteTarget.nome} banido — será deletado no próximo cron`);
    setDeleteTarget(null);
    queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
  };

  // Suporte Realizado → volta pro estado anterior baseado em canal/ja_comprou
  const handleSuporteRealizado = async () => {
    if (!suporteTarget) return;
    try {
      const returnState = computeReturnState(suporteTarget);
      const now = new Date().toISOString();
      const updates: any = {
        ultima_interacao: returnState,
        duvidas_consecutivas: 0,
        updated_at: now,
      };
      if (returnState === 'wait_follow_up') {
        updates.data_wait_follow_up = now;
      } else if (returnState === 'ativacao_contatos') {
        updates.data_ultimo_ativacao = now;
      }

      await supabase.from('contatos').update(updates).eq('id', suporteTarget.id);

      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Desconhecido',
        acao: `Suporte resolvido — retornou para ${returnState}`,
        tabela_afetada: 'contatos',
        registro_id: suporteTarget.id,
        detalhe: suporteTarget.nome,
      });

      toast.success(`Suporte finalizado! Estado: ${returnState}`);
      setSuporteTarget(null);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Erro ao processar: ' + err.message);
    }
  };

  const copyPhone = (phone: string) => {
    copyToClipboard(phone).then(success => {
      if (success) toast.success('Número copiado!');
      else toast.error('Falha ao copiar');
    });
  };

  if (loading) return <Skeleton className="h-96" />;

  const renderCard = (contact: Contact, col: ColumnKey) => {
    // Não pode arrastar pra fora se em em_fechamento com sessão Typebot ativa
    const isDraggable = true;
    return (
      <KanbanCard
        key={contact.id}
        contact={contact}
        column={col}
        canDelete={canDeleteCard}
        isDraggable={isDraggable}
        draggedCard={draggedCard}
        setDraggedCard={setDraggedCard}
        setDeleteTarget={setDeleteTarget}
        setSuporteTarget={setSuporteTarget}
        copyPhone={copyPhone}
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
                <SelectItem key={i.id} value={i.id}>Instância {i.nome}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}
      </div>

      <div className="flex gap-4 overflow-x-auto kanban-scroll pb-4" style={{ minHeight: 500 }}>
        {KANBAN_COLUMNS.map(({ key, label, accent }) => {
          const colContacts = getColumnContacts(key);
          return (
            <div
              key={key}
              className={cn('flex-shrink-0 w-72 bg-muted/50 rounded-lg border-t-4', accent)}
              onDragOver={e => e.preventDefault()}
              onDrop={e => {
                e.preventDefault();
                const id = e.dataTransfer.getData('contactId');
                if (id) handleDrop(id, key);
              }}
            >
              <div className="p-3 border-b border-border">
                <div className="flex items-center justify-between">
                  <h3 className="font-bold text-sm">{label}</h3>
                  <Badge variant="secondary" className="text-xs">{colContacts.length}</Badge>
                </div>
              </div>
              <div className="p-2 space-y-2 max-h-[60vh] overflow-y-auto">
                {colContacts.length === 0 && (
                  <p className="text-xs text-muted-foreground text-center py-4">Nenhum card</p>
                )}
                {colContacts.map(contact => renderCard(contact, key))}
              </div>
            </div>
          );
        })}
      </div>

      {/* Confirmação de banimento */}
      <AlertDialog open={!!deleteTarget} onOpenChange={() => setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Banir contato</AlertDialogTitle>
            <AlertDialogDescription>
              {deleteTarget?.nome} será marcado como NUNCA_MAIS e excluído permanentemente no próximo cron diário.
              Esta ação não pode ser desfeita.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-destructive text-destructive-foreground">
              Banir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Confirmação de suporte realizado */}
      <AlertDialog open={!!suporteTarget} onOpenChange={() => setSuporteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Suporte realizado</AlertDialogTitle>
            <AlertDialogDescription>
              Marcar suporte como realizado para {suporteTarget?.nome}?
              <br /><br />
              <strong>Retorno:</strong> {suporteTarget ? computeReturnState(suporteTarget) : '—'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleSuporteRealizado} className="bg-sf-green text-primary-foreground">
              Confirmar
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

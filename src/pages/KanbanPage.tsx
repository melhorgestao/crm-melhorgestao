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
import { Copy, MoreVertical, Trash2, Phone, CheckCircle, AlertCircle, Clock, MessageSquare, X } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { cn, copyToClipboard } from '@/lib/utils';
import { findConversationByPhone } from '@/lib/chatwootApi';
import { FechamentoVendaModal } from '@/components/kanban/FechamentoVendaModal';

// 4 colunas do Kanban derivadas de ultima_interacao.
// Follow-Up unifica 2 estados (wait_follow_up + follow_up) — distinção fica
// na tag do card (WAIT vs F-UP).
const KANBAN_COLUMNS = [
  { key: 'follow_up',      label: 'FOLLOW-UP', accent: 'border-t-orange-500' },
  { key: 'rmkt',           label: 'RMKT',      accent: 'border-t-purple-500' },
  { key: 'em_fechamento',  label: 'FECHAMENTO', accent: 'border-t-primary' },
  { key: 'suporte',        label: 'SUPORTE',   accent: 'border-t-blue-500' },
] as const;

type ColumnKey = typeof KANBAN_COLUMNS[number]['key'];

// Estados internos que vão pra cada coluna do Kanban.
const COLUMN_STATES: Record<ColumnKey, readonly string[]> = {
  follow_up:     ['wait_follow_up', 'follow_up'],
  rmkt:          ['rmkt'],
  em_fechamento: ['em_fechamento'],
  suporte:       ['suporte'],
};

// Gaps de follow_up por tentativa (igual claim_proximo_lead_followup):
// tentativa 0 → 24h, 1 → 3d, 2 → 7d. Usado pra ordenar WAIT por
// proximidade do próximo disparo (quem está mais perto = topo).
const FOLLOW_UP_GAPS_MS = [
  24 * 3600 * 1000,
  3  * 24 * 3600 * 1000,
  7  * 24 * 3600 * 1000,
] as const;

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
  instancias?: { nome: string; numero: string } | null;
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
  draggedCard, setDraggedCard, setDeleteTarget, setSuporteTarget, setVendaTarget, sairFechamento, copyPhone, openChatwoot
}: {
  contact: Contact;
  column: ColumnKey;
  canDelete: boolean;
  isDraggable: boolean;
  draggedCard: string | null;
  setDraggedCard: (id: string | null) => void;
  setDeleteTarget: (c: Contact) => void;
  setSuporteTarget: (c: Contact) => void;
  setVendaTarget: (c: Contact) => void;
  sairFechamento: (c: Contact) => void;
  copyPhone: (p: string) => void;
  openChatwoot: (telefone: string) => void;
}) => {
  const activeTag = contact.tag_kanban &&
    (!contact.tag_kanban_ate || new Date(contact.tag_kanban_ate) > new Date())
    ? contact.tag_kanban : null;

  // Determina tempo "no estado" e tentativa pra exibir.
  // Coluna 'follow_up' cobre 2 estados internos — checa ultima_interacao.
  const realState = contact.ultima_interacao || '';
  const stateInfo = (() => {
    if (column === 'follow_up') {
      if (realState === 'follow_up') {
        return {
          time: contact.data_ultimo_follow_up ? timeAgo(contact.data_ultimo_follow_up) : null,
          tentativa: formatTentativa(contact.follow_up_tentativas, 3),
          label: 'disparado',
        };
      }
      // wait_follow_up
      return {
        time: contact.data_wait_follow_up ? timeAgo(contact.data_wait_follow_up) : null,
        tentativa: formatTentativa(contact.follow_up_tentativas, 3),
        label: 'no aguardo',
      };
    }
    switch (column) {
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
  // Suporte tem 3 níveis de urgência por idade do card
  const horasNoSuporte = column === 'suporte' && contact.data_suporte
    ? (Date.now() - new Date(contact.data_suporte).getTime()) / (3600 * 1000)
    : 0;
  const suporteNivel: 'ok' | 'atrasado' | 'urgente' =
    horasNoSuporte >= 48 ? 'urgente'
    : horasNoSuporte >= 24 ? 'atrasado'
    : 'ok';
  const isUrgent = suporteNivel === 'urgente';
  const suporteLabel = horasNoSuporte >= 24
    ? `${Math.floor(horasNoSuporte / 24)}d ${Math.floor(horasNoSuporte % 24)}h no suporte`
    : horasNoSuporte >= 1 ? `${Math.floor(horasNoSuporte)}h no suporte`
    : '';

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
        suporteNivel === 'atrasado' && 'border-2 border-amber-500',
        suporteNivel === 'urgente'  && 'animate-pulse border-2 border-destructive'
      )}
    >
      <CardContent className="p-3">
        <div className="flex items-start justify-between">
          <div className="flex-1 min-w-0">
            {/* Tags + nome */}
            <div className="flex items-center gap-1 flex-wrap">
              {column === 'follow_up' && realState === 'follow_up' && (
                <Badge className="bg-orange-500 text-white text-[10px] px-1.5 py-0 font-bold">F-UP</Badge>
              )}
              {column === 'follow_up' && realState === 'wait_follow_up' && (
                <Badge className="bg-amber-400 text-black text-[10px] px-1.5 py-0 font-bold">WAIT</Badge>
              )}
              {activeTag === 'NEW' && <Badge className="bg-blue-500 text-white text-[10px] px-1.5 py-0 font-bold">NEW</Badge>}
              {activeTag === 'VIP' && <Badge className="bg-yellow-500 text-black text-[10px] px-1.5 py-0 font-bold">VIP</Badge>}
              {activeTag === 'BUYER' && <Badge className="bg-emerald-500 text-white text-[10px] px-1.5 py-0 font-bold">BUYER</Badge>}
              {activeTag === 'REP' && <Badge className="bg-blue-500 text-white text-[10px] px-1.5 py-0 font-bold">REP</Badge>}
              {activeTag === 'ADS' && <Badge className="bg-purple-500 text-white text-[10px] px-1.5 py-0 font-bold">ADS</Badge>}
              <p className="font-bold text-sm truncate">{contact.nome}</p>
            </div>

            {/* Telefone + instância */}
            <div className="flex items-center gap-1 mt-1 text-xs text-muted-foreground">
              <Phone className="w-3 h-3" />
              <span>{contact.instancias?.nome || 'sem instância'}</span>
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

            {/* Tempo no suporte com cor por urgência */}
            {column === 'suporte' && suporteLabel && (
              <p className={cn(
                'text-[11px] mt-1 font-medium flex items-center gap-1',
                suporteNivel === 'urgente'  ? 'text-destructive' :
                suporteNivel === 'atrasado' ? 'text-amber-600' :
                'text-muted-foreground'
              )}>
                <Clock className="w-3 h-3" /> {suporteLabel}
              </p>
            )}
          </div>

          {/* Ações */}
          <div className="flex items-center gap-1">
            <Button
              variant="ghost" size="icon" className="h-7 w-7"
              title="Abrir conversa no Chatwoot"
              onClick={() => openChatwoot(contact.telefone || '')}
            >
              <MessageSquare className="w-3 h-3" />
            </Button>
            <Button
              variant="ghost" size="icon" className="h-7 w-7"
              title="Copiar telefone"
              onClick={() => copyPhone(contact.telefone || '')}
            >
              <Copy className="w-3 h-3" />
            </Button>
          </div>
        </div>

        {/* Suporte: [✓] realizado — ícone discreto */}
        {column === 'suporte' && (
          <div className="mt-2 flex justify-end">
            <Button
              size="icon"
              variant="outline"
              className="h-7 w-7 text-sf-green border-sf-green/40 hover:bg-sf-green/10"
              title="Suporte realizado"
              onClick={() => setSuporteTarget(contact)}
            >
              <CheckCircle className="w-4 h-4" />
            </Button>
          </div>
        )}

        {/* Fechamento: [✓] abre Venda · [X] sai de fechamento — ícones discretos */}
        {column === 'em_fechamento' && (
          <div className="mt-2 flex gap-1.5 justify-end">
            <Button
              size="icon"
              variant="outline"
              className="h-7 w-7 text-sf-green border-sf-green/40 hover:bg-sf-green/10"
              title="Sinal certo — registrar venda"
              onClick={() => setVendaTarget(contact)}
            >
              <CheckCircle className="w-4 h-4" />
            </Button>
            <Button
              size="icon"
              variant="outline"
              className="h-7 w-7 text-destructive border-destructive/40 hover:bg-destructive/10"
              title="Sair de fechamento (volta ao estado anterior)"
              onClick={() => sairFechamento(contact)}
            >
              <X className="w-4 h-4" />
            </Button>
          </div>
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
  const [vendaTarget, setVendaTarget] = useState<Contact | null>(null);
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

  // Define filtro inicial — começa em "Todas" se houver >1 instância
  useEffect(() => {
    if (!filter && instancias.length > 0) {
      setFilter(instancias.length > 1 ? 'all' : instancias[0].id);
    }
  }, [instancias, filter]);

  // Abre conversa no Chatwoot via Edge Function (evita CORS).
  const openChatwoot = async (telefone: string) => {
    if (!telefone) { toast.error('Sem telefone'); return; }
    const found = await findConversationByPhone({ url: '', accountId: '', apiToken: '' }, telefone);
    if (!found?.url) {
      toast.error('Chatwoot indisponível — veja console (F12)');
      return;
    }
    if (found.fallback) toast.info('Conversa não encontrada — abrindo busca');
    window.open(found.url, '_blank');
  };

  // Estados que aparecem em alguma coluna do Kanban.
  // Pode ser mais que o número de colunas (Follow-Up cobre 2 estados).
  const VISIBLE_STATES = KANBAN_COLUMNS.flatMap(c => COLUMN_STATES[c.key]);

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
          instancias(nome, numero)
        `)
        .in('ultima_interacao', VISIBLE_STATES as string[]);

      if (error) {
        console.error('Erro ao carregar kanban:', error);
        return [];
      }

      const list = (data || []) as unknown as Contact[];
      // 'all' → retorna tudo unificado. Caso contrário, filtra por instância.
      if (filter === 'all') return list;
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
    const states = COLUMN_STATES[col];
    const list = contacts.filter(c => states.includes(c.ultima_interacao || ''));

    // Coluna SUPORTE: ordena por data_suporte ASC (mais antigos no topo).
    if (col === 'suporte') {
      return list.sort((a, b) => {
        const ta = a.data_suporte ? new Date(a.data_suporte).getTime() : Infinity;
        const tb = b.data_suporte ? new Date(b.data_suporte).getTime() : Infinity;
        return ta - tb;
      });
    }

    // Coluna FOLLOW-UP: F-UP (já disparados) no topo. Depois WAIT ordenados
    // por proximidade do próximo disparo (quanto MENOS tempo faltar pro gap,
    // mais alto). Tempo até disparo = data_wait_follow_up + gap_da_tentativa.
    if (col === 'follow_up') {
      const now = Date.now();
      const tempoAteDisparo = (c: Contact): number => {
        if (c.ultima_interacao === 'follow_up') return -Infinity; // sempre topo
        if (!c.data_wait_follow_up) return Infinity;
        const tent = Math.min(c.follow_up_tentativas ?? 0, FOLLOW_UP_GAPS_MS.length - 1);
        const gap = FOLLOW_UP_GAPS_MS[tent];
        const proxDisparo = new Date(c.data_wait_follow_up).getTime() + gap;
        return proxDisparo - now;
      };
      return list.sort((a, b) => tempoAteDisparo(a) - tempoAteDisparo(b));
    }

    return list;
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

    // Atualiza data do estado de destino quando faz sentido.
    // Coluna 'follow_up' tem 2 estados internos — drag-drop está desativado,
    // então tratamento default usa data_wait_follow_up.
    const now = new Date().toISOString();
    switch (newColumn) {
      case 'follow_up':
        updates.ultima_interacao = 'wait_follow_up';
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

  // Botão X do fechamento → sai de em_fechamento, volta ao estado anterior
  const sairFechamento = async (c: Contact) => {
    try {
      const { data, error } = await supabase.rpc('sair_fechamento_contato' as any, { p_contato_id: c.id });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'falha desconhecida');
      toast.success(`${c.nome} saiu de fechamento → ${r.destino}`);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || err));
    }
  };

  // Suporte Finalizado → chama RPC que restaura estado_antes_suporte
  // (cobre cliente, wait_follow_up, rmkt, follow_up, em_fechamento, etc).
  const handleSuporteRealizado = async () => {
    if (!suporteTarget) return;
    try {
      const { data, error } = await supabase.rpc('finalizar_suporte_contato' as any, {
        p_contato_id: suporteTarget.id,
      });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'falha desconhecida');

      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Desconhecido',
        acao: `Suporte finalizado via UI — destino: ${r.destino}`,
        tabela_afetada: 'contatos',
        registro_id: suporteTarget.id,
        detalhe: suporteTarget.nome,
      });

      toast.success(`Suporte finalizado! → ${r.destino}`);
      setSuporteTarget(null);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Erro ao finalizar suporte: ' + err.message);
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
    // Drag-drop manual DESABILITADO — estado do contato é gerenciado
    // exclusivamente pelo agent (router/closing) e por crons.
    // Movimentação manual quebrava regras automáticas (data_*, campanhas).
    // Pra forçar mudança de estado, use comandos /cliente, /sumiu, /banir, /voltar.
    const isDraggable = false;
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
        setVendaTarget={setVendaTarget}
        sairFechamento={sairFechamento}
        copyPhone={copyPhone}
        openChatwoot={openChatwoot}
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
              {instancias.length > 1 && <SelectItem value="all">Todas</SelectItem>}
              {instancias.map(i => (
                <SelectItem key={i.id} value={i.id}>{i.nome}</SelectItem>
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

      {/* Modal de Venda (botão Sinal Certo no fechamento) */}
      <FechamentoVendaModal
        open={!!vendaTarget}
        onClose={() => setVendaTarget(null)}
        contato={vendaTarget}
        onDone={() => queryClient.invalidateQueries({ queryKey: ['kanban-v2'] })}
      />
    </div>
  );
}

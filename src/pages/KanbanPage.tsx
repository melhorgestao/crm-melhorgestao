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
import { Copy, MoreVertical, Trash2, Phone, CheckCircle, AlertCircle, Clock, MessageSquare, X, Headset, Play, ShoppingCart, RefreshCw, Package, Minus, CalendarClock, Hourglass, ChevronDown } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Calendar } from '@/components/ui/calendar';
import { ptBR } from 'date-fns/locale';
import { cn, copyToClipboard } from '@/lib/utils';
import { findConversationByPhone } from '@/lib/chatwootApi';
import { FechamentoVendaModal } from '@/components/kanban/FechamentoVendaModal';
import { PedidoDetailModal } from '@/components/pedidos/PedidoDetailModal';

// 4 colunas do Kanban derivadas de ultima_interacao.
// Follow-Up unifica 2 estados (wait_follow_up + follow_up) — distinção fica
// na tag do card (WAIT vs F-UP).
const KANBAN_COLUMNS = [
  { key: 'suporte',        label: 'SUPORTE',   accent: 'border-t-blue-500' },
  { key: 'follow_up',      label: 'FOLLOW-UP', accent: 'border-t-orange-500' },
  { key: 'em_fechamento',  label: 'FECHAMENTO', accent: 'border-t-primary' },
  { key: 'rmkt',           label: 'RMKT',      accent: 'border-t-purple-500' },
] as const;

type ColumnKey = typeof KANBAN_COLUMNS[number]['key'];

// Estados internos que vão pra cada coluna do Kanban.
const COLUMN_STATES: Record<ColumnKey, readonly string[]> = {
  follow_up:     ['wait_follow_up', 'follow_up', 'wait_follow_up_custom'],
  rmkt:          ['rmkt'],
  em_fechamento: ['em_fechamento'],
  suporte:       ['suporte'],
};

// Motivos pré-definidos do suporte / aguardando fechamento (dropdown no card).
// "Personalizado" abre um campo de texto livre.
const MOTIVOS_PRESET = ['Analisar receita', 'Reclamação', 'Aguardando resposta'] as const;

// Formata "há Xh" / "há Xd Yh" a partir de uma data. Usado nos timers de
// FECHAMENTO ("Em fechamento há Xh") e AGUARDANDO ("Aguardando há Xh").
function fmtHoras(dateStr: string | null | undefined, prefix: string): string | null {
  if (!dateStr) return null;
  const h = (Date.now() - new Date(dateStr).getTime()) / 3600000;
  if (h < 1) return `${prefix} <1h`;
  if (h < 24) return `${prefix} ${Math.floor(h)}h`;
  return `${prefix} ${Math.floor(h / 24)}d ${Math.floor(h % 24)}h`;
}

// Gaps de follow_up por tentativa (igual claim_proximo_lead_followup):
// tentativa 0 → dispara já (o 4h de silêncio já foi no start->wait), 1 → 3d,
// 2 → 7d. Usado pra ordenar WAIT por proximidade do próximo disparo
// (quem está mais perto = topo). Tent 0 = 0 → sempre "no ponto", vai pro topo.
const FOLLOW_UP_GAPS_MS = [
  0,
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
  data_ultima_entrada?: string | null;
  data_wait_follow_up?: string | null;
  followup_custom_em?: string | null;
  data_ultimo_follow_up?: string | null;
  data_em_fechamento?: string | null;
  data_ultimo_rmkt?: string | null;
  data_suporte?: string | null;
  suporte_motivo?: string | null;
  fechamento_aguardando?: boolean | null;
  bot_pausado_ate?: string | null;
  ultima_venda_em?: string | null;
  qtd_ultimo_pedido?: number | null;
  rmkt_consecutive_silenciosos?: number | null;
  proxima_rmkt_em?: string | null;
  ultimo_pedido_id?: string | null;
  ultimo_pedido_order?: number | null;
  _rmktWait?: boolean;
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

// Preenche o template pro disparo manual: {nome}/{{nome}} → 1º nome do contato,
// demais placeholders {{...}} viram vazio (não mostrar cru na cópia).
function preencherTemplate(texto: string, nomeCompleto?: string | null): string {
  const primeiro = String(nomeCompleto || '').trim().split(/\s+/)[0] || 'amigo(a)';
  return String(texto || '')
    .replace(/\{\{?\s*nome\s*\}?\}/gi, primeiro)
    .replace(/\{\{[^}]*\}\}/g, '')
    .trim();
}

// Quando o PRÓXIMO follow-up deste lead fica apto (mesma cadência do claim):
//   tent 0 → 4h de silêncio real (data_ultima_entrada)
//   tent 1 → 3 dias do último envio; tent 2 → 7 dias.
// Retorna epoch ms; 0 = já apto (sem data base pra comparar).
function nextFollowupEligibleAt(c: Contact): number {
  const tent = c.follow_up_tentativas ?? 0;
  if (tent <= 0) {
    const base = c.data_ultima_entrada || c.data_wait_follow_up || c.data_start;
    return base ? new Date(base).getTime() + 4 * 3600_000 : 0;
  }
  const base = c.data_ultimo_follow_up || c.data_wait_follow_up;
  const days = tent === 1 ? 3 : 7;
  return base ? new Date(base).getTime() + days * 86400_000 : 0;
}

// Elegibilidade do disparo manual: RMKT sempre liberado (cadência própria);
// follow-up respeita a cadência acima.
function dispatchEligible(t: { contact: Contact; tipo: 'followup' | 'rmkt' } | null): { apto: boolean; faltamMs: number } {
  if (!t || t.tipo === 'rmkt') return { apto: true, faltamMs: 0 };
  const faltamMs = nextFollowupEligibleAt(t.contact) - Date.now();
  return { apto: faltamMs <= 0, faltamMs: Math.max(0, faltamMs) };
}

// "2d 5h" / "5h 30min" / "12min"
function formatCountdown(ms: number): string {
  const totalMin = Math.max(0, Math.ceil(ms / 60000));
  const d = Math.floor(totalMin / 1440);
  const h = Math.floor((totalMin % 1440) / 60);
  const m = totalMin % 60;
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}min`;
  return `${m}min`;
}

const KanbanCard = memo(({
  contact, column, canDelete, isDraggable,
  draggedCard, setDraggedCard, setDeleteTarget, setSuporteTarget, setVendaTarget, setPararTarget,
  pausarBot, reativarBot, copyPhone, openChatwoot,
  collapsed, toggleCollapsed, openPedido, onDisparoManual, onAgendarCustom, onFinalizarFechamento, onEditMotivo,
  onMoverAguardando, onFinalizarAguardando
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
  setPararTarget: (t: { contact: Contact; mode: 'followup' | 'rmkt' }) => void;
  pausarBot: (c: Contact) => void;
  reativarBot: (c: Contact) => void;
  copyPhone: (p: string) => void;
  openChatwoot: (telefone: string) => void;
  collapsed: boolean;
  toggleCollapsed: (id: string) => void;
  openPedido: (pedidoId: string | null, contatoId?: string) => void;
  onDisparoManual: (c: Contact, tipo: 'followup' | 'rmkt') => void;
  onAgendarCustom: (c: Contact) => void;
  onFinalizarFechamento: (c: Contact) => void;
  onEditMotivo: (c: Contact, motivo: string) => void;
  onMoverAguardando: (c: Contact) => void;
  onFinalizarAguardando: (c: Contact) => void;
}) => {
  // Aguardando fechamento = ultima_interacao='suporte' + flag. Renderiza na
  // coluna FECHAMENTO (column='em_fechamento') mas com comportamento de suporte.
  const isAguardando = contact.fechamento_aguardando === true;
  // Edição inline do motivo do suporte (duplo clique no texto azul)
  const [editandoMotivo, setEditandoMotivo] = useState(false);
  const [motivoDraft, setMotivoDraft] = useState('');
  // Bot está pausado se bot_pausado_ate está no futuro
  const botPausado = !!contact.bot_pausado_ate && new Date(contact.bot_pausado_ate).getTime() > Date.now();
  const activeTag = contact.tag_kanban &&
    (!contact.tag_kanban_ate || new Date(contact.tag_kanban_ate) > new Date())
    ? contact.tag_kanban : null;
  // Representante: detectado pelo canal (fonte real) OU pela tag. REP prevalece
  // sobre BUYER — um representante nunca deve exibir tag de comprador.
  // Etiquetas de CANAL saem do canal_atual (situação vigente do contato),
  // não de canal_origem nem de tag_kanban (tag expira e origem é histórica).
  const isRep  = contact.canal_atual === 'REP' || contact.canal_atual === 'C-REP';
  const isAds  = contact.canal_atual === 'ADS';
  // BUYER não é canal: vem do fato de já ter comprado (mais confiável que tag).
  const isBuyer = contact.ja_comprou === true;

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
      // wait_follow_up_custom — prazo prometido pelo cliente. Mostra a data
      // combinada ("volta 05/08"), não "sumiu há".
      if (realState === 'wait_follow_up_custom') {
        const d = contact.followup_custom_em ? new Date(contact.followup_custom_em) : null;
        const dataStr = d
          ? d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
          : null;
        return {
          time: dataStr ? `Volta ${dataStr}` : null,
          tentativa: null,
          label: 'prazo do cliente',
        };
      }
      // wait_follow_up — "Sumiu há X" = tempo desde a ÚLTIMA MENSAGEM DO LEAD
      // (data_ultima_entrada), não desde que entrou na coluna. Assim, ao chegar
      // com 4h de silêncio mostra "Sumiu há 4h" (não "Agora"), e se o lead
      // responder zera pra "Agora". Fallback pro que existir.
      const silencioDesde = contact.data_ultima_entrada || contact.data_wait_follow_up || contact.data_start;
      return {
        time: silencioDesde ? timeAgo(silencioDesde) : null,
        tentativa: formatTentativa(contact.follow_up_tentativas, 3),
        label: 'no aguardo',
      };
    }
    switch (column) {
      case 'rmkt': {
        // RMKT: mostra tempo desde a ÚLTIMA COMPRA (não "sumiu há").
        const d = contact.ultima_venda_em
          ? Math.floor((Date.now() - new Date(contact.ultima_venda_em).getTime()) / 86400000)
          : null;
        return {
          time: d != null ? `Comprou há ${d} dia${d !== 1 ? 's' : ''}` : null,
          tentativa: formatTentativa(contact.rmkt_consecutive_silenciosos, 3),
          label: contact._rmktWait ? 'aguardando disparo' : 'disparado',
        };
      }
      case 'em_fechamento':
        // Aguardando fechamento (suporte + flag): "Aguardando há Xh".
        if (isAguardando) {
          return {
            time: fmtHoras(contact.data_suporte, 'Aguardando há'),
            tentativa: null,
            label: contact.suporte_motivo || 'aguardando fechamento',
          };
        }
        // Em negociação: "Em fechamento há Xh" (não mais "sumiu há").
        return {
          time: fmtHoras(contact.data_em_fechamento, 'Em fechamento há'),
          tentativa: null,
          label: 'em negociação',
        };
      case 'suporte':
        // Sem "sumiu há" no suporte — o timer "Xh no suporte" (abaixo) já cobre.
        return {
          time: null,
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
    : `${Math.max(1, Math.floor(horasNoSuporte * 60))}min no suporte`;

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
            {/* Tags + contador X/3 (junto da tag principal) + nome */}
            <div className="flex items-center gap-1 flex-wrap">
              {/* Botão minimizar/expandir (- / +) — deixa o card fininho */}
              <button
                type="button"
                onClick={(e) => { e.stopPropagation(); toggleCollapsed(contact.id); }}
                className="text-muted-foreground hover:text-foreground transition-colors -ml-0.5 mr-0.5 rounded hover:bg-muted/40 leading-none"
                title={collapsed ? 'Expandir' : 'Minimizar card'}
              >
                {collapsed ? <span className="text-xs font-bold px-1">+</span> : <Minus className="w-3 h-3" />}
              </button>

              {/* Clicar na tag = registrar disparo manual (X/3) — trabalho
                  manual enquanto o bot está off. */}
              {column === 'follow_up' && realState === 'follow_up' && (
                <Badge role="button" title="Registrar follow-up manual" onClick={(e) => { e.stopPropagation(); onDisparoManual(contact, 'followup'); }}
                  className="bg-orange-500 text-white text-[10px] px-1.5 py-0 font-bold cursor-pointer hover:brightness-110">
                  F-UP{stateInfo.tentativa ? ` ${stateInfo.tentativa}` : ''}
                </Badge>
              )}
              {column === 'follow_up' && realState === 'wait_follow_up' && (
                <Badge role="button" title="Registrar follow-up manual" onClick={(e) => { e.stopPropagation(); onDisparoManual(contact, 'followup'); }}
                  className="bg-amber-400 text-black text-[10px] px-1.5 py-0 font-bold cursor-pointer hover:brightness-110">
                  WAIT{stateInfo.tentativa ? ` ${stateInfo.tentativa}` : ''}
                </Badge>
              )}
              {column === 'follow_up' && realState === 'wait_follow_up_custom' && (
                <Badge title="Retorno agendado no prazo do cliente"
                  className="bg-violet-500 text-white text-[10px] px-1.5 py-0 font-bold">
                  F-UP Custom
                </Badge>
              )}
              {column === 'rmkt' && contact._rmktWait && (
                <Badge role="button" title="Registrar RMKT manual" onClick={(e) => { e.stopPropagation(); onDisparoManual(contact, 'rmkt'); }}
                  className="bg-blue-500 text-white text-[10px] px-1.5 py-0 font-bold cursor-pointer hover:brightness-110">
                  WAIT{stateInfo.tentativa ? ` ${stateInfo.tentativa}` : ''}
                </Badge>
              )}
              {column === 'rmkt' && !contact._rmktWait && (
                <Badge role="button" title="Registrar RMKT manual" onClick={(e) => { e.stopPropagation(); onDisparoManual(contact, 'rmkt'); }}
                  className="bg-purple-500 text-white text-[10px] px-1.5 py-0 font-bold cursor-pointer hover:brightness-110">
                  RMKT{stateInfo.tentativa ? ` ${stateInfo.tentativa}` : ''}
                </Badge>
              )}
              {activeTag === 'NEW' && <Badge className="bg-blue-500 text-white text-[10px] px-1.5 py-0 font-bold">NEW</Badge>}
              {activeTag === 'VIP' && <Badge className="bg-yellow-500 text-black text-[10px] px-1.5 py-0 font-bold">VIP</Badge>}
              {/* REP prevalece: representante (por canal ou tag) mostra REP,
                  NUNCA BUYER. BUYER também é redundante na coluna RMKT. */}
              {isRep ? (
                <Badge className="bg-blue-500 text-white text-[10px] px-1.5 py-0 font-bold">REP</Badge>
              ) : (
                isBuyer && column !== 'rmkt' && <Badge className="bg-emerald-500 text-white text-[10px] px-1.5 py-0 font-bold">BUYER</Badge>
              )}
              {/* ADS só na coluna FECHAMENTO — é onde a origem do lead importa
                  pra decisão de venda. Nas outras colunas polui o card. */}
              {isAds && column === 'em_fechamento' && <Badge className="bg-purple-500 text-white text-[10px] px-1.5 py-0 font-bold">ADS</Badge>}
              <p className="font-bold text-sm truncate">{contact.nome}</p>
            </div>

            {!collapsed && (
              <>
                {/* Telefone (clicável = copia) + instância */}
                <div className="flex items-center gap-1 mt-1 text-xs text-muted-foreground">
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); copyPhone(contact.telefone || ''); }}
                    className="hover:text-foreground transition-colors flex items-center gap-1"
                    title="Copiar telefone"
                  >
                    <Phone className="w-3 h-3" />
                  </button>
                  <span>{contact.instancias?.nome || 'sem instância'}</span>
                </div>

                {/* Tempo no estado + (RMKT) ícone caixa com qtd → abre popup pedido */}
                {stateInfo.time && (
                  <div className="flex items-center gap-2 mt-1.5 text-xs">
                    <span className="flex items-center gap-1 text-muted-foreground">
                      <Clock className="w-3 h-3" /> {stateInfo.time}
                    </span>
                    {column === 'rmkt' && contact.qtd_ultimo_pedido != null && contact.qtd_ultimo_pedido > 0 && (
                      <button
                        type="button"
                        onClick={(e) => { e.stopPropagation(); openPedido(contact.ultimo_pedido_id || null, contact.id); }}
                        className="flex items-center gap-0.5 text-muted-foreground hover:text-foreground transition-colors"
                        title={contact.ultimo_pedido_order ? `Ver Pedido #${contact.ultimo_pedido_order}` : 'Ver último pedido'}
                      >
                        <Package className="w-3 h-3" />
                        <span className="tabular-nums">{contact.qtd_ultimo_pedido}</span>
                      </button>
                    )}
                  </div>
                )}
              </>
            )}

            {!collapsed && (column === 'suporte' || isAguardando) && (
              editandoMotivo ? (
                <div className="mt-1 flex items-center gap-1">
                  <AlertCircle className="w-3 h-3 text-blue-600 shrink-0" />
                  <input
                    autoFocus
                    value={motivoDraft}
                    onChange={e => setMotivoDraft(e.target.value)}
                    onClick={e => e.stopPropagation()}
                    onBlur={() => { onEditMotivo(contact, motivoDraft); setEditandoMotivo(false); }}
                    onKeyDown={e => {
                      if (e.key === 'Enter') { e.preventDefault(); onEditMotivo(contact, motivoDraft); setEditandoMotivo(false); }
                      if (e.key === 'Escape') { e.preventDefault(); setEditandoMotivo(false); }
                    }}
                    placeholder="motivo personalizado…"
                    maxLength={60}
                    className="flex-1 min-w-0 text-xs text-blue-700 bg-blue-50 dark:bg-blue-950/40 border border-blue-300 rounded px-1.5 py-0.5 outline-none focus:ring-1 focus:ring-blue-400"
                  />
                </div>
              ) : (
                <div className="mt-1 flex items-center gap-1">
                  <AlertCircle className="w-3 h-3 text-blue-600 shrink-0" />
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <button
                        type="button"
                        onClick={e => e.stopPropagation()}
                        title="Trocar motivo"
                        className="flex-1 min-w-0 text-left text-xs text-blue-600 flex items-center gap-1 cursor-pointer rounded px-0.5 -mx-0.5 hover:bg-blue-50 dark:hover:bg-blue-950/30 transition-colors"
                      >
                        <span className="truncate">
                          {contact.suporte_motivo || <span className="italic text-blue-400">definir motivo…</span>}
                        </span>
                        <ChevronDown className="w-3 h-3 shrink-0 opacity-60" />
                      </button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="start" onClick={e => e.stopPropagation()}>
                      {MOTIVOS_PRESET.map(m => (
                        <DropdownMenuItem key={m} onClick={() => onEditMotivo(contact, m)}>{m}</DropdownMenuItem>
                      ))}
                      <DropdownMenuItem
                        onClick={() => {
                          const atual = contact.suporte_motivo || '';
                          setMotivoDraft((MOTIVOS_PRESET as readonly string[]).includes(atual) ? '' : atual);
                          setEditandoMotivo(true);
                        }}
                      >
                        ✏️ Personalizado…
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              )
            )}

            {!collapsed && column === 'suporte' && suporteLabel && (
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

          {/* Ações — botões contextuais moram aqui pra manter altura padrão do card */}
          <div className="flex items-center gap-1">
            {/* Suporte: [✓] realizado · [🛒] registrar venda. Sem pause/play
                (bot já está pausado neste estado). */}
            {column === 'suporte' && (
              <>
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-sf-green hover:bg-sf-green/10"
                  title="Suporte realizado (reativa o bot)"
                  onClick={() => setSuporteTarget(contact)}
                >
                  <CheckCircle className="w-3.5 h-3.5" />
                </Button>
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-indigo-500 hover:bg-indigo-500/10"
                  title="Mover pra Aguardando fechamento (aguardando pagamento/data)"
                  onClick={() => onMoverAguardando(contact)}
                >
                  <Hourglass className="w-3.5 h-3.5" />
                </Button>
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-sf-green hover:bg-sf-green/10"
                  title="Registrar venda"
                  onClick={() => setVendaTarget(contact)}
                >
                  <ShoppingCart className="w-3.5 h-3.5" />
                </Button>
              </>
            )}
            {/* Agendar retorno manual (F-UP Custom). Só na coluna Follow-up —
                não faz sentido em Fechamento. */}
            {column === 'follow_up' && (
              <Button
                variant="ghost" size="icon"
                className={cn('h-7 w-7 hover:bg-violet-500/10',
                  realState === 'wait_follow_up_custom' ? 'text-violet-600' : 'text-muted-foreground hover:text-violet-600')}
                title={realState === 'wait_follow_up_custom' ? 'Editar retorno agendado (F-UP Custom)' : 'Agendar retorno (F-UP Custom)'}
                onClick={() => onAgendarCustom(contact)}
              >
                <CalendarClock className="w-3.5 h-3.5" />
              </Button>
            )}
            {/* Suporte/Reativar (comando /humano ↔ /voltar). Ícone de atendente
                com headset (mais claro que "pause"). Aguardando fechamento já
                está com o bot pausado (estado suporte) — não mostra headset. */}
            {column !== 'suporte' && !isAguardando && (
              botPausado ? (
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-sf-green hover:bg-sf-green/10"
                  title="Reativar bot (/voltar)"
                  onClick={() => reativarBot(contact)}
                >
                  <Play className="w-3.5 h-3.5" />
                </Button>
              ) : (
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-amber-600 hover:bg-amber-500/10"
                  title="Levar pro suporte — humano atendendo (/humano)"
                  onClick={() => pausarBot(contact)}
                >
                  <Headset className="w-3.5 h-3.5" />
                </Button>
              )
            )}
            {/* Fechamento — em negociação: [⏳] mover pra Aguardando fechamento ·
                [X] finaliza e retroage ao estado anterior (com confirmação). */}
            {column === 'em_fechamento' && !isAguardando && (
              <>
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-indigo-500 hover:bg-indigo-500/10"
                  title="Mover pra Aguardando fechamento (aguardando pagamento/data)"
                  onClick={() => onMoverAguardando(contact)}
                >
                  <Hourglass className="w-3.5 h-3.5" />
                </Button>
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:bg-destructive/10"
                  title="Finalizar fechamento — volta ao estado anterior"
                  onClick={() => onFinalizarFechamento(contact)}
                >
                  <X className="w-3.5 h-3.5" />
                </Button>
              </>
            )}
            {/* Aguardando fechamento: [🛒] registrar venda · [X] finaliza
                (não comprou) e volta ao estado anterior. */}
            {isAguardando && (
              <>
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-sf-green hover:bg-sf-green/10"
                  title="Registrar venda"
                  onClick={() => setVendaTarget(contact)}
                >
                  <ShoppingCart className="w-3.5 h-3.5" />
                </Button>
                <Button
                  variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:bg-destructive/10"
                  title="Finalizar aguardando — não comprou (volta ao estado anterior)"
                  onClick={() => onFinalizarAguardando(contact)}
                >
                  <X className="w-3.5 h-3.5" />
                </Button>
              </>
            )}
            {/* X = parar campanha (F-UP ou RMKT) deste contato.
                F-UP → volta pra Start (nunca-mais F-UP).
                RMKT → volta pra Cliente (nunca-mais RMKT até nova compra). */}
            {(column === 'follow_up' || column === 'rmkt') && (
              <Button
                variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:bg-destructive/10"
                title={column === 'rmkt' ? 'Parar RMKT deste contato' : 'Parar F-UP deste contato'}
                onClick={() => setPararTarget({ contact, mode: column === 'rmkt' ? 'rmkt' : 'followup' })}
              >
                <X className="w-3.5 h-3.5" />
              </Button>
            )}
            <Button
              variant="ghost" size="icon" className="h-7 w-7"
              title="Abrir conversa no Chatwoot"
              onClick={() => openChatwoot(contact.telefone || '')}
            >
              <MessageSquare className="w-3 h-3" />
            </Button>
          </div>
        </div>
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
  const [pararTarget, setPararTarget] = useState<{ contact: Contact; mode: 'followup' | 'rmkt' } | null>(null);
  const [disparoTarget, setDisparoTarget] = useState<{ contact: Contact; tipo: 'followup' | 'rmkt'; proxima: number } | null>(null);
  const [tplVars, setTplVars] = useState<string[]>([]);
  const [tplIdx, setTplIdx] = useState(0);
  const [draggedCard, setDraggedCard] = useState<string | null>(null);
  const [collapsedIds, setCollapsedIds] = useState<Set<string>>(new Set());
  const [pedidoAbertoId, setPedidoAbertoId] = useState<string | null>(null);
  // Filtro da coluna Follow-up: todos | custom | wait | 1 | 2 | 3 (tentativa)
  const [fupFiltro, setFupFiltro] = useState<'todos' | 'custom' | 'wait' | '1' | '2' | '3'>('todos');
  // Filtro da coluna Fechamento: todos | negociacao | aguardando
  const [fecFiltro, setFecFiltro] = useState<'todos' | 'negociacao' | 'aguardando'>('todos');
  // Agendamento manual F-UP Custom (calendário)
  const [agendarTarget, setAgendarTarget] = useState<Contact | null>(null);
  const [finalizarTarget, setFinalizarTarget] = useState<Contact | null>(null);
  // X no card de "aguardando fechamento" (não comprou → finaliza suporte)
  const [aguardandoTarget, setAguardandoTarget] = useState<Contact | null>(null);
  const [agendarDate, setAgendarDate] = useState<Date | undefined>(undefined);

  const toggleCollapsed = (id: string) => setCollapsedIds(prev => {
    const n = new Set(prev);
    if (n.has(id)) n.delete(id); else n.add(id);
    return n;
  });
  const openPedido = async (pedidoId: string | null, contatoId?: string) => {
    if (pedidoId) { setPedidoAbertoId(pedidoId); return; }
    if (!contatoId) return;
    // Sem ultimo_pedido_id na view (cards dispatched) → busca o último pedido.
    const { data } = await supabase.from('pedidos').select('id')
      .eq('contato_id', contatoId).neq('status_pedido', 'cancelado')
      .order('created_at', { ascending: false }).limit(1).maybeSingle();
    if (data?.id) setPedidoAbertoId(data.id);
    else toast.info('Nenhum pedido encontrado');
  };

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
    // Abre a aba SINCRONAMENTE dentro do gesto do clique — mobile (Safari/Chrome)
    // bloqueia window.open chamado depois de um await (fora do gesto).
    const win = window.open('', '_blank');
    const found = await findConversationByPhone({ url: '', accountId: '', apiToken: '' }, telefone);
    if (!found?.url) {
      win?.close();
      toast.error('Chatwoot indisponível — veja console (F12)');
      return;
    }
    if (found.fallback) toast.info('Conversa não encontrada — abrindo busca');
    if (win) win.location.href = found.url;
    else window.open(found.url, '_blank'); // fallback se o open síncrono foi bloqueado
  };

  // Estados que aparecem em alguma coluna do Kanban.
  // Pode ser mais que o número de colunas (Follow-Up cobre 2 estados).
  const VISIBLE_STATES = KANBAN_COLUMNS.flatMap(c => COLUMN_STATES[c.key]);

  const { data: contacts = [], isLoading: loading, isFetching, refetch } = useQuery({
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
          data_start, data_ultima_entrada, data_wait_follow_up, followup_custom_em, data_ultimo_follow_up,
          data_em_fechamento, data_ultimo_rmkt, data_suporte, suporte_motivo,
          fechamento_aguardando,
          bot_pausado_ate, ultima_venda_em, rmkt_consecutive_silenciosos,
          qtd_ultimo_pedido,
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
    // Realtime cuida do 99% das atualizações; refetchInterval é fallback pra caso
    // a Publication de contatos não esteja ligada no Supabase.
    staleTime: 30 * 1000,
    refetchInterval: 30 * 1000,
    refetchOnWindowFocus: true,
  });

  // Clientes ELEGÍVEIS pra RMKT (fase wait) — view espelha a elegibilidade do claim.
  const { data: rmktWait = [] } = useQuery({
    queryKey: ['kanban-rmkt-wait', filter],
    enabled: !!filter,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_kanban_rmkt_wait' as any)
        .select('*')
        .order('proxima_rmkt_em', { ascending: true });
      if (error) { console.error('rmkt-wait:', error); return []; }
      const rows = (data || []) as any[];
      const mapped: Contact[] = rows.map(r => ({
        ...r,
        _rmktWait: true,
        instancias: r.inst_nome ? { nome: r.inst_nome, numero: r.inst_numero } : null,
      }));
      if (filter === 'all') return mapped;
      return mapped.filter(c => c.instancia_id === filter || c.instancia_id === null);
    },
    staleTime: 30 * 1000,
    refetchInterval: 30 * 1000,
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
    // Coluna SUPORTE = suporte SEM flag de aguardando fechamento.
    // Coluna FECHAMENTO = em_fechamento (negociação) OU suporte COM flag (aguardando).
    let list = contacts.filter(c => {
      const st = c.ultima_interacao || '';
      if (col === 'suporte') return st === 'suporte' && !c.fechamento_aguardando;
      if (col === 'em_fechamento') return st === 'em_fechamento' || (st === 'suporte' && !!c.fechamento_aguardando);
      return states.includes(st);
    });

    // Filtro do dropdown da coluna Fechamento (negociação / aguardando).
    if (col === 'em_fechamento' && fecFiltro !== 'todos') {
      list = list.filter(c => fecFiltro === 'aguardando'
        ? (c.ultima_interacao === 'suporte' && !!c.fechamento_aguardando)
        : c.ultima_interacao === 'em_fechamento');
    }

    // Filtro do dropdown da coluna Follow-up (Custom / Wait / 1|2|3 de 3).
    if (col === 'follow_up' && fupFiltro !== 'todos') {
      list = list.filter(c => {
        const st = c.ultima_interacao;
        const tent = c.follow_up_tentativas ?? 0;
        if (fupFiltro === 'custom') return st === 'wait_follow_up_custom';
        // 'wait' = aguardando o 1º toque (ainda sem disparo): WAIT sem número
        if (fupFiltro === 'wait')   return st === 'wait_follow_up' && tent === 0;
        // '1' | '2' | '3' → tentativa N já disparada, esteja o card DISPARADO
        // (F-UP N/3) ou de volta na fila (WAIT N/3) — os dois entram.
        return (st === 'follow_up' || st === 'wait_follow_up') && tent === Number(fupFiltro);
      });
    }

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
        if (c.ultima_interacao === 'follow_up') return -Infinity; // disparado no topo
        // custom: ordena pela data prometida pelo cliente
        if (c.ultima_interacao === 'wait_follow_up_custom') {
          return c.followup_custom_em ? new Date(c.followup_custom_em).getTime() - now : Infinity;
        }
        if (!c.data_wait_follow_up) return Infinity;
        const tent = Math.min(c.follow_up_tentativas ?? 0, FOLLOW_UP_GAPS_MS.length - 1);
        const gap = FOLLOW_UP_GAPS_MS[tent];
        const proxDisparo = new Date(c.data_wait_follow_up).getTime() + gap;
        return proxDisparo - now;
      };
      return list.sort((a, b) => tempoAteDisparo(a) - tempoAteDisparo(b));
    }

    // Coluna RMKT: dispatched ('rmkt') no topo + WAIT (elegíveis da view)
    // ordenados por proximidade do disparo (proxima_rmkt_em ASC = mais atrasado
    // primeiro, igual a ordem do claim por ultima_venda_em).
    if (col === 'rmkt') {
      const merged = [...list, ...rmktWait];
      return merged.sort((a, b) => {
        if (!a._rmktWait && b._rmktWait) return -1; // dispatched no topo
        if (a._rmktWait && !b._rmktWait) return 1;
        const ta = a.proxima_rmkt_em ? new Date(a.proxima_rmkt_em).getTime() : Infinity;
        const tb = b.proxima_rmkt_em ? new Date(b.proxima_rmkt_em).getTime() : Infinity;
        return ta - tb;
      });
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
        updates.fechamento_aguardando = false; // negociação real, não aguardando
        break;
      case 'suporte':
        updates.data_suporte = now;
        updates.suporte_motivo = 'manual_kanban';
        updates.fechamento_aguardando = false; // suporte de verdade
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

  // Pause = /humano (pausa bot indefinidamente + move pra suporte)
  const pausarBot = async (c: Contact) => {
    try {
      const { data, error } = await supabase.rpc('executa_comando_dono' as any, {
        p_contato_id: c.id, p_comando: '/humano',
      });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'falha desconhecida');
      toast.success(`${c.nome} → suporte (bot pausado)`);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || err));
    }
  };

  // Play = /voltar (reativa bot + restaura estado_antes_suporte)
  const reativarBot = async (c: Contact) => {
    try {
      const { data, error } = await supabase.rpc('executa_comando_dono' as any, {
        p_contato_id: c.id, p_comando: '/voltar',
      });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'falha desconhecida');
      toast.success(`${c.nome}: bot reativado`);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || err));
    }
  };

  // Editar o motivo do suporte (duplo clique no texto azul do card).
  const handleEditMotivo = async (c: Contact, motivo: string) => {
    const novo = motivo.trim();
    if (novo === (c.suporte_motivo || '')) return; // nada mudou
    const { error } = await supabase.from('contatos')
      .update({ suporte_motivo: novo || null, updated_at: new Date().toISOString() })
      .eq('id', c.id);
    if (error) { toast.error('Não deu pra salvar o motivo: ' + error.message); return; }
    toast.success('Motivo do suporte atualizado');
    queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
  };

  // Mover pra "aguardando fechamento" (ampulheta ⏳ no card de suporte ou
  // de negociação). Cliente esperando data de pagamento ou pagar o PIX.
  // Fica com o bot pausado (estado suporte) mas aparece na coluna FECHAMENTO.
  const moverParaAguardando = async (c: Contact) => {
    try {
      const { data, error } = await supabase.rpc('mover_para_aguardando_fechamento' as any, {
        p_contato_id: c.id, p_motivo: null,
      });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'falha desconhecida');
      toast.success(`${c.nome} → aguardando fechamento`);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || err));
    }
  };

  // X no card de aguardando (não comprou) → finaliza suporte e restaura o
  // estado anterior. Mesma RPC do "suporte realizado" (limpa a flag também).
  const handleFinalizarAguardando = async () => {
    if (!aguardandoTarget) return;
    try {
      const { data, error } = await supabase.rpc('finalizar_suporte_contato' as any, {
        p_contato_id: aguardandoTarget.id,
      });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'falha desconhecida');
      toast.success(`${aguardandoTarget.nome}: aguardando finalizado → ${r.destino}`);
      setAguardandoTarget(null);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || err));
    }
  };

  // Finalizar fechamento → retroage o contato ao estado anterior
  // (estado_antes_fechamento, com fallback por canal/ja_comprou na RPC).
  const handleFinalizarFechamento = async () => {
    if (!finalizarTarget) return;
    try {
      const { data, error } = await supabase.rpc('finalizar_fechamento_contato' as any, {
        p_contato_id: finalizarTarget.id,
      });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'não foi possível finalizar');
      toast.success(`${finalizarTarget.nome}: fechamento finalizado → ${r.novo_estado}`);
      setFinalizarTarget(null);
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

  // Carrega as variações de template da etapa quando o popup abre.
  useEffect(() => {
    if (!disparoTarget) { setTplVars([]); setTplIdx(0); return; }
    const { tipo, proxima } = disparoTarget;
    const sub = tipo === 'followup' ? (['4h', '3d', '7d'][proxima - 1] || '4h') : null;
    let cancelled = false;
    (async () => {
      let q = supabase.from('templates_msg').select('texto, ordem')
        .eq('categoria', tipo === 'followup' ? 'followup' : 'rmkt')
        .eq('ativo', true).order('ordem', { ascending: true });
      if (sub) q = q.eq('subcategoria', sub);
      const { data } = await q;
      if (cancelled) return;
      const arr = (data || []).map((t: any) => String(t.texto || '')).filter(Boolean);
      setTplVars(arr);
      setTplIdx(arr.length ? Math.floor(Math.random() * arr.length) : 0);
    })();
    return () => { cancelled = true; };
  }, [disparoTarget]);

  // Clicar na tag (WAIT/F-UP/RMKT) → abre confirmação de disparo manual X/3.
  const openDisparoManual = (contact: Contact, tipo: 'followup' | 'rmkt') => {
    const feitas = tipo === 'rmkt'
      ? (contact.rmkt_consecutive_silenciosos || 0)
      : (contact.follow_up_tentativas || 0);
    if (feitas >= 3) { toast.info('Este contato já teve os 3 disparos registrados.'); return; }
    setDisparoTarget({ contact, tipo, proxima: feitas + 1 });
  };

  // Confirma o disparo manual: avança contador + carimba data (como o bot faria).
  const handleDisparoManual = async () => {
    if (!disparoTarget) return;
    const { contact, tipo, proxima } = disparoTarget;
    const rpc = tipo === 'rmkt' ? 'registrar_disparo_manual_rmkt' : 'registrar_disparo_manual_followup';
    try {
      const { data, error } = await supabase.rpc(rpc as any, { p_contato_id: contact.id });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'não elegível');
      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Desconhecido',
        acao: `Disparo manual ${tipo === 'rmkt' ? 'RMKT' : 'F-UP'} ${proxima}/3 via Kanban`,
        tabela_afetada: 'contatos', registro_id: contact.id, detalhe: contact.nome,
      });
      toast.success(`${tipo === 'rmkt' ? 'RMKT' : 'Follow-up'} ${proxima}/3 registrado para ${contact.nome}`);
      setDisparoTarget(null);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
      queryClient.invalidateQueries({ queryKey: ['kanban-rmkt-wait'] });
    } catch (err: any) {
      toast.error('Não deu pra registrar: ' + (err.message || 'erro'));
    }
  };

  // ---- F-UP Custom manual (calendário) --------------------------------------
  // Fallback pro agent off/mudo/erro: marca ou edita a data de retorno.
  const abrirAgendarCustom = (contact: Contact) => {
    setAgendarTarget(contact);
    // pré-seleciona a data já agendada (modo edição), senão vazio
    setAgendarDate(contact.followup_custom_em ? new Date(contact.followup_custom_em) : undefined);
  };

  const confirmAgendarCustom = async () => {
    if (!agendarTarget || !agendarDate) return;
    // dispara às 10:00 local (dentro da janela comercial 09-20). O RPC ainda
    // aplica guarda-corpos (nunca no passado, teto de 90 dias).
    const d = new Date(agendarDate);
    d.setHours(10, 0, 0, 0);
    try {
      const { data, error } = await supabase.rpc('agendar_followup_custom', {
        p_contato_id: agendarTarget.id,
        p_data: d.toISOString(),
      });
      if (error) throw error;
      const quando = (data as any)?.agendado_para
        ? new Date((data as any).agendado_para).toLocaleDateString('pt-BR')
        : d.toLocaleDateString('pt-BR');
      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Desconhecido',
        acao: `F-UP Custom agendado p/ ${quando} via Kanban`,
        tabela_afetada: 'contatos', registro_id: agendarTarget.id, detalhe: agendarTarget.nome,
      });
      toast.success(`${agendarTarget.nome}: retorno agendado p/ ${quando}`);
      setAgendarTarget(null); setAgendarDate(undefined);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Não deu pra agendar: ' + (err.message || 'erro'));
    }
  };

  const desagendarCustom = async () => {
    if (!agendarTarget) return;
    try {
      const { error } = await supabase.rpc('desagendar_followup_custom', { p_contato_id: agendarTarget.id });
      if (error) throw error;
      toast.success(`${agendarTarget.nome}: agendamento cancelado — voltou pra fila de follow-up`);
      setAgendarTarget(null); setAgendarDate(undefined);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
    } catch (err: any) {
      toast.error('Não deu pra cancelar: ' + (err.message || 'erro'));
    }
  };

  // Parar campanha (X no card) — F-UP ou RMKT.
  //  followup → parar_followup_contato: volta pra 'start' + followup_bloqueado.
  //  rmkt     → parar_rmkt_contato:     volta pra 'cliente' + rmkt_bloqueado.
  const handlePararCampanha = async () => {
    if (!pararTarget) return;
    const { contact, mode } = pararTarget;
    const rpc = mode === 'rmkt' ? 'parar_rmkt_contato' : 'parar_followup_contato';
    const nomeCamp = mode === 'rmkt' ? 'RMKT' : 'F-UP';
    try {
      const { data, error } = await supabase.rpc(rpc as any, { p_contato_id: contact.id });
      if (error) throw error;
      const r = data as any;
      if (!r?.ok) throw new Error(r?.error || 'falha desconhecida');

      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Desconhecido',
        acao: `Parou ${nomeCamp} via Kanban → ${r.estado_para}`,
        tabela_afetada: 'contatos',
        registro_id: contact.id,
        detalhe: contact.nome,
      });

      toast.success(`${nomeCamp} parado para ${contact.nome}`);
      setPararTarget(null);
      queryClient.invalidateQueries({ queryKey: ['kanban-v2'] });
      queryClient.invalidateQueries({ queryKey: ['kanban-rmkt-wait'] });
    } catch (err: any) {
      toast.error(`Erro ao parar ${nomeCamp}: ` + (err.message || err));
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
        setPararTarget={setPararTarget}
        pausarBot={pausarBot}
        reativarBot={reativarBot}
        copyPhone={copyPhone}
        openChatwoot={openChatwoot}
        onDisparoManual={openDisparoManual}
        onAgendarCustom={abrirAgendarCustom}
        onFinalizarFechamento={setFinalizarTarget}
        onEditMotivo={handleEditMotivo}
        onMoverAguardando={moverParaAguardando}
        onFinalizarAguardando={setAguardandoTarget}
        collapsed={collapsedIds.has(contact.id)}
        toggleCollapsed={toggleCollapsed}
        openPedido={openPedido}
      />
    );
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Kanban</h1>
        <div className="flex items-center gap-2">
          <Button
            variant="outline" size="icon" className="h-9 w-9"
            title="Atualizar Kanban"
            onClick={() => refetch()}
            disabled={isFetching}
          >
            <RefreshCw className={cn('w-4 h-4', isFetching && 'animate-spin')} />
          </Button>
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
              <div className="p-3 border-b border-border space-y-2">
                <div className="flex items-center justify-between">
                  <h3 className="font-bold text-sm">{label}</h3>
                  <Badge variant="secondary" className="text-xs">{colContacts.length}</Badge>
                </div>
                {key === 'follow_up' && (
                  <Select value={fupFiltro} onValueChange={(v) => setFupFiltro(v as typeof fupFiltro)}>
                    <SelectTrigger className="h-7 text-xs">
                      <SelectValue placeholder="Todos os F-up" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="todos">Todos os F-up</SelectItem>
                      <SelectItem value="custom">🗓️ Custom (agendado)</SelectItem>
                      <SelectItem value="wait">⏳ Wait (aguardando 1º)</SelectItem>
                      <SelectItem value="1">1/3 (F-UP + Wait)</SelectItem>
                      <SelectItem value="2">2/3 (F-UP + Wait)</SelectItem>
                      <SelectItem value="3">3/3 (F-UP + Wait)</SelectItem>
                    </SelectContent>
                  </Select>
                )}
                {key === 'em_fechamento' && (
                  <Select value={fecFiltro} onValueChange={(v) => setFecFiltro(v as typeof fecFiltro)}>
                    <SelectTrigger className="h-7 text-xs">
                      <SelectValue placeholder="Todos" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="todos">Todos</SelectItem>
                      <SelectItem value="negociacao">🤝 Em negociação</SelectItem>
                      <SelectItem value="aguardando">⏳ Aguardando fechamento</SelectItem>
                    </SelectContent>
                  </Select>
                )}
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

      {/* Confirmação de finalizar "aguardando fechamento" (não comprou) */}
      <AlertDialog open={!!aguardandoTarget} onOpenChange={() => setAguardandoTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Finalizar aguardando fechamento</AlertDialogTitle>
            <AlertDialogDescription>
              Encerrar o aguardando de {aguardandoTarget?.nome}? Use quando o cliente
              <strong> não vai comprar</strong>. O contato sai da coluna Fechamento e o
              bot é reativado, voltando ao estado anterior.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleFinalizarAguardando} className="bg-destructive text-destructive-foreground">
              Finalizar
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Confirmação de parar campanha (X no card F-UP / RMKT) */}
      <AlertDialog open={!!pararTarget} onOpenChange={() => setPararTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Parar {pararTarget?.mode === 'rmkt' ? 'RMKT' : 'F-UP'}
            </AlertDialogTitle>
            <AlertDialogDescription>
              Deseja realmente parar {pararTarget?.mode === 'rmkt' ? 'RMKT' : 'F-UP'} para {pararTarget?.contact.nome}?
              <br /><br />
              {pararTarget?.mode === 'rmkt' ? (
                <><strong>RMKT:</strong> o contato volta para <strong>Cliente</strong> e não recebe mais RMKT
                  até fazer uma nova compra (a compra reativa automaticamente).</>
              ) : (
                <><strong>F-UP:</strong> o contato volta para <strong>Start</strong> e não recebe mais follow-up
                  (nunca-mais F-UP).</>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handlePararCampanha} className="bg-destructive text-destructive-foreground">
              Parar {pararTarget?.mode === 'rmkt' ? 'RMKT' : 'F-UP'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Confirmação: finalizar fechamento → retroage ao estado anterior */}
      <AlertDialog open={!!finalizarTarget} onOpenChange={() => setFinalizarTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Finalizar fechamento</AlertDialogTitle>
            <AlertDialogDescription>
              Finalizar o fechamento de <strong>{finalizarTarget?.nome}</strong>? O contato sai de
              Fechamento e <strong>volta ao estado anterior</strong> (de onde entrou no fechamento).
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleFinalizarFechamento} className="bg-destructive text-destructive-foreground">
              Finalizar
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Confirmação de disparo manual (clicar na tag WAIT/F-UP/RMKT) */}
      <AlertDialog open={!!disparoTarget} onOpenChange={() => setDisparoTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Disparo manual {disparoTarget?.tipo === 'rmkt' ? 'RMKT' : 'Follow-up'} · {disparoTarget?.proxima}/3
            </AlertDialogTitle>
            <AlertDialogDescription>
              Envie manualmente a mensagem abaixo para <strong>{disparoTarget?.contact.nome}</strong> e confirme. O contador avança como se o bot tivesse mandado — ele retoma daqui.
            </AlertDialogDescription>
          </AlertDialogHeader>

          {disparoTarget && (() => {
            const tplTexto = tplVars.length
              ? preencherTemplate(tplVars[tplIdx % tplVars.length], disparoTarget.contact.nome)
              : '';
            const { apto, faltamMs } = dispatchEligible(disparoTarget);
            return (
              <div className="space-y-3">
                {/* Guarda de cadência: não deixa disparar antes do prazo (evita
                    spam/ban). Fora do prazo → mostra o contador e trava o botão. */}
                {!apto && (
                  <div className="border border-amber-300 bg-amber-50 dark:bg-amber-950/30 rounded-lg px-3 py-2 text-xs text-amber-800 dark:text-amber-200">
                    ⏳ Fora do prazo da cadência. Faltam <strong>{formatCountdown(faltamMs)}</strong> para o {disparoTarget.proxima}/3 ficar apto.
                  </div>
                )}
                {/* número copiável (útil com Chatwoot off) */}
                <div className="flex items-center justify-between gap-2 border rounded-lg px-3 py-2 bg-muted/30">
                  <div className="min-w-0">
                    <p className="text-[10px] uppercase text-muted-foreground tracking-wide">Número do contato</p>
                    <p className="font-mono text-sm truncate">{disparoTarget.contact.telefone || '—'}</p>
                  </div>
                  <Button size="sm" variant="outline" onClick={() => copyPhone(disparoTarget.contact.telefone || '')}>
                    <Copy className="w-3.5 h-3.5 mr-1" /> Copiar
                  </Button>
                </div>

                {/* template com variação */}
                <div className="space-y-1">
                  <div className="flex items-center justify-between">
                    <p className="text-[10px] uppercase text-muted-foreground tracking-wide">
                      Mensagem sugerida{tplVars.length > 1 ? ` (${(tplIdx % tplVars.length) + 1}/${tplVars.length})` : ''}
                    </p>
                    <div className="flex gap-1">
                      {tplVars.length > 1 && (
                        <Button size="sm" variant="ghost" className="h-7 px-2" title="Trocar variação"
                          onClick={() => setTplIdx(i => (i + 1) % tplVars.length)}>
                          <RefreshCw className="w-3.5 h-3.5" />
                        </Button>
                      )}
                      <Button size="sm" variant="ghost" className="h-7 px-2" title="Copiar mensagem" disabled={!tplTexto}
                        onClick={() => copyToClipboard(tplTexto).then(ok => ok ? toast.success('Mensagem copiada!') : toast.error('Falha ao copiar'))}>
                        <Copy className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  </div>
                  <div className="border rounded-lg p-3 text-sm whitespace-pre-wrap bg-background max-h-48 overflow-y-auto">
                    {tplTexto || <span className="text-muted-foreground italic">Nenhum template ativo cadastrado pra esta etapa.</span>}
                  </div>
                </div>
              </div>
            );
          })()}

          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDisparoManual}
              disabled={!dispatchEligible(disparoTarget).apto}
              className={cn(
                'bg-sf-green hover:bg-sf-green/90 text-primary-foreground',
                !dispatchEligible(disparoTarget).apto && 'opacity-40 pointer-events-none',
              )}
            >
              Confirmar {disparoTarget?.proxima}/3
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

      {/* Modal Detalhes do Pedido (ícone caixa nos cards RMKT) */}
      <PedidoDetailModal
        open={!!pedidoAbertoId}
        onClose={() => setPedidoAbertoId(null)}
        pedidoId={pedidoAbertoId}
      />

      {/* Agendar/editar F-UP Custom manual (calendário) */}
      <Dialog
        open={!!agendarTarget}
        onOpenChange={(o) => { if (!o) { setAgendarTarget(null); setAgendarDate(undefined); } }}
      >
        <DialogContent className="sm:max-w-fit">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <CalendarClock className="w-4 h-4 text-violet-600" />
              {agendarTarget?.ultima_interacao === 'wait_follow_up_custom' ? 'Editar retorno agendado' : 'Agendar retorno'}
            </DialogTitle>
            <DialogDescription>
              <span className="font-medium text-foreground">{agendarTarget?.nome}</span> — escolha o dia em que o bot deve retomar o contato.
              {agendarTarget?.followup_custom_em && (
                <span className="block mt-1 text-xs">
                  Agendado hoje para <strong>{new Date(agendarTarget.followup_custom_em).toLocaleDateString('pt-BR')}</strong>.
                </span>
              )}
              <span className="block mt-1 text-xs text-muted-foreground">
                Fallback para quando o agent está mudo/off ou não captou o prazo.
              </span>
            </DialogDescription>
          </DialogHeader>

          <div className="flex justify-center">
            <Calendar
              mode="single"
              locale={ptBR}
              selected={agendarDate}
              onSelect={setAgendarDate}
              weekStartsOn={0}
              disabled={(d) => { const t = new Date(); t.setHours(0, 0, 0, 0); return d < t; }}
              initialFocus
            />
          </div>

          <DialogFooter className="gap-2 sm:justify-between">
            {agendarTarget?.ultima_interacao === 'wait_follow_up_custom' ? (
              <Button variant="ghost" className="text-destructive hover:bg-destructive/10" onClick={desagendarCustom}>
                Cancelar agendamento
              </Button>
            ) : <span />}
            <Button
              className="bg-violet-600 hover:bg-violet-600/90 text-white"
              disabled={!agendarDate}
              onClick={confirmAgendarCustom}
            >
              {agendarTarget?.ultima_interacao === 'wait_follow_up_custom' ? 'Salvar data' : 'Agendar retorno'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

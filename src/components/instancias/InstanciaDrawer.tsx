import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { Eye, EyeOff, RefreshCw, QrCode, RotateCcw, Trash2, Loader2, MessageSquare, CheckCircle2, ExternalLink } from 'lucide-react';
import { getConnectionState, fetchQrCode, restartInstance, deleteInstance, connectChatwoot } from '@/lib/evolutionApi';
import { getChatwootConfig, findInboxByName } from '@/lib/chatwootApi';
import type { InstanciaRow } from './InstanciaCard';

interface Props {
  open: boolean;
  onClose: () => void;
  instancia: InstanciaRow | null;
}

export function InstanciaDrawer({ open, onClose, instancia }: Props) {
  const qc = useQueryClient();
  const [editNome, setEditNome] = useState('');
  const [editEvoInstance, setEditEvoInstance] = useState('');
  const [editEvoUrl, setEditEvoUrl] = useState('');
  const [editApikey, setEditApikey] = useState('');
  const [editAlertaAdmin, setEditAlertaAdmin] = useState(false);
  const [editAlertaTel, setEditAlertaTel] = useState('');
  const [editChatwootInbox, setEditChatwootInbox] = useState('');
  const [editAtivo, setEditAtivo] = useState(true);
  const [editNumero, setEditNumero] = useState('');
  const [showApikey, setShowApikey] = useState(false);
  const [qrBase64, setQrBase64] = useState<string | null>(null);
  const [loadingQr, setLoadingQr] = useState(false);
  const [restarting, setRestarting] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [connectingCw, setConnectingCw] = useState(false);

  useEffect(() => {
    if (!instancia) return;
    setEditNome(instancia.nome);
    setEditEvoInstance(instancia.evolution_instance || '');
    setEditEvoUrl(instancia.evolution_url || 'https://evo.melhorgestao.online');
    setEditApikey(instancia.evolution_apikey || '');
    setEditAlertaAdmin(!!instancia.alerta_admin);
    setEditAlertaTel(instancia.alerta_telefone || '');
    setEditChatwootInbox(instancia.chatwoot_inbox_id || '');
    setEditAtivo(!!instancia.ativo);
    setEditNumero(instancia.numero || '');
    setShowApikey(false);
    setQrBase64(null);
  }, [instancia]);

  // estado evolution em tempo real
  const { data: evoState, refetch: refetchState, isFetching: stateLoading } = useQuery({
    queryKey: ['evo_state_drawer', instancia?.id],
    enabled: !!instancia?.evolution_apikey && !!instancia?.evolution_instance && open,
    queryFn: async () => {
      return getConnectionState({
        evolution_url: instancia!.evolution_url || '',
        evolution_instance: instancia!.evolution_instance || '',
        evolution_apikey: instancia!.evolution_apikey || '',
      });
    },
    refetchInterval: open ? 15_000 : false,
  });

  // config Chatwoot (pra deeplink do inbox)
  const { data: cwConfig } = useQuery({
    queryKey: ['chatwoot_config'],
    enabled: open,
    queryFn: async () => {
      const { data } = await supabase
        .from('configuracoes')
        .select('chave, valor')
        .in('chave', ['chatwoot_url', 'chatwoot_account_id']);
      const map = Object.fromEntries((data || []).map((c: any) => [c.chave, c.valor]));
      return { url: map.chatwoot_url || '', accountId: map.chatwoot_account_id || '' };
    },
    staleTime: 5 * 60 * 1000,
  });

  // histórico (eventos_contato filtrados por instancia)
  const { data: eventos } = useQuery({
    queryKey: ['eventos_instancia', instancia?.id],
    enabled: !!instancia?.id && open,
    queryFn: async () => {
      const { data } = await supabase
        .from('eventos_contato' as any)
        .select('tipo, metadata, created_at')
        .eq('instancia_id', instancia!.id)
        .in('tipo', ['instancia_pausada', 'instancia_reativada', 'instancia_criada', 'instancia_marcada_admin'])
        .order('created_at', { ascending: false })
        .limit(20);
      return (data || []) as any[];
    },
  });

  if (!instancia) return null;

  const saveChanges = async () => {
    const changes: Record<string, any> = {};
    if (editNome !== instancia.nome) changes.nome = editNome.trim();
    if (editEvoInstance !== (instancia.evolution_instance || '')) changes.evolution_instance = editEvoInstance.trim() || null;
    if (editEvoUrl !== (instancia.evolution_url || '')) changes.evolution_url = editEvoUrl.trim() || null;
    if (editApikey !== (instancia.evolution_apikey || '')) changes.evolution_apikey = editApikey.trim() || null;
    if (editAlertaAdmin !== instancia.alerta_admin) changes.alerta_admin = editAlertaAdmin;
    if (editAlertaTel !== (instancia.alerta_telefone || '')) changes.alerta_telefone = editAlertaTel.trim() || null;
    if (editChatwootInbox !== (instancia.chatwoot_inbox_id || '')) changes.chatwoot_inbox_id = editChatwootInbox.trim() || null;
    if (editAtivo !== instancia.ativo) changes.ativo = editAtivo;
    if (editNumero !== (instancia.numero || '')) changes.numero = editNumero.trim() || null;
    if (Object.keys(changes).length === 0) { toast.info('Sem alterações'); return; }

    const { error } = await supabase.from('instancias').update(changes).eq('id', instancia.id);
    if (error) { toast.error('Erro ao salvar: ' + error.message); return; }
    toast.success('Instância atualizada');
    qc.invalidateQueries({ queryKey: ['instancias_list'] });
    qc.invalidateQueries({ queryKey: ['evo_state', instancia.id] });
    qc.invalidateQueries({ queryKey: ['evo_state_drawer', instancia.id] });
  };

  const handlePause = async (horas: number, motivo: string) => {
    const { error } = await supabase.rpc('pausar_instancia', {
      p_id: instancia.id,
      p_motivo: motivo,
      p_horas: horas,
    });
    if (error) { toast.error('Erro ao pausar: ' + error.message); return; }
    toast.success(`Pausada por ${horas}h`);
    qc.invalidateQueries({ queryKey: ['instancias_list'] });
    qc.invalidateQueries({ queryKey: ['eventos_instancia', instancia.id] });
  };

  const handleReativar = async () => {
    const { error } = await supabase.rpc('reativar_instancia', { p_id: instancia.id });
    if (error) { toast.error('Erro ao reativar: ' + error.message); return; }
    toast.success('Reativada');
    qc.invalidateQueries({ queryKey: ['instancias_list'] });
    qc.invalidateQueries({ queryKey: ['eventos_instancia', instancia.id] });
  };

  const handleShowQR = async () => {
    setLoadingQr(true);
    setQrBase64(null);
    const r = await fetchQrCode({
      evolution_url: instancia.evolution_url || '',
      evolution_instance: instancia.evolution_instance || '',
      evolution_apikey: instancia.evolution_apikey || '',
    });
    setLoadingQr(false);
    if (r.error) { toast.error('Erro QR: ' + r.error); return; }
    if (r.base64) {
      const src = r.base64.startsWith('data:') ? r.base64 : `data:image/png;base64,${r.base64}`;
      setQrBase64(src);
    } else if (r.pairingCode) {
      toast.info('Pairing code: ' + r.pairingCode);
    } else {
      toast.error('Evolution não retornou QR Code');
    }
  };

  const handleConnectChatwoot = async () => {
    setConnectingCw(true);
    const cfg = await getChatwootConfig();
    if (!cfg.url || !cfg.accountId || !cfg.apiToken) {
      setConnectingCw(false);
      toast.error('Config Chatwoot incompleta — preencha em Configurações Globais');
      return;
    }
    const r = await connectChatwoot({
      inst: {
        evolution_url: instancia.evolution_url || '',
        evolution_instance: instancia.evolution_instance || '',
        evolution_apikey: instancia.evolution_apikey || '',
      },
      chatwootUrl: cfg.url,
      accountId: cfg.accountId,
      apiToken: cfg.apiToken,
    });
    if (!r.ok) { setConnectingCw(false); toast.error('Chatwoot: ' + r.error); return; }

    // Auto-detecta inbox criado (Evolution usa nameInbox = evolution_instance)
    let inboxId = editChatwootInbox; // fallback: o que já estava
    try {
      const inbox = await findInboxByName(cfg, instancia.evolution_instance || '');
      if (inbox) inboxId = String(inbox.id);
    } catch { /* segue sem inbox_id */ }

    await supabase
      .from('instancias')
      .update({ chatwoot_integrated: true, chatwoot_inbox_id: inboxId || null })
      .eq('id', instancia.id);
    setEditChatwootInbox(inboxId);
    setConnectingCw(false);
    qc.invalidateQueries({ queryKey: ['instancias_list'] });
    toast.success(inboxId ? `Conectada ao Chatwoot (inbox #${inboxId})` : 'Conectada ao Chatwoot');
  };

  const handleRestart = async () => {
    setRestarting(true);
    const r = await restartInstance({
      evolution_url: instancia.evolution_url || '',
      evolution_instance: instancia.evolution_instance || '',
      evolution_apikey: instancia.evolution_apikey || '',
    });
    setRestarting(false);
    if (!r.ok) { toast.error('Erro restart: ' + r.error); return; }
    toast.success('Restart solicitado');
    setTimeout(() => refetchState(), 2000);
  };

  const handleDelete = async () => {
    if (!confirm(`Excluir Instância ${instancia.nome}? Isto remove no Evolution e no CRM. Workflows param de usá-la imediatamente.`)) return;
    setDeleting(true);
    // tenta deletar no Evolution primeiro (best-effort)
    if (instancia.evolution_instance) {
      const r = await deleteInstance(instancia.evolution_instance, instancia.evolution_url || '');
      if (!r.ok) {
        const proceed = confirm(`Evolution retornou erro (${r.error}). Excluir do CRM mesmo assim?`);
        if (!proceed) { setDeleting(false); return; }
      }
    }
    const { error } = await supabase.from('instancias').delete().eq('id', instancia.id);
    setDeleting(false);
    if (error) { toast.error('Erro DB: ' + error.message); return; }
    toast.success('Instância excluída');
    qc.invalidateQueries({ queryKey: ['instancias_list'] });
    onClose();
  };

  return (
    <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
      <SheetContent className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Instância {instancia.nome}</SheetTitle>
        </SheetHeader>

        <div className="space-y-6 py-4">
          {/* Status */}
          <section className="space-y-2">
            <p className="text-xs uppercase text-muted-foreground tracking-wide">Status</p>
            <div className="flex items-center justify-between border rounded-lg p-3">
              <div>
                <p className="text-sm font-semibold">
                  {instancia.status === 'ativo'
                    ? (evoState === 'open' ? '🟢 Conectada' : evoState === 'connecting' ? '🟡 Conectando' : evoState === 'close' ? '🔴 Sem conexão' : '⚪ Verificando…')
                    : `⚫ ${instancia.status}`}
                </p>
                {instancia.motivo_pausa && <p className="text-xs text-muted-foreground">{instancia.motivo_pausa}</p>}
                {instancia.pausado_ate && <p className="text-xs text-muted-foreground">Pausada até {new Date(instancia.pausado_ate).toLocaleString('pt-BR')}</p>}
              </div>
              <Button variant="ghost" size="icon" onClick={() => refetchState()} disabled={stateLoading}>
                <RefreshCw className={stateLoading ? 'w-4 h-4 animate-spin' : 'w-4 h-4'} />
              </Button>
            </div>
          </section>

          {/* QR Code */}
          {evoState !== 'open' && instancia.status === 'ativo' && (
            <section className="space-y-2">
              <p className="text-xs uppercase text-muted-foreground tracking-wide">Reconectar</p>
              <Button variant="outline" className="w-full" onClick={handleShowQR} disabled={loadingQr}>
                {loadingQr ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <QrCode className="w-4 h-4 mr-2" />}
                Mostrar QR Code
              </Button>
              {qrBase64 && (
                <div className="bg-white p-3 rounded-lg flex justify-center">
                  <img src={qrBase64} alt="QR Code Evolution" className="w-56 h-56" />
                </div>
              )}
              <Button variant="outline" className="w-full" onClick={handleRestart} disabled={restarting}>
                {restarting ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <RotateCcw className="w-4 h-4 mr-2" />}
                Forçar reconexão (restart)
              </Button>
            </section>
          )}

          {/* Configuração */}
          <section className="space-y-3">
            <p className="text-xs uppercase text-muted-foreground tracking-wide">Configuração</p>
            <div className="space-y-2">
              <Label className="text-xs">Nome CRM</Label>
              <Input value={editNome} onChange={e => setEditNome(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label className="text-xs">Número do chip (DDD + número)</Label>
              <Input
                value={editNumero}
                onChange={e => setEditNumero(e.target.value.replace(/\D/g, '').slice(0, 11))}
                placeholder="45998510512"
                inputMode="numeric"
                maxLength={11}
                className="font-mono"
              />
              <p className="text-[10px] text-muted-foreground">
                Só dígitos, sem 55. Ao salvar, é criado/atualizado um contato INTERNO vinculado à instância (uso exclusivo de alertas — não aparece no Kanban, não chama agente).
              </p>
            </div>
            <div className="space-y-2">
              <Label className="text-xs">Nome Evolution</Label>
              <Input value={editEvoInstance} onChange={e => setEditEvoInstance(e.target.value)} className="font-mono" />
            </div>
            <div className="space-y-2">
              <Label className="text-xs">URL Evolution</Label>
              <Input value={editEvoUrl} onChange={e => setEditEvoUrl(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label className="text-xs">API Key</Label>
              <div className="flex gap-2">
                <Input
                  type={showApikey ? 'text' : 'password'}
                  value={editApikey}
                  onChange={e => setEditApikey(e.target.value)}
                  className="font-mono text-xs"
                />
                <Button variant="ghost" size="icon" onClick={() => setShowApikey(s => !s)} type="button">
                  {showApikey ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </Button>
              </div>
            </div>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <Checkbox checked={editAlertaAdmin} onCheckedChange={v => setEditAlertaAdmin(!!v)} />
              <span>Recebe alertas (👑 envia avisos de erro pelo WhatsApp)</span>
            </label>
            {editAlertaAdmin && (
              <div className="space-y-1 pl-6">
                <Label className="text-xs">Telefone destino dos alertas</Label>
                <Input
                  value={editAlertaTel}
                  onChange={e => setEditAlertaTel(e.target.value)}
                  placeholder="5511991282579"
                  className="font-mono text-xs"
                />
                <p className="text-[10px] text-muted-foreground">Apenas dígitos com 55 na frente. Para onde os alertas serão enviados.</p>
              </div>
            )}
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <Checkbox checked={editAtivo} onCheckedChange={v => setEditAtivo(!!v)} />
              <span>Ativa (campo ativo — workflows também filtram)</span>
            </label>
            <Button className="w-full" onClick={saveChanges}>Salvar alterações</Button>
          </section>

          {/* Chatwoot */}
          <section className="space-y-2">
            <p className="text-xs uppercase text-muted-foreground tracking-wide flex items-center gap-1.5">
              <MessageSquare className="w-3 h-3" /> Chatwoot
            </p>

            {instancia.chatwoot_integrated ? (
              <>
                {/* Card de status conectado — destaque visual */}
                <div className="rounded-xl border-2 border-blue-500/30 bg-blue-500/5 p-4">
                  <div className="flex items-center gap-3 mb-3">
                    <div className="rounded-full bg-blue-500/15 p-2">
                      <CheckCircle2 className="w-5 h-5 text-blue-600 dark:text-blue-400" />
                    </div>
                    <div className="flex-1">
                      <p className="font-semibold text-blue-900 dark:text-blue-200">Integração ativa</p>
                      <p className="text-xs text-muted-foreground">
                        Inbox {editChatwootInbox ? `#${editChatwootInbox}` : '—'} · {instancia.evolution_instance}
                      </p>
                    </div>
                  </div>
                  {cwConfig?.url && cwConfig?.accountId && editChatwootInbox && (
                    <a
                      href={`${cwConfig.url.replace(/\/$/, '')}/app/accounts/${cwConfig.accountId}/inbox/${editChatwootInbox}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-1.5 text-sm font-medium text-blue-700 dark:text-blue-300 hover:underline"
                    >
                      Abrir inbox no Chatwoot
                      <ExternalLink className="w-3.5 h-3.5" />
                    </a>
                  )}
                </div>
                {/* Reconectar — pequeno, secundário */}
                <Button
                  variant="ghost"
                  size="sm"
                  className="w-full text-xs text-muted-foreground hover:text-foreground"
                  onClick={handleConnectChatwoot}
                  disabled={connectingCw}
                >
                  {connectingCw ? <Loader2 className="w-3 h-3 mr-1.5 animate-spin" /> : <RefreshCw className="w-3 h-3 mr-1.5" />}
                  Reconectar (re-importa contatos/msgs)
                </Button>
                {/* Inbox ID editável — collapsed sob acordeão visual minimalista */}
                <details className="text-xs">
                  <summary className="cursor-pointer text-muted-foreground hover:text-foreground select-none">
                    Inbox ID manual
                  </summary>
                  <div className="mt-2 space-y-1">
                    <Input
                      value={editChatwootInbox}
                      onChange={e => setEditChatwootInbox(e.target.value)}
                      placeholder="auto-detectado após conectar"
                      className="font-mono text-xs"
                    />
                    <p className="text-[10px] text-muted-foreground">
                      Preencha manualmente apenas se o auto-detect falhar.
                    </p>
                  </div>
                </details>
              </>
            ) : (
              <>
                {/* Não conectada — call to action prominente */}
                <p className="text-xs text-muted-foreground">
                  Evolution cria um inbox com nome <span className="font-mono">"{instancia.evolution_instance}"</span> no Chatwoot.
                </p>
                <Button
                  className="w-full bg-blue-600 hover:bg-blue-700 text-white"
                  onClick={handleConnectChatwoot}
                  disabled={connectingCw}
                >
                  {connectingCw ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <MessageSquare className="w-4 h-4 mr-2" />}
                  Conectar ao Chatwoot
                </Button>
              </>
            )}
          </section>

          {/* Ações de pausa */}
          <section className="space-y-2">
            <p className="text-xs uppercase text-muted-foreground tracking-wide">Pausar / Reativar</p>
            {instancia.status === 'ativo' ? (
              <div className="flex gap-2">
                <Button variant="outline" className="flex-1" onClick={() => handlePause(24, 'admin: pausa 24h')}>Pausar 24h</Button>
                <Button variant="outline" className="flex-1" onClick={() => handlePause(24 * 7, 'admin: pausa indefinida')}>Pausar 7d</Button>
              </div>
            ) : (
              <Button variant="default" className="w-full bg-sf-green hover:bg-sf-green/90" onClick={handleReativar}>Reativar agora</Button>
            )}
          </section>

          {/* Histórico */}
          <section className="space-y-2">
            <p className="text-xs uppercase text-muted-foreground tracking-wide">Histórico</p>
            <div className="space-y-1.5 max-h-56 overflow-y-auto">
              {eventos && eventos.length > 0 ? eventos.map((e: any, idx) => (
                <div key={idx} className="text-xs border-l-2 border-muted pl-2 py-1">
                  <div className="flex justify-between items-start gap-2">
                    <Badge variant="outline" className="text-[10px]">{e.tipo.replace('instancia_','')}</Badge>
                    <span className="text-muted-foreground tabular-nums">
                      {new Date(e.created_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}
                    </span>
                  </div>
                  {e.metadata?.motivo && <p className="text-muted-foreground mt-0.5">{e.metadata.motivo}</p>}
                </div>
              )) : <p className="text-xs text-muted-foreground">Sem eventos registrados.</p>}
            </div>
          </section>

          {/* Zona perigosa */}
          <section className="space-y-2 pt-4 border-t">
            <p className="text-xs uppercase text-destructive tracking-wide">Zona perigosa</p>
            <Button variant="destructive" className="w-full" onClick={handleDelete} disabled={deleting}>
              {deleting ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Trash2 className="w-4 h-4 mr-2" />}
              Excluir instância
            </Button>
          </section>
        </div>
      </SheetContent>
    </Sheet>
  );
}

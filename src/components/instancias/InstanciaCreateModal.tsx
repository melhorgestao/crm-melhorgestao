import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { toast } from 'sonner';
import { Loader2, QrCode, ArrowRight } from 'lucide-react';
import { createInstance, fetchQrCode, getConnectionState, getMasterApiKey, connectChatwoot, setWebhook } from '@/lib/evolutionApi';
import { getChatwootConfig, findInboxByName } from '@/lib/chatwootApi';

interface Props {
  open: boolean;
  onClose: () => void;
}

type Step = 'form' | 'creating' | 'qr' | 'done' | 'error';

const DEFAULT_URL = 'https://evo.melhorgestao.online';

export function InstanciaCreateModal({ open, onClose }: Props) {
  const qc = useQueryClient();
  const [step, setStep] = useState<Step>('form');
  const [nomeCrm, setNomeCrm] = useState('');
  const [nomeEvo, setNomeEvo] = useState('');
  const [url, setUrl] = useState(DEFAULT_URL);
  const [ativar, setAtivar] = useState(true);
  const [alertaAdmin, setAlertaAdmin] = useState(false);
  const [conectarChatwoot, setConectarChatwoot] = useState(true);

  const [apikey, setApikey] = useState<string | null>(null);
  const [qrSrc, setQrSrc] = useState<string | null>(null);
  const [instanciaId, setInstanciaId] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [masterMissing, setMasterMissing] = useState(false);

  useEffect(() => {
    if (open) {
      setStep('form');
      setNomeCrm('');
      setNomeEvo('');
      setUrl(DEFAULT_URL);
      setAtivar(true);
      setAlertaAdmin(false);
      setApikey(null);
      setQrSrc(null);
      setInstanciaId(null);
      setErrorMsg(null);
      // check master apikey upfront
      getMasterApiKey().then(k => setMasterMissing(!k));
    }
  }, [open]);

  // Polling do estado da conexão até 'open'
  useEffect(() => {
    if (step !== 'qr' || !nomeEvo || !apikey) return;
    const interval = setInterval(async () => {
      const state = await getConnectionState({ evolution_url: url, evolution_instance: nomeEvo, evolution_apikey: apikey });
      if (state === 'open') {
        setStep('done');
        qc.invalidateQueries({ queryKey: ['instancias_list'] });
      }
    }, 3000);
    return () => clearInterval(interval);
  }, [step, nomeEvo, apikey, url, qc]);

  const handleCreate = async () => {
    if (!nomeCrm.trim() || !nomeEvo.trim()) {
      toast.error('Preencha Nome CRM e Nome Evolution');
      return;
    }
    setStep('creating');
    setErrorMsg(null);

    // 1) Cria na Evolution
    const created = await createInstance({ instanceName: nomeEvo.trim(), evolutionUrl: url });
    if (!created.ok || !created.apikey) {
      setErrorMsg(created.error || 'Evolution não retornou apikey');
      setStep('error');
      return;
    }
    setApikey(created.apikey);

    // 1.5) Assina o webhook do router (MESSAGES_UPSERT + SEND_MESSAGE).
    // Sem SEND_MESSAGE, comandos "/" via Chatwoot não chegam no router.
    // Best-effort: não bloqueia o fluxo, mas avisa se falhar.
    const whRes = await setWebhook({ evolution_url: url, evolution_instance: nomeEvo.trim(), evolution_apikey: created.apikey });
    if (!whRes.ok) {
      toast.warning('Instância criada, mas o webhook falhou — comandos podem não funcionar. Erro: ' + (whRes.error || 'desconhecido'));
    }

    // 2) Insert no banco
    const { data: row, error: insErr } = await supabase
      .from('instancias')
      .insert({
        nome: nomeCrm.trim(),
        evolution_instance: nomeEvo.trim(),
        evolution_url: url,
        evolution_apikey: created.apikey,
        ativo: ativar,
        status: 'ativo',
        alerta_admin: alertaAdmin,
      } as any)
      .select('id')
      .single();
    if (insErr) {
      setErrorMsg('Criada na Evolution mas falhou no DB: ' + insErr.message);
      setStep('error');
      return;
    }
    setInstanciaId(row.id);

    // 2.5) Conexão automática com Chatwoot (best-effort, não bloqueia QR)
    if (conectarChatwoot) {
      try {
        const cfg = await getChatwootConfig();
        if (cfg.url && cfg.accountId && cfg.apiToken) {
          const cwRes = await connectChatwoot({
            inst: { evolution_url: url, evolution_instance: nomeEvo.trim(), evolution_apikey: created.apikey },
            chatwootUrl: cfg.url, accountId: cfg.accountId, apiToken: cfg.apiToken,
          });
          if (cwRes.ok) {
            let inboxId: string | null = null;
            try {
              const ib = await findInboxByName(cfg, nomeEvo.trim());
              if (ib) inboxId = String(ib.id);
            } catch { /* ignore */ }
            await supabase.from('instancias').update({
              chatwoot_integrated: true,
              chatwoot_inbox_id: inboxId,
            }).eq('id', row.id);
          }
        }
      } catch { /* não falha o fluxo principal */ }
    }

    // 3) QR Code
    if (created.qrcode) {
      const src = created.qrcode.startsWith('data:') ? created.qrcode : `data:image/png;base64,${created.qrcode}`;
      setQrSrc(src);
      setStep('qr');
      qc.invalidateQueries({ queryKey: ['instancias_list'] });
      return;
    }
    // QR não veio embutido — busca via /instance/connect
    const r = await fetchQrCode({ evolution_url: url, evolution_instance: nomeEvo.trim(), evolution_apikey: created.apikey });
    if (r.base64) {
      const src = r.base64.startsWith('data:') ? r.base64 : `data:image/png;base64,${r.base64}`;
      setQrSrc(src);
      setStep('qr');
      qc.invalidateQueries({ queryKey: ['instancias_list'] });
    } else {
      setErrorMsg('Instância criada, mas Evolution não devolveu QR Code. Abra Evolution Manager pra conectar.');
      setStep('error');
      qc.invalidateQueries({ queryKey: ['instancias_list'] });
    }
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Nova Instância</DialogTitle>
          <DialogDescription>Cria na Evolution + adiciona ao CRM em um fluxo só.</DialogDescription>
        </DialogHeader>

        {step === 'form' && (
          <div className="space-y-3">
            {masterMissing && (
              <div className="border border-amber-300 bg-amber-50 dark:bg-amber-950/30 text-amber-900 dark:text-amber-200 rounded-lg p-3 text-xs">
                <strong>Atenção:</strong> A master apikey da Evolution não está configurada em <code>configuracoes.evolution_master_apikey</code>. Sem ela, a criação automática vai falhar.
              </div>
            )}
            <div className="space-y-1">
              <Label className="text-xs">Nome CRM *</Label>
              <Input value={nomeCrm} onChange={e => setNomeCrm(e.target.value)} placeholder="ex: 3" />
              <p className="text-[10px] text-muted-foreground">Apelido curto usado no CRM (ex: "1", "2", "vendas").</p>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Nome Evolution *</Label>
              <Input value={nomeEvo} onChange={e => setNomeEvo(e.target.value)} placeholder="ex: Instancia 3" className="font-mono" />
              <p className="text-[10px] text-muted-foreground">Nome que aparece no servidor Evolution e nas URLs (case-sensitive).</p>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">URL Evolution</Label>
              <Input value={url} onChange={e => setUrl(e.target.value)} />
            </div>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <Checkbox checked={ativar} onCheckedChange={v => setAtivar(!!v)} />
              <span>Ativar imediatamente (workflows passam a usar)</span>
            </label>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <Checkbox checked={alertaAdmin} onCheckedChange={v => setAlertaAdmin(!!v)} />
              <span>Definir como destino dos alertas (👑)</span>
            </label>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <Checkbox checked={conectarChatwoot} onCheckedChange={v => setConectarChatwoot(!!v)} />
              <span>Criar inbox no Chatwoot automaticamente</span>
            </label>
            <div className="flex gap-2 pt-2">
              <Button variant="outline" className="flex-1" onClick={onClose}>Cancelar</Button>
              <Button className="flex-1 bg-sf-green hover:bg-sf-green/90" onClick={handleCreate}>
                Criar e Conectar <ArrowRight className="w-4 h-4 ml-1" />
              </Button>
            </div>
          </div>
        )}

        {step === 'creating' && (
          <div className="py-8 text-center space-y-3">
            <Loader2 className="w-8 h-8 animate-spin text-sf-green mx-auto" />
            <p className="text-sm">Criando na Evolution e registrando no CRM…</p>
          </div>
        )}

        {step === 'qr' && (
          <div className="space-y-3">
            <p className="text-sm text-center">Escaneie o QR Code no WhatsApp para conectar:</p>
            <div className="bg-white p-3 rounded-lg flex justify-center">
              {qrSrc ? <img src={qrSrc} alt="QR Code" className="w-64 h-64" /> : <Loader2 className="w-8 h-8 animate-spin" />}
            </div>
            <p className="text-xs text-muted-foreground text-center flex items-center justify-center gap-1.5">
              <Loader2 className="w-3 h-3 animate-spin" /> Aguardando conexão…
            </p>
            <Button variant="outline" className="w-full" onClick={onClose}>Continuar em background</Button>
          </div>
        )}

        {step === 'done' && (
          <div className="py-6 text-center space-y-3">
            <div className="w-16 h-16 rounded-full bg-sf-green/20 flex items-center justify-center mx-auto">
              <QrCode className="w-8 h-8 text-sf-green" />
            </div>
            <p className="font-semibold">Conectada e ativa nos workflows!</p>
            <p className="text-xs text-muted-foreground">Instância {nomeCrm} pronta pra receber e enviar mensagens.</p>
            <Button className="w-full bg-sf-green hover:bg-sf-green/90" onClick={onClose}>Fechar</Button>
          </div>
        )}

        {step === 'error' && (
          <div className="py-4 space-y-3">
            <div className="border border-destructive/30 bg-destructive/10 rounded-lg p-3 text-sm">
              <p className="font-semibold mb-1">Falhou ao criar</p>
              <p className="text-xs">{errorMsg}</p>
            </div>
            {instanciaId && (
              <p className="text-xs text-muted-foreground">A instância foi criada no DB (id {instanciaId.slice(0, 8)}). Você pode editar manualmente na lista.</p>
            )}
            <div className="flex gap-2">
              <Button variant="outline" className="flex-1" onClick={() => setStep('form')}>Tentar novamente</Button>
              <Button variant="outline" className="flex-1" onClick={onClose}>Fechar</Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

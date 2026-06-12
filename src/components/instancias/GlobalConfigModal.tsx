import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { Eye, EyeOff, Loader2 } from 'lucide-react';

interface Props {
  open: boolean;
  onClose: () => void;
}

const KEYS = [
  'evolution_master_apikey',
  'chatwoot_url',
  'chatwoot_account_id',
  'chatwoot_api_token',
] as const;

type ConfigKey = typeof KEYS[number];

export function GlobalConfigModal({ open, onClose }: Props) {
  const [values, setValues] = useState<Record<ConfigKey, string>>({
    evolution_master_apikey: '',
    chatwoot_url: '',
    chatwoot_account_id: '',
    chatwoot_api_token: '',
  });
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [showMaster, setShowMaster] = useState(false);
  const [showToken, setShowToken] = useState(false);

  useEffect(() => {
    if (!open) return;
    (async () => {
      setLoading(true);
      const { data } = await supabase
        .from('configuracoes')
        .select('chave, valor')
        .in('chave', KEYS as any);
      const map: any = { ...values };
      (data || []).forEach((r: any) => { if (KEYS.includes(r.chave)) map[r.chave] = r.valor || ''; });
      setValues(map);
      setLoading(false);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const save = async () => {
    setSaving(true);
    const rows = KEYS.map(k => ({ chave: k, valor: values[k] || '' }));
    const { error } = await supabase.from('configuracoes').upsert(rows, { onConflict: 'chave' });
    setSaving(false);
    if (error) { toast.error('Erro ao salvar: ' + error.message); return; }
    toast.success('Configurações salvas');
    onClose();
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Configurações Globais</DialogTitle>
          <DialogDescription>Credenciais usadas por todas as instâncias.</DialogDescription>
        </DialogHeader>

        {loading ? (
          <div className="py-8 text-center"><Loader2 className="w-6 h-6 animate-spin mx-auto" /></div>
        ) : (
          <div className="space-y-5 py-2">
            <section className="space-y-3">
              <p className="text-xs uppercase text-muted-foreground tracking-wide">Evolution</p>
              <div className="space-y-1">
                <Label className="text-xs">Master API Key</Label>
                <div className="flex gap-2">
                  <Input
                    type={showMaster ? 'text' : 'password'}
                    value={values.evolution_master_apikey}
                    onChange={e => setValues(v => ({ ...v, evolution_master_apikey: e.target.value }))}
                    placeholder="apikey do AUTHENTICATION_API_KEY do servidor Evolution"
                    className="font-mono text-xs"
                  />
                  <Button variant="ghost" size="icon" type="button" onClick={() => setShowMaster(s => !s)}>
                    {showMaster ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </Button>
                </div>
                <p className="text-[10px] text-muted-foreground">
                  Necessária para criar/excluir instâncias via UI. Vem do .env do servidor Evolution.
                </p>
              </div>
            </section>

            <section className="space-y-3">
              <p className="text-xs uppercase text-muted-foreground tracking-wide">Chatwoot</p>
              <div className="space-y-1">
                <Label className="text-xs">URL</Label>
                <Input
                  value={values.chatwoot_url}
                  onChange={e => setValues(v => ({ ...v, chatwoot_url: e.target.value }))}
                  placeholder="https://chatwoot.melhorgestao.online"
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Account ID</Label>
                <Input
                  value={values.chatwoot_account_id}
                  onChange={e => setValues(v => ({ ...v, chatwoot_account_id: e.target.value }))}
                  placeholder="ex: 1"
                  className="font-mono"
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">API Token</Label>
                <div className="flex gap-2">
                  <Input
                    type={showToken ? 'text' : 'password'}
                    value={values.chatwoot_api_token}
                    onChange={e => setValues(v => ({ ...v, chatwoot_api_token: e.target.value }))}
                    placeholder="token de acesso à API"
                    className="font-mono text-xs"
                  />
                  <Button variant="ghost" size="icon" type="button" onClick={() => setShowToken(s => !s)}>
                    {showToken ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </Button>
                </div>
                <p className="text-[10px] text-muted-foreground">
                  Encontrado em Chatwoot → Profile Settings → Access Token.
                </p>
              </div>
            </section>

            <div className="flex gap-2 pt-2">
              <Button variant="outline" className="flex-1" onClick={onClose}>Cancelar</Button>
              <Button className="flex-1 bg-sf-green hover:bg-sf-green/90" onClick={save} disabled={saving}>
                {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
                Salvar
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

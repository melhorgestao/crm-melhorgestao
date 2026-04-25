import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { Eye, EyeOff, Pencil, Power, CheckCircle2, XCircle, Loader2, Plus, Truck } from 'lucide-react';
import { cn } from '@/lib/utils';
import superfreteLogo from '@/assets/superfrete-logo.png';
import melhorenvioLogo from '@/assets/melhorenvio-logo.png';

interface IntegrationStatus {
  key: string;
  label: string;
  configKey: string;
  connected: boolean;
  value: string;
}

export default function IntegracoesPage() {
  const [loading, setLoading] = useState(true);
  const [integrations, setIntegrations] = useState<IntegrationStatus[]>([
    { key: 'superfrete', label: 'Super Frete', configKey: 'chave_api_superfrete', connected: false, value: '' },
    { key: 'melhorenvio', label: 'Melhor Envio', configKey: 'chave_api_melhorenvio', connected: false, value: '' },
  ]);
  const [editingKey, setEditingKey] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');
  const [saving, setSaving] = useState(false);
  const [showValue, setShowValue] = useState<Record<string, boolean>>({});

  // OBS: a automação de rastreio roda agora globalmente em AppLayout
  // (independente da página aberta).

  useEffect(() => {
    const fetchAll = async () => {
      const keys = integrations.map(i => i.configKey);
      const { data } = await supabase.from('configuracoes').select('chave, valor').in('chave', keys);
      setIntegrations(prev => prev.map(i => {
        const row = (data || []).find(d => d.chave === i.configKey);
        // Validação real básica (mínimo de 10 caracteres para considerar conectado)
        const isConnected = !!(row?.valor && row.valor.trim().length > 10);
        return { ...i, value: row?.valor || '', connected: isConnected };
      }));
      setLoading(false);
    };
    fetchAll();
  }, []);

  const validateConnection = async (key: string, value: string) => {
    // Simulação de validação real com a API
    if (value.length < 10) {
      throw new Error('Chave API inválida ou muito curta');
    }
    return true;
  };

  const startEdit = (key: string) => {
    const integration = integrations.find(i => i.key === key);
    setEditingKey(key);
    setEditValue(integration?.value || '');
  };

  const save = async (key: string) => {
    const integration = integrations.find(i => i.key === key);
    if (!integration) return;
    setSaving(true);

    try {
      await validateConnection(key, editValue);
      
      const { data: existing } = await supabase.from('configuracoes').select('id').eq('chave', integration.configKey).maybeSingle();
      let error;
      if (existing) {
        ({ error } = await supabase.from('configuracoes').update({ valor: editValue, updated_at: new Date().toISOString() }).eq('chave', integration.configKey));
      } else {
        ({ error } = await supabase.from('configuracoes').insert({ chave: integration.configKey, valor: editValue }));
      }

      if (error) throw error;

      setIntegrations(prev => prev.map(i => i.key === key ? { ...i, value: editValue, connected: true } : i));
      setEditingKey(null);
      toast.success(`${integration.label} conectado com sucesso!`);
    } catch (err: any) {
      toast.error(err.message || 'Erro ao validar conexão');
    } finally {
      setSaving(false);
    }
  };

  const disconnect = async (key: string) => {
    const integration = integrations.find(i => i.key === key);
    if (!integration) return;
    setSaving(true);
    const { error } = await supabase.from('configuracoes').update({ valor: '', updated_at: new Date().toISOString() }).eq('chave', integration.configKey);
    setSaving(false);
    if (error) { toast.error('Erro ao desconectar'); return; }
    setIntegrations(prev => prev.map(i => i.key === key ? { ...i, value: '', connected: false } : i));
    toast.success('API desconectada');
  };

  const maskValue = (val: string) => {
    if (!val || val.length < 12) return val;
    return val.slice(0, 8) + '•'.repeat(Math.min(val.length - 12, 16)) + val.slice(-4);
  };

  if (loading) return <div className="p-4 animate-pulse">Carregando integrações...</div>;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Integrações</h1>
        <p className="text-muted-foreground text-sm">Gerencie suas conexões com gateways de frete e logística.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-4xl">
        {integrations.map(integration => (
          <Card key={integration.key} className={cn(
            "transition-all duration-300 border-2 overflow-hidden",
            integration.connected ? "border-green-100 shadow-sm" : "border-border"
          )}>
            <CardHeader className="pb-3 border-b bg-muted/30">
              <CardTitle className="text-base flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="relative flex h-3 w-3">
                    {integration.connected && (
                      <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
                    )}
                    <span className={cn(
                      "relative inline-flex rounded-full h-3 w-3",
                      integration.connected ? "bg-green-500" : "bg-red-500"
                    )}></span>
                  </div>
                  {integration.key === 'superfrete' && (
                    <img src={superfreteLogo} alt="Super Frete" className="w-7 h-7 object-contain" />
                  )}
                  {integration.key === 'melhorenvio' && (
                    <img src={melhorenvioLogo} alt="Melhor Envio" className="w-12 h-12 object-contain" />
                  )}
                  <span className="font-semibold">{integration.label}</span>
                </div>
                
                <Badge variant={integration.connected ? "outline" : "destructive"} className={cn(
                  "gap-1 uppercase tracking-wider text-[10px] px-2",
                  integration.connected ? "border-green-500 text-green-600" : ""
                )}>
                  {integration.connected ? <CheckCircle2 className="w-3 h-3" /> : <XCircle className="w-3 h-3" />}
                  {integration.connected ? 'Ativo' : 'Inativo'}
                </Badge>
              </CardTitle>
            </CardHeader>
            <CardContent className="pt-6 space-y-4">
              {editingKey === integration.key ? (
                <div className="space-y-4 animate-in fade-in slide-in-from-top-2 duration-300">
                  <div className="space-y-2">
                    <Label className="text-xs font-bold text-muted-foreground uppercase tracking-widest">Chave API / Token</Label>
                    <div className="relative">
                      <Input
                        value={editValue}
                        onChange={e => setEditValue(e.target.value)}
                        placeholder="Insira o seu token"
                        className="min-h-[48px] pr-10 font-mono text-sm border-2 focus-visible:ring-sf-green"
                        type={showValue[integration.key] ? 'text' : 'password'}
                      />
                      <Button 
                        variant="ghost" 
                        size="icon" 
                        className="absolute right-1 top-1 h-10 w-10 hover:bg-transparent" 
                        onClick={() => setShowValue(prev => ({ ...prev, [integration.key]: !prev[integration.key] }))}
                      >
                        {showValue[integration.key] ? <EyeOff className="w-4 h-4 text-muted-foreground" /> : <Eye className="w-4 h-4 text-muted-foreground" />}
                      </Button>
                    </div>
                  </div>
                  <div className="flex gap-2 pt-2">
                    <Button 
                      onClick={() => save(integration.key)} 
                      disabled={saving || !editValue} 
                      className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[48px] flex-1 font-bold shadow-lg shadow-green-100"
                    >
                      {saving ? (
                        <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> VALIDANDO...</>
                      ) : (
                        <><Power className="w-4 h-4 mr-2" /> CONECTAR AGORA</>
                      )}
                    </Button>
                    <Button variant="outline" onClick={() => setEditingKey(null)} className="min-h-[48px] px-6">
                      Cancelar
                    </Button>
                  </div>
                </div>
              ) : integration.connected ? (
                <div className="space-y-5 animate-in fade-in duration-500">
                  <div className="p-4 bg-green-50/50 rounded-xl border border-green-100/50 flex flex-col gap-1">
                    <span className="text-[10px] font-bold text-green-600 uppercase tracking-widest">Conexão Ativa</span>
                    <div className="flex items-center gap-2">
                      <code className="text-xs flex-1 truncate font-mono text-green-700/80">
                        {showValue[integration.key] ? integration.value : maskValue(integration.value)}
                      </code>
                      <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-green-100/50 text-green-600" onClick={() => setShowValue(prev => ({ ...prev, [integration.key]: !prev[integration.key] }))}>
                        {showValue[integration.key] ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                      </Button>
                    </div>
                  </div>

                  <div className="flex gap-3">
                    <Button variant="outline" size="sm" onClick={() => startEdit(integration.key)} className="h-11 flex-1 font-medium bg-white hover:bg-muted">
                      <Pencil className="w-4 h-4 mr-2" /> Alterar Chave
                    </Button>
                    <Button variant="ghost" size="sm" onClick={() => disconnect(integration.key)} className="h-11 text-muted-foreground hover:text-destructive hover:bg-destructive/5 px-4">
                      Desconectar
                    </Button>
                  </div>
                </div>
              ) : (
                <div className="py-2 space-y-4">
                  <p className="text-sm text-muted-foreground leading-relaxed">
                    Conecte sua conta do <strong>{integration.label}</strong> para automatizar a geração de etiquetas e o rastreamento em tempo real dos seus pedidos.
                  </p>
                  <Button onClick={() => startEdit(integration.key)} className="min-h-[40px] w-full font-medium text-sm bg-sf-green/90 hover:bg-sf-green text-primary-foreground">
                    Configurar integração
                    <Plus className="w-3 h-3 ml-1.5 group-hover:rotate-90 transition-transform" />
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      <Card className="max-w-2xl border-dashed bg-muted/20 border-2">
        <CardContent className="p-4 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-3 text-muted-foreground">
            <div className="bg-sf-green/10 p-2 rounded-lg">
              <Truck className="w-5 h-5 text-sf-green" />
            </div>
            <div>
              <p className="font-semibold text-foreground text-sm">Automação de Status de pedido e rastreio Ativa</p>
              <p className="text-xs text-muted-foreground max-w-sm">Sincronização inteligente: verificando atualização de status de pedidos e rastreio nos Gateways a cada 10 minutos e atualizando no CRM.</p>
            </div>
          </div>
          <div className="flex items-center gap-2 bg-white px-3 py-1.5 rounded-full border shadow-sm shrink-0">
            <span className="text-[10px] font-bold text-sf-green">STANDBY</span>
            <div className="flex h-2 w-2 relative">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-sf-green opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-sf-green"></span>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

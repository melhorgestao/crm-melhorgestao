import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Skeleton } from '@/components/ui/skeleton';
import { Separator } from '@/components/ui/separator';
import { formatDateTime } from '@/lib/format';
import { Switch } from '@/components/ui/switch';
import { ChevronLeft, ChevronRight, Plus, Trash2, Shield, Loader2, Users } from 'lucide-react';
import { toast } from 'sonner';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';

const UF_OPTIONS = [
  'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
  'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SE','SP','TO'
];

export default function AdminPage() {
  const { user, profile } = useAuth();
  const [activeTab, setActiveTab] = useState('usuarios');

  // Logs state
  const [logsLoading, setLogsLoading] = useState(true);
  const [logs, setLogs] = useState<any[]>([]);
  const [logsPage, setLogsPage] = useState(1);
  const [filterUser, setFilterUser] = useState('todos');
  const [filterAction, setFilterAction] = useState('todos');
  const [dateStart, setDateStart] = useState('');
  const [dateEnd, setDateEnd] = useState('');
  const LOGS_PER_PAGE = 50;

  // Users state
  const [users, setUsers] = useState<any[]>([]);
  const [usersLoading, setUsersLoading] = useState(true);
  const [adminContatos, setAdminContatos] = useState<any[]>([]);
  const [adminSocios, setAdminSocios] = useState<Record<string, boolean>>({});
  const [showCreateUser, setShowCreateUser] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<any>(null);
  const [deleteAdminPassword, setDeleteAdminPassword] = useState('');

  // Create user form
  const [formTipo, setFormTipo] = useState<'admin' | 'servico' | 'representante'>('admin');
  const [formApelido, setFormApelido] = useState('');
  const [formEmail, setFormEmail] = useState('');
  const [formSenha, setFormSenha] = useState('');
  const [formServicoTipo, setFormServicoTipo] = useState<'atendimento' | 'logistica'>('atendimento');
  const [formUf, setFormUf] = useState('');
  const [formInstanciaNome, setFormInstanciaNome] = useState('');
  const [formUfInstancia, setFormUfInstancia] = useState('');
  const [formIsSocio, setFormIsSocio] = useState(false);
  const [formCapitalInicial, setFormCapitalInicial] = useState('');
  const [creatingUser, setCreatingUser] = useState(false);

  useEffect(() => {
    fetchLogs();
    fetchUsers();
    fetchAdminContatos();
  }, []);

  const fetchLogs = async () => {
    setLogsLoading(true);
    const { data } = await supabase.from('log_atividades').select('*').order('created_at', { ascending: false }).limit(500);
    setLogs(data || []);
    setLogsLoading(false);
  };

  const fetchUsers = async () => {
    setUsersLoading(true);
    const { data } = await supabase
      .from('perfis_usuario')
      .select('*, instancias(id, nome, dono_tipo)')
      .order('created_at', { ascending: false });
    setUsers(data || []);
    setUsersLoading(false);
  };

  const fetchAdminContatos = async () => {
    const { data: contatos } = await supabase
      .from('contatos')
      .select('id, nome, canal_origem, canal_atual, created_at')
      .eq('canal_origem', 'ADMIN')
      .order('created_at');
    setAdminContatos(contatos || []);

    // Fetch socio status by socio_key (nome do contato = socio_key)
    const { data: perfis } = await supabase
      .from('perfis_usuario')
      .select('socio_key, is_socio')
      .eq('tipo_usuario', 'admin')
      .not('socio_key', 'is', null);
    const socioMap: Record<string, boolean> = {};
    (perfis || []).forEach((p: any) => {
      if (p.socio_key) socioMap[p.socio_key.toUpperCase()] = p.is_socio || false;
    });
    setAdminSocios(socioMap);
  };

  const handleCreateUser = async () => {
    if (!formApelido.trim() || !formEmail.trim()) {
      toast.error('Preencha todos os campos obrigatórios');
      return;
    }

    if (!formSenha.trim()) {
      toast.error('Defina uma senha');
      return;
    }

    if (formTipo === 'representante' && !formInstanciaNome.trim()) {
      toast.error('Informe o nome da instância do representante');
      return;
    }

    if (formTipo === 'representante' && !formUfInstancia) {
      toast.error('Selecione a UF da instância do representante');
      return;
    }

    if (formTipo === 'servico' && formServicoTipo === 'logistica' && !formUf) {
      toast.error('Usuário de Logística precisa ter uma UF definida');
      return;
    }

    setCreatingUser(true);

    try {
      // Step 1: Create auth user via signUp (triggers auto-profile)
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: formEmail.trim(),
        password: formSenha,
        options: {
          data: {
            apelido: formApelido.trim(),
            tipo_usuario: formTipo,
            socio_key: formTipo === 'admin' ? formApelido.trim().charAt(0).toUpperCase() : null,
          },
        },
      });

      if (authError) throw authError;
      if (!authData.user) throw new Error('Erro ao criar usuário');

      const userId = authData.user.id;

      // Step 2: Update profile with full info
      const { error: profileError } = await supabase
        .from('perfis_usuario')
        .update({
          tipo_usuario: formTipo,
          servico_tipo: formTipo === 'servico' ? formServicoTipo : null,
          uf_fixa: formTipo === 'servico' && formServicoTipo === 'logistica' ? formUf : null,
          acesso_kanban: formTipo === 'servico' && formServicoTipo === 'atendimento' ? 'kanban'
            : formTipo === 'servico' && formServicoTipo === 'logistica' ? 'logistica'
            : 'todos',
          ver_menu: formTipo === 'representante' ? ['representante']
            : formTipo === 'servico' ? [formServicoTipo]
            : ['todos'],
          socio_key: formTipo === 'admin' && formIsSocio ? formApelido.trim().charAt(0).toUpperCase() : null,
          is_socio: formTipo === 'admin' ? formIsSocio : false,
        })
        .eq('user_id', userId);

      if (profileError) throw profileError;

      // Step 2.5: If socio with capital inicial, insert lancamento_socios
      if (formTipo === 'admin' && formIsSocio && formCapitalInicial.trim()) {
        const capital = parseFloat(formCapitalInicial.replace(',', '.'));
        if (!isNaN(capital) && capital > 0) {
          const adminLabel = profile?.nome || 'Admin';
          await supabase.from('lancamentos_socios').insert({
            socio: formApelido.trim().charAt(0).toUpperCase(),
            tipo: 'CAPITAL_INICIAL',
            valor: capital,
            descricao: `Capital inicial de ${formApelido.trim()}`,
            status_pagamento: '-',
            criado_por: adminLabel,
            realizado: true,
          });
        }
      }

      // Step 3: If representante, create instancia
      let instanciaId: string | null = null;
      if (formTipo === 'representante') {
        const { data: instData, error: instError } = await supabase
          .from('instancias')
          .insert({
            nome: formInstanciaNome.trim(),
            tipo: 'rep',
            dono_tipo: 'representante',
            uf_fixa: formUfInstancia,
            representante_user_id: userId,
            ativo: true,
          })
          .select('id')
          .single();

        if (instError) throw instError;
        instanciaId = instData.id;

        // Link profile to instancia
        await supabase.from('perfis_usuario').update({ instancia_id: instanciaId }).eq('user_id', userId);
      }

      toast.success('Usuário criado com sucesso!');
      setShowCreateUser(false);
      resetCreateForm();
      fetchUsers();
    } catch (err: any) {
      toast.error(err.message || 'Erro ao criar usuário');
    } finally {
      setCreatingUser(false);
    }
  };

  const handleDeleteUser = async () => {
    if (!deleteTarget) return;
    if (!deleteAdminPassword.trim()) {
      toast.error('Digite a senha do admin para confirmar');
      return;
    }

    try {
      const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
      const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/deletar_usuario`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify({
          p_user_id: deleteTarget.user_id,
          p_admin_password: deleteAdminPassword,
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(errorText || 'Erro ao deletar usuário');
      }

      toast.success('Usuário removido!');
      setDeleteTarget(null);
      setDeleteAdminPassword('');
      fetchUsers();
    } catch (err: any) {
      toast.error(err.message || 'Erro ao deletar usuário');
    }
  };

  const resetCreateForm = () => {
    setFormTipo('admin');
    setFormApelido('');
    setFormEmail('');
    setFormSenha('');
    setFormServicoTipo('atendimento');
    setFormUf('');
    setFormInstanciaNome('');
    setFormUfInstancia('');
    setFormIsSocio(false);
    setFormCapitalInicial('');
  };

  // Admins aparecem só em "Contatos de Admin"; demais usuários (representante/serviço) ficam aqui
  const filteredUsers = users.filter((u: any) => u.tipo_usuario !== 'admin');

  // Logs filtering
  let filteredLogs = [...logs];
  if (filterUser !== 'todos') filteredLogs = filteredLogs.filter(l => l.usuario === filterUser);
  if (filterAction !== 'todos') filteredLogs = filteredLogs.filter(l => l.acao.includes(filterAction));
  if (dateStart) filteredLogs = filteredLogs.filter(l => l.created_at >= dateStart);
  if (dateEnd) filteredLogs = filteredLogs.filter(l => l.created_at <= dateEnd + 'T23:59:59');

  const pagedLogs = filteredLogs.slice((logsPage - 1) * LOGS_PER_PAGE, logsPage * LOGS_PER_PAGE);
  const totalLogPages = Math.ceil(filteredLogs.length / LOGS_PER_PAGE);
  const logUsers = [...new Set(logs.map(l => l.usuario))];

  if (usersLoading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Administração</h1>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="usuarios">Usuários</TabsTrigger>
          <TabsTrigger value="logs">Logs</TabsTrigger>
        </TabsList>

        {/* ==================== USUARIOS TAB ==================== */}
        <TabsContent value="usuarios" className="space-y-6">
          {/* Seção 1: Usuários do Sistema (CRM Pai) */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold flex items-center gap-2">
                <Shield className="w-5 h-5" />
                Usuários do Sistema
              </h2>
              <Button onClick={() => { resetCreateForm(); setShowCreateUser(true); }} className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground">
                <Plus className="w-4 h-4 mr-1" /> Novo Usuário
              </Button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b font-bold">
                    <th className="text-left py-2 w-[18%]">Apelido</th>
                    <th className="text-left py-2 w-[22%]">Email</th>
                    <th className="text-left py-2 w-[16%]">Tipo</th>
                    <th className="text-left py-2 w-[12%]">Serviço/UF</th>
                    <th className="text-left py-2 w-[12%]">Instância</th>
                    <th className="py-2 w-[10%]"></th>
                  </tr>
                </thead>
                <tbody>
                  {filteredUsers.length === 0 && (
                    <tr><td colSpan={6} className="text-center text-muted-foreground py-8">Nenhum usuário encontrado</td></tr>
                  )}
                  {filteredUsers.map(u => (
                    <tr key={u.id} className="border-b border-border/50">
                      <td className="py-2 font-medium">{u.nome || '—'}</td>
                      <td className="py-2 text-muted-foreground">{u.email || '—'}</td>
                      <td className="py-2">
                        <span className={`px-2 py-0.5 rounded text-xs font-medium ${
                          u.tipo_usuario === 'admin' ? 'bg-primary/10 text-primary' :
                          u.tipo_usuario === 'servico' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300' :
                          'bg-sf-green/10 text-sf-green'
                        }`}>
                          {u.tipo_usuario === 'admin' ? 'Admin' : u.tipo_usuario === 'servico' ? `Serviço (${u.servico_tipo})` : 'Representante'}
                        </span>
                      </td>
                      <td className="py-2 text-muted-foreground">
                        {u.tipo_usuario === 'servico' && u.uf_fixa ? u.uf_fixa : '—'}
                      </td>
                      <td className="py-2 text-muted-foreground">
                        {u.instancias?.nome || '—'}
                      </td>
                      <td className="py-2">
                        <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => setDeleteTarget(u)}>
                          <Trash2 className="w-3 h-3" />
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Seção 2: Contatos Admin */}
          <div className="space-y-4">
            <Separator />
            <h2 className="text-lg font-semibold flex items-center gap-2">
              <Users className="w-5 h-5" />
              Contatos de Admin
            </h2>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b font-bold">
                    <th className="text-left py-2 w-[25%]">Apelido</th>
                    <th className="text-left py-2 w-[20%]">Canal</th>
                    <th className="text-left py-2 w-[20%]">Criado em</th>
                    <th className="text-left py-2 w-[15%]">É Sócio?</th>
                  </tr>
                </thead>
                <tbody>
                  {adminContatos.length === 0 && (
                    <tr><td colSpan={4} className="text-center text-muted-foreground py-8">Nenhum contato admin encontrado</td></tr>
                  )}
                  {adminContatos.map(c => {
                    const isSocio = c.nome === 'V' || c.nome === 'A';
                    return (
                    <tr key={c.id} className="border-b border-border/50">
                      <td className="py-2 font-medium">{c.nome}</td>
                      <td className="py-2 text-muted-foreground">{c.canal_origem}</td>
                      <td className="py-2 text-muted-foreground">{formatDateTime(c.created_at)}</td>
                      <td className="py-2">
                        {isSocio ? (
                          <span className="px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-700">Sim</span>
                        ) : (
                          <span className="px-2 py-0.5 rounded text-xs font-medium bg-muted text-muted-foreground">Não</span>
                        )}
                      </td>
                    </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        </TabsContent>

        {/* ==================== LOGS TAB ==================== */}
        <TabsContent value="logs" className="space-y-4">
          <div className="flex flex-wrap gap-3 items-center">
            <Input type="date" value={dateStart} onChange={e => setDateStart(e.target.value)} className="w-40" placeholder="De" />
            <Input type="date" value={dateEnd} onChange={e => setDateEnd(e.target.value)} className="w-40" placeholder="Até" />
            <Select value={filterUser} onValueChange={setFilterUser}>
              <SelectTrigger className="w-40"><SelectValue placeholder="Usuário" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="todos">Todos</SelectItem>
                {logUsers.map(u => <SelectItem key={u} value={u}>{u}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={filterAction} onValueChange={setFilterAction}>
              <SelectTrigger className="w-40"><SelectValue placeholder="Ação" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="todos">Todas</SelectItem>
                <SelectItem value="Editou">Edição</SelectItem>
                <SelectItem value="Excluiu">Exclusão</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {logsLoading ? <Skeleton className="h-96" /> : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead><tr className="border-b font-bold"><th className="text-left py-2">Data/Hora</th><th className="text-left py-2">Usuário</th><th className="text-left py-2">Ação</th><th className="text-left py-2">Detalhe</th></tr></thead>
                  <tbody>
                    {pagedLogs.length === 0 && (
                      <tr><td colSpan={4} className="text-center text-muted-foreground py-8">Nenhum log encontrado</td></tr>
                    )}
                    {pagedLogs.map(l => (
                      <tr key={l.id} className="border-b border-border/50">
                        <td className="py-2">{formatDateTime(l.created_at)}</td>
                        <td className="py-2">{l.usuario}</td>
                        <td className="py-2">{l.acao}</td>
                        <td className="py-2">{l.detalhe || '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className="flex justify-end gap-2">
                <Button variant="outline" size="sm" disabled={logsPage <= 1} onClick={() => setLogsPage(p => p - 1)}><ChevronLeft className="w-4 h-4" /> Anterior</Button>
                <span className="text-sm flex items-center">{logsPage}/{totalLogPages || 1}</span>
                <Button variant="outline" size="sm" disabled={logsPage >= totalLogPages} onClick={() => setLogsPage(p => p + 1)}>Próxima <ChevronRight className="w-4 h-4" /></Button>
              </div>
            </>
          )}
        </TabsContent>
      </Tabs>

      {/* ==================== CREATE USER DIALOG ==================== */}
      <Dialog open={showCreateUser} onOpenChange={(open) => { setShowCreateUser(open); if (!open) resetCreateForm(); }}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Novo Usuário</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Tipo de Usuário</Label>
              <Select value={formTipo} onValueChange={v => setFormTipo(v as any)}>
                <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="admin">Admin</SelectItem>
                  <SelectItem value="servico">Serviço</SelectItem>
                  <SelectItem value="representante">Representante</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <Separator />

            <div>
              <Label>Apelido</Label>
              <Input value={formApelido} onChange={e => setFormApelido(e.target.value)} placeholder="Ex: João" className="min-h-[44px]" />
            </div>
            <div>
              <Label>Email</Label>
              <Input type="email" value={formEmail} onChange={e => setFormEmail(e.target.value)} placeholder="email@exemplo.com" className="min-h-[44px]" />
            </div>
            <div>
              <Label>Senha</Label>
              <Input type="password" value={formSenha} onChange={e => setFormSenha(e.target.value)} placeholder="••••••••" className="min-h-[44px]" />
            </div>

            {formTipo === 'admin' && (
              <div className="flex items-center justify-between p-3 border rounded-lg">
                <div>
                  <Label className="text-sm font-medium">É Sócio?</Label>
                  <p className="text-xs text-muted-foreground">Aparecerá como card no Financeiro</p>
                </div>
                <Switch checked={formIsSocio} onCheckedChange={setFormIsSocio} className="data-[state=checked]:bg-sf-green" />
              </div>
            )}

            {formTipo === 'admin' && formIsSocio && (
              <div>
                <Label>Capital Inicial (R$)</Label>
                <Input value={formCapitalInicial} onChange={e => setFormCapitalInicial(e.target.value)} placeholder="0,00" className="min-h-[44px]" />
                <p className="text-xs text-muted-foreground mt-1">Saldo inicial do sócio no Financeiro (não aparece nos lançamentos)</p>
              </div>
            )}

            {formTipo === 'servico' && (
              <>
                <Separator />
                <div>
                  <Label>Tipo de Serviço</Label>
                  <Select value={formServicoTipo} onValueChange={v => setFormServicoTipo(v as any)}>
                    <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="atendimento">Atendimento</SelectItem>
                      <SelectItem value="logistica">Logística</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {formServicoTipo === 'logistica' && (
                  <div>
                    <Label>UF</Label>
                    <Select value={formUf} onValueChange={setFormUf}>
                      <SelectTrigger className="min-h-[44px]"><SelectValue placeholder="Selecionar UF" /></SelectTrigger>
                      <SelectContent>
                        {UF_OPTIONS.map(uf => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                )}
              </>
            )}

            {formTipo === 'representante' && (
              <>
                <Separator />
                <div>
                  <Label>Nome da Instância</Label>
                  <Input value={formInstanciaNome} onChange={e => setFormInstanciaNome(e.target.value)} placeholder="Ex: João Silva - Representante SP" className="min-h-[44px]" />
                </div>
                <div>
                  <Label>UF da Instância</Label>
                  <Select value={formUfInstancia} onValueChange={setFormUfInstancia}>
                    <SelectTrigger className="min-h-[44px]"><SelectValue placeholder="Selecionar UF..." /></SelectTrigger>
                    <SelectContent>
                      {UF_OPTIONS.map(uf => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </>
            )}

            <Button onClick={handleCreateUser} disabled={creatingUser} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px]">
              {creatingUser ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Criar Usuário'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ==================== DELETE USER DIALOG ==================== */}
      <AlertDialog open={!!deleteTarget} onOpenChange={() => { setDeleteTarget(null); setDeleteAdminPassword(''); }}>
        <AlertDialogContent>
          <AlertDialogHeader><AlertDialogTitle>Remover Usuário</AlertDialogTitle><AlertDialogDescription>
            Para remover <strong>{deleteTarget?.nome}</strong>, digite a senha do admin que criou este usuário.
          </AlertDialogDescription></AlertDialogHeader>
          <div className="space-y-3">
            <Label>Senha do Admin</Label>
            <Input type="password" value={deleteAdminPassword} onChange={e => setDeleteAdminPassword(e.target.value)} placeholder="••••••••" className="min-h-[44px]" />
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteUser} className="bg-destructive text-destructive-foreground">Remover</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { formatDateTime } from '@/lib/format';
import { ChevronLeft, ChevronRight } from 'lucide-react';

export default function LogsPage() {
  const [loading, setLoading] = useState(true);
  const [logs, setLogs] = useState<any[]>([]);
  const [page, setPage] = useState(1);
  const [filterUser, setFilterUser] = useState('todos');
  const [filterAction, setFilterAction] = useState('todos');
  const [dateStart, setDateStart] = useState('');
  const [dateEnd, setDateEnd] = useState('');
  const PER_PAGE = 50;

  useEffect(() => { fetchLogs(); }, []);

  const fetchLogs = async () => {
    setLoading(true);
    const { data } = await supabase.from('log_atividades').select('*').order('created_at', { ascending: false }).limit(500);
    setLogs(data || []);
    setLoading(false);
  };

  let filtered = [...logs];
  if (filterUser !== 'todos') filtered = filtered.filter(l => l.usuario === filterUser);
  if (filterAction !== 'todos') filtered = filtered.filter(l => l.acao.includes(filterAction));
  if (dateStart) filtered = filtered.filter(l => l.created_at >= dateStart);
  if (dateEnd) filtered = filtered.filter(l => l.created_at <= dateEnd + 'T23:59:59');

  const paged = filtered.slice((page - 1) * PER_PAGE, page * PER_PAGE);
  const totalPages = Math.ceil(filtered.length / PER_PAGE);
  const users = [...new Set(logs.map(l => l.usuario))];

  if (loading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold">Logs</h1>

      <div className="flex flex-wrap gap-3 items-center">
        <Input type="date" value={dateStart} onChange={e => setDateStart(e.target.value)} className="w-40" placeholder="De" />
        <Input type="date" value={dateEnd} onChange={e => setDateEnd(e.target.value)} className="w-40" placeholder="Até" />
        <Select value={filterUser} onValueChange={setFilterUser}>
          <SelectTrigger className="w-40"><SelectValue placeholder="Usuário" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="todos">Todos</SelectItem>
            {users.map(u => <SelectItem key={u} value={u}>{u}</SelectItem>)}
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

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead><tr className="border-b font-bold"><th className="text-left py-2">Data/Hora</th><th className="text-left py-2">Usuário</th><th className="text-left py-2">Ação</th><th className="text-left py-2">Detalhe</th></tr></thead>
          <tbody>
            {paged.length === 0 && (
              <tr><td colSpan={4} className="text-center text-muted-foreground py-8">Nenhum log encontrado</td></tr>
            )}
            {paged.map(l => (
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
        <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}><ChevronLeft className="w-4 h-4" /> Anterior</Button>
        <span className="text-sm flex items-center">{page}/{totalPages || 1}</span>
        <Button variant="outline" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>Próxima <ChevronRight className="w-4 h-4" /></Button>
      </div>
    </div>
  );
}

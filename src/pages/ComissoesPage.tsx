import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { formatBRL } from '@/lib/format';
import { cn } from '@/lib/utils';

export default function ComissoesPage() {
  const { user } = useAuth();
  const [filterStatus, setFilterStatus] = useState('todos');

  const { data: comissoes, isLoading } = useQuery({
    queryKey: ['comissoes', user?.id],
    queryFn: async () => {
      const { data } = await supabase
        .from('comissoes')
        .select('*, pedidos(order_number, status_pedido)')
        .eq('representante_id', user?.id)
        .order('data_criacao', { ascending: false });
      return data || [];
    },
    staleTime: 5 * 60 * 1000,
  });

  const { data: totalPendente } = useQuery({
    queryKey: ['comissoes-total-pendente', user?.id],
    queryFn: async () => {
      const { data } = await supabase
        .from('comissoes')
        .select('valor_fixo')
        .eq('representante_id', user?.id)
        .eq('status', 'pendente');
      return (data || []).reduce((sum: number, c: any) => sum + Number(c.valor_fixo), 0);
    },
    staleTime: 5 * 60 * 1000,
  });

  const { data: totalPago } = useQuery({
    queryKey: ['comissoes-total-pago', user?.id],
    queryFn: async () => {
      const { data } = await supabase
        .from('comissoes')
        .select('valor_fixo')
        .eq('representante_id', user?.id)
        .eq('status', 'pago');
      return (data || []).reduce((sum: number, c: any) => sum + Number(c.valor_fixo), 0);
    },
    staleTime: 5 * 60 * 1000,
  });

  const filtered = (comissoes || []).filter(c => filterStatus === 'todos' || c.status === filterStatus);

  if (isLoading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Comissões</h1>

      <div className="grid grid-cols-2 gap-4 max-w-sm">
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-sm font-bold text-muted-foreground">Pendente</p>
            <p className="text-xl font-bold text-orange-500">{formatBRL(totalPendente || 0)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-sm font-bold text-muted-foreground">Pago</p>
            <p className="text-xl font-bold text-sf-green">{formatBRL(totalPago || 0)}</p>
          </CardContent>
        </Card>
      </div>

      <Separator />

      <div className="flex gap-2">
        {['todos', 'pendente', 'pago'].map(s => (
          <Button key={s} variant={filterStatus === s ? 'default' : 'outline'} size="sm" onClick={() => setFilterStatus(s)}>
            {s === 'todos' ? 'Todas' : s === 'pendente' ? 'Pendentes' : 'Pagas'}
          </Button>
        ))}
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b font-bold">
              <th className="text-left py-2 w-[15%]">Data</th>
              <th className="text-left py-2 w-[15%]">Pedido</th>
              <th className="text-left py-2 w-[30%]">Produto</th>
              <th className="text-right py-2 w-[15%]">Valor</th>
              <th className="text-left py-2 w-[15%]">Status</th>
              <th className="text-left py-2 w-[10%]">Pgto</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 && (
              <tr><td colSpan={6} className="text-center text-muted-foreground py-8">Nenhuma comissão encontrada</td></tr>
            )}
            {filtered.map(c => (
              <tr key={c.id} className="border-b border-border/50">
                <td className="py-2">{new Date(c.data_criacao).toLocaleDateString('pt-BR')}</td>
                <td className="py-2 font-medium">#{c.pedidos?.order_number || '—'}</td>
                <td className="py-2 truncate">{c.produto}</td>
                <td className="py-2 text-right font-medium">{formatBRL(Number(c.valor_fixo))}</td>
                <td className="py-2">
                  <Badge variant={c.status === 'pago' ? 'default' : c.status === 'pendente' ? 'outline' : 'destructive'}>
                    {c.status === 'pendente' ? 'Pendente' : c.status === 'pago' ? 'Pago' : 'Cancelado'}
                  </Badge>
                </td>
                <td className="py-2 text-muted-foreground">{c.data_pagamento ? new Date(c.data_pagamento).toLocaleDateString('pt-BR') : '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

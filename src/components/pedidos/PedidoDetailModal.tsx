/**
 * Modal Detalhes do Pedido — reutilizável.
 * Pode receber o pedido já carregado (via prop `pedido`) OU um `pedidoId` que
 * dispara o fetch aqui (útil pra abrir a partir do Kanban).
 */
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Copy, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { copyToClipboard } from '@/lib/utils';
import { getTagDisplayName } from '@/lib/productDisplayNames';

function formatBRL(v: any) {
  const n = Number(v || 0);
  return n.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

interface Props {
  open: boolean;
  onClose: () => void;
  pedido?: any | null;
  pedidoId?: string | null;
}

export function PedidoDetailModal({ open, onClose, pedido: pedidoProp, pedidoId }: Props) {
  const [pedido, setPedido] = useState<any | null>(pedidoProp || null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!open) return;
    if (pedidoProp) { setPedido(pedidoProp); return; }
    if (!pedidoId) { setPedido(null); return; }
    setLoading(true);
    (async () => {
      const { data } = await supabase
        .from('pedidos')
        .select('*, contatos(nome, telefone, cpf, endereco, complemento, bairro, cidade_uf, cep)')
        .eq('id', pedidoId).maybeSingle();
      setPedido(data);
      setLoading(false);
    })();
  }, [open, pedidoProp, pedidoId]);

  const valor = pedido ? (pedido.valor_total ?? pedido.valor ?? 0) : 0;

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Detalhes do Pedido {pedido?.order_number ? '#' + pedido.order_number : ''}</DialogTitle>
        </DialogHeader>
        {loading ? (
          <div className="py-10 flex justify-center"><Loader2 className="w-6 h-6 animate-spin" /></div>
        ) : pedido ? (
          <div className="space-y-2 text-sm">
            <div>
              <strong>Produtos:</strong>
              {(() => {
                try {
                  const prods = JSON.parse(pedido.produto);
                  if (Array.isArray(prods)) {
                    return prods.map((p: any, i: number) => (
                      <p key={i} className="ml-2">• {getTagDisplayName(p.produto)} × {p.quantidade}</p>
                    ));
                  }
                } catch {}
                return <p className="ml-2">{getTagDisplayName(pedido.produto)} × {pedido.quantidade}</p>;
              })()}
            </div>
            <p><strong>Valor Total:</strong> {pedido.is_free ? <span className="text-sky-600 font-bold">FREE</span> : formatBRL(valor)}</p>
            <p><strong>CPF:</strong> {(pedido.contatos as any)?.cpf || '—'}</p>
            <p><strong>Endereço:</strong> {(pedido.contatos as any)?.endereco || '—'}</p>
            <p><strong>Complemento:</strong> {(pedido.contatos as any)?.complemento || '—'}</p>
            <p><strong>Bairro:</strong> {(pedido.contatos as any)?.bairro || '—'}</p>
            <p><strong>Cidade/UF:</strong> {(pedido.contatos as any)?.cidade_uf || '—'}</p>
            <p><strong>CEP:</strong> {(pedido.contatos as any)?.cep || '—'}</p>
            <p><strong>UF Postagem:</strong> {pedido.uf_postagem || '—'}</p>
            <p><strong>Canal:</strong> {pedido.canal}</p>
            <p><strong>Status:</strong> {pedido.status_pedido === 'entregue' ? 'Entregue' : pedido.status_pedido === 'postado' ? 'Postado' : 'Aguardando Postagem'}</p>
            <p>
              <strong>Rastreio:</strong> {pedido.codigo_rastreio || 'Aguardando rastreio'}
              {pedido.codigo_rastreio && (
                <Button variant="ghost" size="icon" className="h-6 w-6 ml-1"
                        onClick={() => copyToClipboard(pedido.codigo_rastreio).then(s => s && toast.success('Código copiado!'))}>
                  <Copy className="w-3 h-3" />
                </Button>
              )}
            </p>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground py-4">Pedido não encontrado.</p>
        )}
      </DialogContent>
    </Dialog>
  );
}

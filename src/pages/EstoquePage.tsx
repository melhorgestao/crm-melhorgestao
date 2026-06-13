import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { formatDateShort } from '@/lib/format';
import { getProductDisplayName, getTagDisplayName } from '@/lib/productDisplayNames';
import { Plus, ExternalLink, User, Package, Palette, Edit2, Trash2, ChevronLeft, ChevronRight, MapPin } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';

const UF_LIST_FALLBACK = ['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'];

// Ocultação visual: lista de movimentações mostra apenas registros recentes.
// NÃO afeta saldos (cards UF/Total vêm de estoque_snapshot, calculado de pedidos+lotes).
const DIAS_OCULTACAO_MOV = 180;
const getDataLimiteMov = () =>
  new Date(Date.now() - DIAS_OCULTACAO_MOV * 86400000).toISOString().slice(0, 10);

/** Relação explícita: evita embed errado quando há várias FKs envolvendo pedidos. */
const MOV_PEDIDO_EMBED =
  'pedidos!estoque_movimentacoes_pedido_id_fkey(order_number, uf_postagem, contatos(nome, uf, cidade_uf))';

function ufClienteFromMov(m: {
  pedidos?: { contatos?: { uf?: string | null; cidade_uf?: string | null } } | null;
}): string {
  const ct = m.pedidos?.contatos;
  if (!ct) return '—';
  const u = (ct.uf || '').trim().toUpperCase();
  if (u) return u;
  const cu = (ct.cidade_uf || '').trim();
  const parts = cu.split('/');
  const last = parts[parts.length - 1]?.trim().toUpperCase();
  if (last && last.length === 2) return last;
  return '—';
}

const CORES_CARDS = [
  // Favoritas (2 linhas)
  '#ffffff', '#f8fafc', '#e2e8f0', '#94a3b8', '#fef9c3', '#fef08a', '#fee2e2', '#fecaca',
  '#ef4444', '#dc2626', '#fb7185', '#f43f5e', '#a855f7', '#9333ea', '#3b82f6', '#2563eb',
  '#22c55e', '#16a34a', '#fb923c', '#f97316', '#f0fdf4', '#dcfce7', '#e9d5ff', '#d8b4fe',
];

export default function EstoquePage() {
  const { profile } = useAuth();
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [activeTab, setActiveTab] = useState('estoque');
  
  // Grupos state
  const [grupos, setGrupos] = useState<any[]>([]);
  const [editProduct, setEditProduct] = useState<any>(null);
  const [deleteProduct, setDeleteProduct] = useState<any>(null);
  const [showAddProduct, setShowAddProduct] = useState(false);
  
  // Form add/edit product
  const [formNome, setFormNome] = useState('');
  const [formTag, setFormTag] = useState('');
  const [formCorCard, setFormCorCard] = useState('#ffffff');
  const [formCorTexto, setFormCorTexto] = useState('#000000');
  const [formLimite, setFormLimite] = useState(0);
  const [formGrupo, setFormGrupo] = useState('');
  const [formBoxSize, setFormBoxSize] = useState('');
  const [formBoxQtyMax, setFormBoxQtyMax] = useState(10);
  const [formPeso, setFormPeso] = useState(300);
  const [formPreco, setFormPreco] = useState<string>('');

  // Estoque state
  const [produtos, setProdutos] = useState<any[]>([]);
  const [movimentacoes, setMovimentacoes] = useState<any[]>([]);
  const [lotesByProduct, setLotesByProduct] = useState<Record<string, { uf: string; qty: number }[]>>({});
  const [showForm, setShowForm] = useState(false);
  const [formRows, setFormRows] = useState<{ produto_id: string; quantidade: number }[]>([{ produto_id: '', quantidade: 1 }]);
  const [formUF, setFormUF] = useState('');
  const [lastLoteCodigo, setLastLoteCodigo] = useState('');

  const [movDetail, setMovDetail] = useState<any>(null);
  const [detailPedido, setDetailPedido] = useState<any>(null);

  const [repStock, setRepStock] = useState<{ rep_nome: string; produto_nome: string; quantidade: number; uf: string }[]>([]);
  
  // Grupo management
  const [showCreateGroup, setShowCreateGroup] = useState(false);
  const [formGroupNome, setFormGroupNome] = useState('');
  const [formGroupCor, setFormGroupCor] = useState('#ffffff');
  const [submittingGroup, setSubmittingGroup] = useState(false);
  const [selectedGroupId, setSelectedGroupId] = useState<string | null>(null);
  const [selectedGroupInCadastro, setSelectedGroupInCadastro] = useState<any>(null);
  const [editGroup, setEditGroup] = useState<any>(null);
  const [deleteGroup, setDeleteGroup] = useState<any>(null);

  // Pagination
  const [pageGrupos, setPageGrupos] = useState(0);
  const [pageProdutosEstoque, setPageProdutosEstoque] = useState(0);
  const [pageProdutosCadastro, setPageProdutosCadastro] = useState(0);
  const [pageMovimentacoes, setPageMovimentacoes] = useState(0);
  const [totalMovCount, setTotalMovCount] = useState(0);
  const PAGE_SIZE_GRUPOS = 20;
  const PAGE_SIZE_PRODUTOS_ESTOQUE = 30;
  const PAGE_SIZE_PRODUTOS_CADASTRO = 25;
  const PAGE_SIZE_MOVIMENTACOES = 50;
  const totalPagesMovimentacoes = Math.ceil(totalMovCount / PAGE_SIZE_MOVIMENTACOES);

  // UFs dinâmicas
  const [estoqueUfs, setEstoqueUfs] = useState<string[]>([]);
  const [showAddUf, setShowAddUf] = useState(false);
  const [newUf, setNewUf] = useState('');
  const [deleteUfTarget, setDeleteUfTarget] = useState<string | null>(null);
  const [submittingUf, setSubmittingUf] = useState(false);
  
  // Regiões de UF state
  const [ufRegioes, setUfRegioes] = useState<{ id: string; uf: string; tag: string; codigo: string }[]>([]);
  const [showAddRegion, setShowAddRegion] = useState(false);
  const [newRegionTag, setNewRegionTag] = useState('');
  const [selectedUfForRegion, setSelectedUfForRegion] = useState('');
  const [deleteRegionTarget, setDeleteRegionTarget] = useState<{ id: string; codigo: string } | null>(null);

  // Limpeza de movimentações
  const [confirmDeleteOld, setConfirmDeleteOld] = useState(false);
  const [cleaningUp, setCleaningUp] = useState(false);

  // Busca movimentações
  const [movSearch, setMovSearch] = useState('');

  useEffect(() => { fetchAll(); }, []);

  const fetchAll = async () => {
    setLoading(true);
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    // Buscar produtos (incluindo inativos para gestão)
    const { data: prods } = await supabase.from('produtos').select('*, produtos_grupos(nome)').order('nome_oficial');
    setProdutos(prods || []);
    
    // Buscar grupos
    const { data: grps } = await supabase.from('produtos_grupos').select('*').order('ordem');
    setGrupos(grps || []);

    // Buscar UFs dinâmicas
    const { data: ufsData } = await supabase.from('estoque_ufs' as any).select('uf').order('uf');
    const ufs = ufsData ? (ufsData as any[]).map((u: any) => u.uf) : [];
    setEstoqueUfs(ufs);

    // Buscar Regiões
    const { data: regionsData } = await supabase.from('uf_regioes' as any).select('*').order('codigo');
    setUfRegioes((regionsData as any[] || []) as { id: string; uf: string; tag: string; codigo: string }[]);
    
    // Buscar estoque com negativo via fetch RPC (bypass PostgREST)
    const { data: sessionData } = await supabase.auth.getSession();
    const accessToken = sessionData?.session?.access_token || SUPABASE_KEY;
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_estoque_completo`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_KEY,
        'Authorization': `Bearer ${accessToken}`,
      },
    });
    
    const estoqueData = response.ok ? await response.json() : [];
    const EstoquePorProduto: Record<string, { uf: string; qty: number }[]> = {};
    
    if (estoqueData && Array.isArray(estoqueData)) {
      (estoqueData as any[]).forEach((item: any) => {
        const pid = item.prod_id;
        if (!EstoquePorProduto[pid]) EstoquePorProduto[pid] = [];
        const normalizedUF = (item.estado || item.uf || 'SP').trim().toUpperCase();
        EstoquePorProduto[pid].push({ uf: normalizedUF, qty: item.saldo || 0 });
      });
    }
    setLotesByProduct(EstoquePorProduto);
    
    // Movimentacoes com paginação e join no cliente
    // Filtro visual de 180 dias: NÃO afeta cards (que vêm de estoque_snapshot)
    const dataLimiteMov = getDataLimiteMov();
    const { count } = await supabase
      .from('estoque_movimentacoes')
      .select('*', { count: 'exact', head: true })
      .gte('data', dataLimiteMov);
    setTotalMovCount(count || 0);
    
    const { data: movs } = await supabase
      .from('estoque_movimentacoes')
      .select(`*,produtos(nome_oficial,tag),lotes(lote_codigo),${MOV_PEDIDO_EMBED}`)
      .gte('data', dataLimiteMov)
      .order('data', { ascending: false })
      .limit(PAGE_SIZE_MOVIMENTACOES);
    setMovimentacoes(movs || []);

    const { data: repLotes } = await supabase
      .from('lotes')
      .select('*, produtos(nome_oficial)')
      .not('representante_id', 'is', null)
      .gt('quantidade_atual', 0);

    const repMap: Record<string, string> = {};
    (repLotes || []).forEach((l: any) => {
      if (l.representante_id) repMap[l.representante_id] = l.representante_id?.slice(0, 8);
    });

    const repStockData: { rep_nome: string; produto_nome: string; quantidade: number; uf: string }[] = [];
    (repLotes || []).forEach(l => {
      repStockData.push({
        rep_nome: repMap[l.representante_id] || l.representante_id?.slice(0, 8) || '—',
        produto_nome: l.produtos?.nome_oficial || l.produto_id?.slice(0, 8) || '—',
        quantidade: l.quantidade_atual,
        uf: l.uf || '—',
      });
    });
    setRepStock(repStockData);

    setLoading(false);
  };

  const handleMovClick = async (m: any) => {
    const pedIdRaw = m.pedido_id as string | undefined | null;
    let ped: any = m.pedidos ?? m.pedido;

    if (pedIdRaw) {
      const { data } = await supabase
        .from('pedidos')
        .select('*, contatos(nome, uf, cidade_uf)')
        .eq('id', pedIdRaw)
        .maybeSingle();
      if (data) ped = data;
    } else {
      const fromOrderNum = m.observacao?.match(/Pedido #(\d+)/);
      const fromUuid = m.observacao?.match(
        /Pedido #([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/
      );
      const matchParen = m.observacao?.match(/\(Pedido ([a-zA-Z0-9-]+)\)/);
      const token = fromOrderNum?.[1] || fromUuid?.[1] || matchParen?.[1];
      if (token) {
        const isUuid = token.includes('-') && token.length > 20;
        let q = supabase.from('pedidos').select('*, contatos(nome, uf, cidade_uf)');
        q = isUuid ? q.eq('id', token) : q.eq('order_number', parseInt(token, 10));
        const { data } = await q.maybeSingle();
        if (data) ped = data;
      }
    }

    const criadoPor = m.criado_por || (m.lotes?.lote_codigo ? 'Sistema' : '—');
    setMovDetail({
      ...m,
      pedido: ped,
      pedidoId: ped?.id || pedIdRaw,
      criadoPor,
      lote_codigo: m.lotes?.lote_codigo || '—',
    });
  };

  const handleVerPedido = async () => {
    if (!movDetail?.pedidoId) return;
    const isUuid = movDetail.pedidoId.length > 20 && movDetail.pedidoId.includes('-');
    let query = supabase.from('pedidos').select('*, contatos(nome, telefone, cpf, endereco, complemento, bairro, cidade_uf, cep)');
    if (isUuid) query = query.eq('id', movDetail.pedidoId);
    else query = query.eq('order_number', movDetail.pedidoId);
    
    const { data: ped } = await query.maybeSingle();
    setDetailPedido(ped);
    setMovDetail(null);
  };

  const handleSubmit = async () => {
    if (!formUF) { toast.error('Selecione a UF do estoque'); return; }
    const validRows = formRows.filter(r => r.produto_id && r.quantidade >= 1);
    if (validRows.length === 0) { toast.error('Selecione pelo menos um produto'); return; }
    if (submitting) return;

    setSubmitting(true);
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    const { data: sessionData } = await supabase.auth.getSession();
    const accessToken = sessionData?.session?.access_token || SUPABASE_KEY;
    let loteCodigo = '';

    for (const row of validRows) {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/criar_lote_estoque`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${accessToken}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify({
          p_produto_id: row.produto_id,
          p_uf: formUF,
          p_quantidade: row.quantidade,
          p_criado_por: profile?.nome || 'Sistema'
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        toast.error('Erro: ' + errorText);
        setSubmitting(false);
        return;
      }

      const result = await response.json();
      if (result.lote_codigo) loteCodigo = result.lote_codigo;
    }

    toast.success(`Estoque atualizado! Lote: ${loteCodigo}`);
    setLastLoteCodigo(loteCodigo);
    setShowForm(false);
    setFormRows([{ produto_id: '', quantidade: 1 }]);
    setFormUF('');
    setSubmitting(false);
    fetchAll();
  };

  const handleSaveProduct = async () => {
    if (!formNome || !formTag) {
      toast.error('Nome e Tag são obrigatórios');
      return;
    }
    setSubmitting(true);
    
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    try {
      if (editProduct?.id) {
        // Update via RPC
        console.log('Updating product:', editProduct.id);
        const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/update_produto`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`,
            'Prefer': 'return=representation',
          },
          body: JSON.stringify({
            p_id: editProduct.id,
            p_nome_oficial: formNome,
            p_tag: formTag,
            p_cor_card: formCorCard,
            p_cor_texto: formCorTexto,
            p_limite_estoque: formLimite || 0,
            p_grupo_id: formGrupo || null,
            p_box_size: formBoxSize || null,
            p_box_qty_max: formBoxQtyMax || 10,
            p_peso: formPeso || 300,
            p_preco: formPreco === '' ? null : Number(formPreco),
          }),
        });
        console.log('Update response:', response.status, response.statusText);
        if (!response.ok) {
          const errText = await response.text();
          console.error('Update error:', errText);
          throw new Error(errText);
        }
        toast.success('Produto atualizado!');
      } else {
        // Create via RPC
        console.log('Creating product:', formNome, formTag);
        const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/create_produto`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`,
            'Prefer': 'return=representation',
          },
          body: JSON.stringify({
            p_nome_oficial: formNome,
            p_tag: formTag,
            p_cor_card: formCorCard,
            p_cor_texto: formCorTexto,
            p_limite_estoque: formLimite || 0,
            p_grupo_id: formGrupo || null,
            p_box_size: formBoxSize || null,
            p_box_qty_max: formBoxQtyMax || 10,
            p_peso: formPeso || 300,
            p_preco: formPreco === '' ? null : Number(formPreco),
          }),
        });
        console.log('Create response:', response.status, response.statusText);
        if (!response.ok) {
          const errText = await response.text();
          console.error('Create error:', errText);
          throw new Error(errText);
        }
        toast.success('Produto criado!');
      }
      
      setShowAddProduct(false);
      setEditProduct(null);
      resetForm();
      fetchAll();
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || 'Erro desconhecido'));
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteProduct = async () => {
    if (!deleteProduct) return;
    setSubmitting(true);
    
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/delete_produto`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify({ p_id: deleteProduct.id }),
      });
      if (!response.ok) throw new Error(await response.text());
      toast.success('Produto excluído!');
      setDeleteProduct(null);
      fetchAll();
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || 'Erro desconhecido'));
    } finally {
      setSubmitting(false);
    }
  };

  const handleCreateGroup = async () => {
    if (!formGroupNome.trim()) {
      toast.error('Nome do grupo é obrigatório');
      return;
    }
    setSubmittingGroup(true);
    
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/create_produto_grupo`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify({ p_nome: formGroupNome.trim(), p_cor: formGroupCor }),
      });
      if (!response.ok) throw new Error(await response.text());
      toast.success('Grupo criado!');
      setFormGroupNome('');
      setFormGroupCor('#ffffff');
      setShowCreateGroup(false);
      fetchAll();
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || 'Erro desconhecido'));
    } finally {
      setSubmittingGroup(false);
    }
  };

  const handleUpdateGroup = async () => {
    if (!editGroup || !formGroupNome.trim()) {
      toast.error('Nome do grupo é obrigatório');
      return;
    }
    setSubmittingGroup(true);
    
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/update_produto_grupo`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify({ p_id: editGroup.id, p_nome: formGroupNome.trim(), p_cor: formGroupCor }),
      });
      if (!response.ok) throw new Error(await response.text());
      toast.success('Grupo atualizado!');
      setEditGroup(null);
      setFormGroupNome('');
      setFormGroupCor('#ffffff');
      fetchAll();
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || 'Erro desconhecido'));
    } finally {
      setSubmittingGroup(false);
    }
  };

  const handleDeleteGroup = async () => {
    if (!deleteGroup) return;
    setSubmittingGroup(true);
    
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/delete_produto_grupo`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify({ p_id: deleteGroup.id }),
      });
      if (!response.ok) throw new Error(await response.text());
      toast.success('Grupo excluído!');
      setDeleteGroup(null);
      if (selectedGroupId === deleteGroup.id) setSelectedGroupId(null);
      fetchAll();
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || 'Erro desconhecido'));
    } finally {
      setSubmittingGroup(false);
    }
  };

  const openEditGroup = (g: any) => {
    setEditGroup(g);
    setFormGroupNome(g.nome);
    setFormGroupCor(g.cor_grupo || '#ffffff');
    setShowCreateGroup(true);
  };

  const resetForm = () => {
    setFormNome('');
    setFormTag('');
    setFormCorCard('#ffffff');
    setFormCorTexto('#000000');
    setFormLimite(0);
    setFormGrupo('');
    setFormBoxSize('');
    setFormPreco('');
  };

  const openEditProduct = (p: any) => {
    setEditProduct(p);
    setFormNome(p.nome_oficial || '');
    setFormTag(p.tag || '');
    setFormCorCard(p.cor_card || '#ffffff');
    setFormCorTexto(p.cor_texto || '#000000');
    setFormLimite(p.limite_estoque || 0);
    setFormGrupo(p.grupo_id || '');
    setFormBoxSize(p.box_size || '');
    setFormBoxQtyMax(p.box_qty_max || 10);
    setFormPeso(p.peso || 300);
    setFormPreco(p.preco != null ? String(p.preco) : '');
    setShowAddProduct(true);
  };

  const toggleProductStatus = async (p: any) => {
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/update_produto_status`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify({ p_id: p.id, p_ativo: !p.ativo }),
      });
      if (!response.ok) throw new Error(await response.text());
      toast.success(p.ativo ? 'Produto inativado!' : 'Produto ativado!');
      fetchAll();
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || 'Erro desconhecido'));
    }
  };

  const loadMoreMovimentacoes = async (direction: 'prev' | 'next') => {
    const newPage = direction === 'next' ? pageMovimentacoes + 1 : pageMovimentacoes - 1;
    if (newPage < 0 || newPage >= totalPagesMovimentacoes) return;
    
    setLoading(true);
    const offset = newPage * PAGE_SIZE_MOVIMENTACOES;
    const dataLimiteMov = getDataLimiteMov();
    let query = supabase
      .from('estoque_movimentacoes')
      .select(`*, produtos(nome_oficial, tag), lotes(lote_codigo), ${MOV_PEDIDO_EMBED}`)
      .gte('data', dataLimiteMov)
      .order('data', { ascending: false })
      .range(offset, offset + PAGE_SIZE_MOVIMENTACOES - 1);
    
    const { data: movs } = await query;
    setMovimentacoes(movs || []);
    setPageMovimentacoes(newPage);
    setLoading(false);
  };

  const handleMovSearch = async () => {
    if (!movSearch.trim()) {
      setPageMovimentacoes(0);
      fetchAll();
      return;
    }
    
    setLoading(true);
    const searchTerm = movSearch.toLowerCase();
    
    const { data: movs } = await supabase
      .from('estoque_movimentacoes')
      .select(`*, produtos(nome_oficial, tag), lotes(lote_codigo), ${MOV_PEDIDO_EMBED}`)
      .gte('data', getDataLimiteMov())
      .order('data', { ascending: false })
      .limit(PAGE_SIZE_MOVIMENTACOES);
    
    const filtered = (movs || []).filter(m => {
      const prodNome = m.produtos?.nome_oficial?.toLowerCase() || '';
      const prodTag = m.produtos?.tag?.toLowerCase() || '';
      const clienteNome = m.pedidos?.contatos?.nome?.toLowerCase() || '';
      return prodNome.includes(searchTerm) || prodTag.includes(searchTerm) || clienteNome.includes(searchTerm);
    });
    
    setMovimentacoes(filtered);
    setTotalMovCount(filtered.length);
    setLoading(false);
    setPageMovimentacoes(0);
  };

  const handleCleanupOldRecords = async () => {
    if (cleaningUp) return;
    setCleaningUp(true);
    
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/limpar_movimentacoes_antigas`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify({ p_dias: '90' }),
      });
      
      if (!response.ok) throw new Error(await response.text());
      
      const result = await response.json();
      toast.success(`${result.registros_apagados} registros antigos removidos!`);
      setConfirmDeleteOld(false);
      fetchAll();
    } catch (err: any) {
      toast.error('Erro ao limpar: ' + (err.message || 'Erro desconhecido'));
    } finally {
      setCleaningUp(false);
    }
  };

  const handleCreateRegion = async () => {
    if (!selectedUfForRegion || !newRegionTag.trim()) {
      toast.error('Selecione uma UF e dê uma tag para a região');
      return;
    }
    setSubmittingUf(true);
    try {
      const { data, error } = await supabase.rpc('criar_regiao_uf' as any, {
        p_uf: selectedUfForRegion,
        p_tag: newRegionTag.trim()
      });

      if (error) throw error;
      
      const result = data as any;
      if (result.error) throw new Error(result.error);

      toast.success(`Região ${result.codigo} criada com sucesso!`);
      setShowAddRegion(false);
      setNewRegionTag('');
      setSelectedUfForRegion('');
      fetchAll();
    } catch (err: any) {
      toast.error('Erro: ' + (err.message || 'Erro desconhecido'));
    } finally {
      setSubmittingUf(false);
    }
  };

  const handleDeleteRegion = async () => {
    if (!deleteRegionTarget) return;
    try {
      const { error } = await supabase.from('uf_regioes' as any).delete().eq('id', deleteRegionTarget.id);
      if (error) throw error;
      toast.success(`Região ${deleteRegionTarget.codigo} removida!`);
      setDeleteRegionTarget(null);
      fetchAll();
    } catch (err: any) {
      toast.error('Erro ao remover região: ' + err.message);
    }
  };

  if (loading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Estoque</h1>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="estoque">📦 Estoque</TabsTrigger>
          <TabsTrigger value="cadastro">📝 Cadastro</TabsTrigger>
        </TabsList>

        <TabsContent value="estoque" className="space-y-6">
            {/* Cards de Grupos */}
            {grupos.length > 0 && (
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <h3 className="font-semibold text-sm">Grupos (clique para filtrar)</h3>
                  {selectedGroupId && (
                    <Button variant="link" size="sm" onClick={() => setSelectedGroupId(null)}>
                      Mostrar todos
                    </Button>
                  )}
                </div>
                <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-2">
                  {grupos
                    .slice(pageGrupos * PAGE_SIZE_GRUPOS, (pageGrupos + 1) * PAGE_SIZE_GRUPOS)
                    .map(g => {
                    const produtosDoGrupo = produtos.filter(p => p.ativo && p.grupo_id === g.id);
                    const estoqueDoGrupo = produtosDoGrupo.reduce((sum, p) => {
                      const uf = lotesByProduct[p.id] || [];
                      return sum + uf.reduce((s, l) => s + l.qty, 0);
                    }, 0);
                    return (
                      <Card 
                        key={g.id} 
                        className={cn(
                          'cursor-pointer transition-all hover:scale-105',
                          selectedGroupId === g.id ? 'ring-2 ring-blue-500 border-blue-500' : 'border-2'
                        )}
                        style={{ backgroundColor: g.cor_grupo || '#f8fafc' }}
                        onClick={() => { setSelectedGroupId(selectedGroupId === g.id ? null : g.id); setPageProdutosEstoque(0); }}
                      >
                        <CardContent className="p-3 text-center">
                          <p className="text-sm font-bold">{g.nome}</p>
                          <p className="text-2xl font-bold text-blue-600">{estoqueDoGrupo}</p>
                          <p className="text-xs text-muted-foreground">{produtosDoGrupo.length} produtos</p>
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
                {grupos.length > PAGE_SIZE_GRUPOS && (
                  <div className="flex justify-center items-center gap-2 mt-2">
                    <Button variant="outline" size="sm" disabled={pageGrupos === 0} onClick={() => setPageGrupos(p => p - 1)}>
                      <ChevronLeft className="w-4 h-4" />
                    </Button>
                    <span className="text-sm">{pageGrupos + 1} / {Math.ceil(grupos.length / PAGE_SIZE_GRUPOS)}</span>
                    <Button variant="outline" size="sm" disabled={(pageGrupos + 1) * PAGE_SIZE_GRUPOS >= grupos.length} onClick={() => setPageGrupos(p => p + 1)}>
                      <ChevronRight className="w-4 h-4" />
                    </Button>
                  </div>
                )}
              </div>
            )}

            {/* Cards de Produtos */}
            {selectedGroupId && (
              <p className="text-sm text-muted-foreground">
                Filtrando: {grupos.find(g => g.id === selectedGroupId)?.nome}
              </p>
            )}
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
            {(() => {
              const produtosExibir = selectedGroupId 
                ? produtos.filter(p => p.ativo && p.grupo_id === selectedGroupId)
                : produtos.filter(p => p.ativo && !p.grupo_id);
              const paginated = produtosExibir.slice(pageProdutosEstoque * PAGE_SIZE_PRODUTOS_ESTOQUE, (pageProdutosEstoque + 1) * PAGE_SIZE_PRODUTOS_ESTOQUE);
              return paginated.map(p => {
                const ufBreakdown = (lotesByProduct[p.id] || []).filter(l => l.qty !== 0);
                const totalEstoque = ufBreakdown.reduce((sum, l) => sum + l.qty, 0);
                return (
                <Card key={p.id} className={cn('border-2', totalEstoque < 0 ? 'border-red-500 animate-pulse-border' : totalEstoque < 5 && 'animate-pulse-border')} style={{ backgroundColor: p.cor_card || '#ffffff', color: p.cor_texto || '#000000' }}>
                  <CardContent className="p-4 text-center">
                    <p className="text-sm font-bold">{getProductDisplayName(p)}</p>
                    <p className="text-3xl font-bold mt-1">{totalEstoque}</p>
                    {ufBreakdown.length > 0 && (
                      <p className="text-xs mt-1 opacity-80">
                        {ufBreakdown.map(l => `${l.uf}: ${l.qty}`).join(' | ')}
                      </p>
                    )}
                  </CardContent>
                </Card>
                );
              });
            })()}
          </div>
          {(() => {
            const produtosExibir = selectedGroupId 
              ? produtos.filter(p => p.ativo && p.grupo_id === selectedGroupId)
              : produtos.filter(p => p.ativo && !p.grupo_id);
            return produtosExibir.length > PAGE_SIZE_PRODUTOS_ESTOQUE && (
              <div className="flex justify-center items-center gap-2 mt-2">
                <Button variant="outline" size="sm" disabled={pageProdutosEstoque === 0} onClick={() => setPageProdutosEstoque(p => p - 1)}>
                  <ChevronLeft className="w-4 h-4" />
                </Button>
                <span className="text-sm">{pageProdutosEstoque + 1} / {Math.ceil(produtosExibir.length / PAGE_SIZE_PRODUTOS_ESTOQUE)}</span>
                <Button variant="outline" size="sm" disabled={(pageProdutosEstoque + 1) * PAGE_SIZE_PRODUTOS_ESTOQUE >= produtosExibir.length} onClick={() => setPageProdutosEstoque(p => p + 1)}>
                  <ChevronRight className="w-4 h-4" />
                </Button>
              </div>
            );
          })()}

            <p className="text-sm font-medium text-muted-foreground">Total de produtos: {produtos.filter(p => p.ativo).reduce((sum, p) => {
              const ufBreakdown = lotesByProduct[p.id] || [];
              return sum + ufBreakdown.reduce((s, l) => s + l.qty, 0);
            }, 0)}</p>

            {repStock.length > 0 && (
              <div className="space-y-3">
                <h2 className="font-bold text-lg flex items-center gap-2">
                  <User className="w-4 h-4" />
                  Estoque Atribuído a Representantes
                </h2>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead><tr className="border-b font-bold"><th className="text-left py-2">Representante</th><th className="text-left py-2">Produto</th><th className="text-right py-2">Qtd</th><th className="text-left py-2">UF</th></tr></thead>
                    <tbody>
                      {repStock.map((rs, i) => (
                        <tr key={i} className="border-b border-border/50">
                          <td className="py-2 font-medium">{rs.rep_nome}</td>
                          <td className="py-2">{rs.produto_nome}</td>
                          <td className="py-2 text-right font-bold">{rs.quantidade}</td>
                          <td className="py-2">{rs.uf}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            <Button onClick={() => setShowForm(true)} className="fixed bottom-6 right-6 rounded-full h-14 w-14 shadow-lg bg-sf-green hover:bg-sf-green/90 text-primary-foreground z-50" size="icon">
              <Plus className="w-6 h-6" />
            </Button>

            <h2 className="font-bold text-lg">Movimentações</h2>
            <div className="flex items-center gap-2 mb-3">
              <Input
                placeholder="Buscar por produto ou cliente..."
                value={movSearch}
                onChange={e => setMovSearch(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleMovSearch()}
                className="max-w-xs"
              />
              <Button variant="outline" size="sm" onClick={handleMovSearch}>
                🔍
              </Button>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead><tr className="border-b font-bold"><th className="text-left py-2">Data</th><th className="text-left py-2">Produto</th><th className="text-right py-2">Qnt.</th><th className="text-left py-2">Tipo</th><th className="text-left py-2">UF estoque</th><th className="text-left py-2">UF cliente</th></tr></thead>
                <tbody>
                  {movimentacoes.map(m => (
                    <tr key={m.id} className="border-b border-border/50 cursor-pointer hover:bg-muted/50" onClick={() => handleMovClick(m)}>
                      <td className="py-2">{formatDateShort((m as any).data || m.created_at)}</td>
                      <td className="py-2">{getProductDisplayName(m.produtos)}</td>
                      <td className="py-2 text-right">{m.quantidade}</td>
                      <td className="py-2">
                        <Badge variant={m.tipo === 'entrada' ? 'default' : 'destructive'} className={m.tipo === 'entrada' ? 'bg-green-600 text-white' : ''}>
                          {m.tipo === 'entrada' ? 'Entrada' : 'Saída'}
                        </Badge>
                      </td>
                      <td className="py-2">{m.uf_origem || m.posse || '—'}</td>
                      <td className="py-2">{ufClienteFromMov(m)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {/* Paginação Movimentações */}
            {totalPagesMovimentacoes > 1 && (
              <div className="flex justify-center items-center gap-2 mt-3">
                <Button 
                  variant="outline" 
                  size="sm" 
                  disabled={pageMovimentacoes === 0} 
                  onClick={() => loadMoreMovimentacoes('prev')}
                >
                  <ChevronLeft className="w-4 h-4" />
                </Button>
                <span className="text-sm text-muted-foreground">
                  {pageMovimentacoes + 1} / {totalPagesMovimentacoes}
                </span>
                <Button 
                  variant="outline" 
                  size="sm" 
                  disabled={pageMovimentacoes + 1 >= totalPagesMovimentacoes} 
                  onClick={() => loadMoreMovimentacoes('next')}
                >
                  <ChevronRight className="w-4 h-4" />
                </Button>
              </div>
            )}
            {/* Aviso visual: lista mostra só últimos 180 dias (cards/saldo não são afetados) */}
            <div className="flex justify-center mt-4 pb-4">
              <p className="text-xs text-muted-foreground italic">
                Exibindo movimentações dos últimos {DIAS_OCULTACAO_MOV} dias — saldos e cards mostram o total real.
              </p>
            </div>
          </TabsContent>

        {/* ==================== CADASTRO TAB ==================== */}
        <TabsContent value="cadastro" className="space-y-4">
          <div className="flex justify-between items-center">
            <p className="text-sm text-muted-foreground">
              {selectedGroupInCadastro 
                ? `Produtos do grupo: ${selectedGroupInCadastro.nome}` 
                : `${produtos.length} produtos cadastrados`}
            </p>
            <div className="flex gap-2">
              {selectedGroupInCadastro && (
                <Button variant="outline" onClick={() => { setSelectedGroupInCadastro(null); setPageProdutosCadastro(0); }}>
                  Voltar
                </Button>
              )}
              <Button onClick={() => { resetForm(); setEditProduct(null); setShowAddProduct(true); }} className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground">
                <Plus className="w-4 h-4 mr-2" /> Novo Produto
              </Button>
            </div>
          </div>

          {/* Seção de UFs cadastradas */}
          {!selectedGroupInCadastro && (
            <div className="space-y-2">
              <div className="flex justify-between items-center">
                <h3 className="font-semibold text-sm flex items-center gap-1"><MapPin className="w-4 h-4" /> UFs de Estoque</h3>
                <div className="flex gap-2">
                  <Button variant="link" size="sm" onClick={() => setShowAddUf(true)}>
                    <Plus className="w-3 h-3 mr-1" /> Nova UF
                  </Button>
                  <Button variant="link" size="sm" onClick={() => setShowAddRegion(true)} disabled={estoqueUfs.length === 0}>
                    <Plus className="w-3 h-3 mr-1" /> Nova Região UF
                  </Button>
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                {estoqueUfs.map(uf => {
                  const regionsOfUf = ufRegioes.filter(r => r.uf === uf);
                  
                  if (regionsOfUf.length > 0) {
                    return regionsOfUf.map(r => (
                      <Badge key={r.codigo} variant="secondary" className="text-sm px-3 py-1 flex items-center gap-1 bg-blue-50/50">
                        {r.codigo} ({r.tag})
                        <button
                          className="ml-1 text-destructive hover:text-destructive/80 text-xs font-bold"
                          onClick={() => setDeleteRegionTarget({ id: r.id, codigo: r.codigo })}
                          title={`Remover região ${r.codigo}`}
                        >
                          ×
                        </button>
                      </Badge>
                    ));
                  }

                  return (
                    <Badge key={uf} variant="secondary" className="text-sm px-3 py-1 flex items-center gap-1">
                      {uf}
                      <button
                        className="ml-1 text-destructive hover:text-destructive/80 text-xs font-bold"
                        onClick={() => setDeleteUfTarget(uf)}
                        title={`Remover ${uf}`}
                      >
                        ×
                      </button>
                    </Badge>
                  );
                })}
                {estoqueUfs.length === 0 && <p className="text-xs text-muted-foreground">Nenhuma UF cadastrada</p>}
              </div>
            </div>
          )}

          {/* Lista de grupos como lista clicável */}
          {!selectedGroupInCadastro && (
            <div className="space-y-2">
              <div className="flex justify-between items-center">
                <h3 className="font-semibold text-sm">Grupos (clique para ver produtos)</h3>
                <Button variant="link" size="sm" onClick={() => setShowCreateGroup(true)}>
                  <Plus className="w-3 h-3 mr-1" /> Novo Grupo
                </Button>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b font-bold">
                      <th className="text-left py-2">Grupo</th>
                      <th className="text-left py-2">Produtos</th>
                      <th className="text-left py-2">Ações</th>
                    </tr>
                  </thead>
                  <tbody>
                    {grupos
                      .slice(pageGrupos * PAGE_SIZE_GRUPOS, (pageGrupos + 1) * PAGE_SIZE_GRUPOS)
                      .map(g => (
                      <tr key={g.id} className="border-b border-border/50 cursor-pointer hover:bg-muted/50" onClick={() => { setSelectedGroupInCadastro(g); setPageProdutosCadastro(0); }}>
                        <td className="py-2 flex items-center gap-2">
                          <div className="w-4 h-4 rounded" style={{ backgroundColor: g.cor_grupo || '#f8fafc' }} />
                          <span className="font-medium">{g.nome}</span>
                        </td>
                        <td className="py-2">{produtos.filter(p => p.grupo_id === g.id).length}</td>
                        <td className="py-2">
                          <div className="flex gap-1">
                            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={(e) => { e.stopPropagation(); openEditGroup(g); }}>
                              <Edit2 className="w-4 h-4" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-8 w-8 text-red-500" onClick={(e) => { e.stopPropagation(); setDeleteGroup(g); }}>
                              <Trash2 className="w-4 h-4" />
                            </Button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {grupos.length > PAGE_SIZE_GRUPOS && (
                <div className="flex justify-center items-center gap-2 mt-2">
                  <Button variant="outline" size="sm" disabled={pageGrupos === 0} onClick={() => setPageGrupos(p => p - 1)}>
                    <ChevronLeft className="w-4 h-4" />
                  </Button>
                  <span className="text-sm">{pageGrupos + 1} / {Math.ceil(grupos.length / PAGE_SIZE_GRUPOS)}</span>
                  <Button variant="outline" size="sm" disabled={(pageGrupos + 1) * PAGE_SIZE_GRUPOS >= grupos.length} onClick={() => setPageGrupos(p => p + 1)}>
                    <ChevronRight className="w-4 h-4" />
                  </Button>
                </div>
              )}
            </div>
          )}

          {/* Lista de produtos em tabela */}
          <h3 className="font-semibold text-sm mb-4 mt-8">Produtos</h3>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b font-bold">
                  <th className="text-left py-2">Nome Oficial</th>
                  <th className="text-left py-2">Tag</th>
                  <th className="text-left py-2">Grupo</th>
                  <th className="text-right py-2">Preço</th>
                  <th className="text-left py-2">Status</th>
                  <th className="text-left py-2">Ações</th>
                </tr>
              </thead>
              <tbody>
                {(selectedGroupInCadastro 
                  ? produtos.filter(p => p.grupo_id === selectedGroupInCadastro.id)
                  : produtos
                ).slice(pageProdutosCadastro * PAGE_SIZE_PRODUTOS_CADASTRO, (pageProdutosCadastro + 1) * PAGE_SIZE_PRODUTOS_CADASTRO).map(p => (
                  <tr key={p.id} className="border-b border-border/50">
                    <td className="py-2 font-medium">{p.nome_oficial}</td>
                    <td className="py-2">{p.tag}</td>
                    <td className="py-2">
                      {p.produtos_grupos?.nome || (
                        <Badge variant="outline" className="text-xs">Sem grupo</Badge>
                      )}
                    </td>
                    <td className="py-2 text-right tabular-nums">
                      {p.preco != null ? `R$ ${Number(p.preco).toFixed(2).replace('.', ',')}` : <span className="text-muted-foreground text-xs">—</span>}
                    </td>
                    <td className="py-2">
                      <Badge
                        variant={p.ativo ? 'default' : 'secondary'}
                        className={cn('cursor-pointer', !p.ativo && 'bg-red-100 text-red-700')}
                        onClick={() => toggleProductStatus(p)}
                      >
                        {p.ativo ? 'Ativo' : 'Inativo'}
                      </Badge>
                    </td>
                    <td className="py-2">
                      <div className="flex gap-1">
                        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openEditProduct(p)}>
                          <Edit2 className="w-4 h-4" />
                        </Button>
                        <Button variant="ghost" size="icon" className="h-8 w-8 text-red-500" onClick={() => setDeleteProduct(p)}>
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {(selectedGroupInCadastro 
            ? produtos.filter(p => p.grupo_id === selectedGroupInCadastro.id)
            : produtos
          ).length > PAGE_SIZE_PRODUTOS_CADASTRO && (
            <div className="flex justify-center items-center gap-2 mt-2">
              <Button variant="outline" size="sm" disabled={pageProdutosCadastro === 0} onClick={() => setPageProdutosCadastro(p => p - 1)}>
                <ChevronLeft className="w-4 h-4" />
              </Button>
              <span className="text-sm">
                {pageProdutosCadastro + 1} / {Math.ceil((selectedGroupInCadastro 
                  ? produtos.filter(p => p.grupo_id === selectedGroupInCadastro.id).length
                  : produtos.length) / PAGE_SIZE_PRODUTOS_CADASTRO)}
              </span>
              <Button variant="outline" size="sm" disabled={(pageProdutosCadastro + 1) * PAGE_SIZE_PRODUTOS_CADASTRO >= (selectedGroupInCadastro 
                ? produtos.filter(p => p.grupo_id === selectedGroupInCadastro.id).length
                : produtos.length)} onClick={() => setPageProdutosCadastro(p => p + 1)}>
                <ChevronRight className="w-4 h-4" />
              </Button>
            </div>
          )}
        </TabsContent>
      </Tabs>

      {/* Dialog entrada de estoque */}
      <Dialog open={showForm} onOpenChange={setShowForm}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Entrada de Estoque</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">Data: {formatDateShort(new Date())}</p>
            {formRows.map((row, idx) => (
              <div key={idx} className="flex gap-2">
                <Select value={row.produto_id} onValueChange={v => { const n = [...formRows]; n[idx].produto_id = v; setFormRows(n); }}>
                  <SelectTrigger className="flex-1"><SelectValue placeholder="Produto" /></SelectTrigger>
                  <SelectContent>{produtos.filter(p => p.ativo).map(p => <SelectItem key={p.id} value={p.id}>{getProductDisplayName(p)}</SelectItem>)}</SelectContent>
                </Select>
                <Input type="number" min={1} value={row.quantidade} onChange={e => { const n = [...formRows]; n[idx].quantidade = Number(e.target.value); setFormRows(n); }} className="w-20" />
              </div>
            ))}
            <Button variant="link" size="sm" onClick={() => setFormRows([...formRows, { produto_id: '', quantidade: 1 }])}>➕ Adicionar linha</Button>
            <div>
              <Label>UF do estoque</Label>
              <Select value={formUF} onValueChange={setFormUF}>
                <SelectTrigger><SelectValue placeholder="Selecione o estado" /></SelectTrigger>
                <SelectContent>{estoqueUfs.map(uf => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <Button onClick={handleSubmit} disabled={submitting} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground">
              {submitting ? 'Salvando...' : 'Adicionar'}
            </Button>
            {lastLoteCodigo && <p className="text-sm text-center text-muted-foreground">Último lote: <strong>{lastLoteCodigo}</strong></p>}
          </div>
        </DialogContent>
      </Dialog>

      {/* Movimentacao detail - Saída */}
      <Dialog open={!!movDetail && movDetail?.tipo === 'saida'} onOpenChange={() => setMovDetail(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Detalhes da Saída</DialogTitle></DialogHeader>
          {movDetail && (
            <div className="space-y-3 text-sm mt-2">
              {movDetail.pedido ? (
                <>
                  <p><strong>Pedido #{movDetail.pedido.order_number}</strong></p>
                  <p><strong>Cliente:</strong> {movDetail.pedido.contatos?.nome || '—'}</p>
                  <p><strong>UF postagem:</strong> {movDetail.pedido.uf_postagem?.trim() || '—'}</p>
                  <p><strong>UF cliente:</strong> {ufClienteFromMov({ pedidos: { contatos: movDetail.pedido.contatos } })}</p>
                  <Button onClick={handleVerPedido} className="w-full mt-2">
                    <ExternalLink className="w-4 h-4 mr-1" /> Ver Pedido
                  </Button>
                </>
              ) : movDetail.observacao?.includes('Saída automática') ? (
                <>
                  <p><strong>Pedido #{movDetail.observacao?.match(/Pedido (.*?)\)/)?.[1] || '—'}</strong></p>
                  <p><strong>Cliente:</strong> <em>Vínculo antigo (não disponível)</em></p>
                </>
              ) : (
                <>
                  <p><strong>Criado por:</strong> {movDetail.criadoPor || '—'}</p>
                  <p><strong>Observação:</strong> {movDetail.observacao || '—'}</p>
                </>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Movimentacao detail - Entrada */}
      <Dialog open={!!movDetail && movDetail?.tipo === 'entrada'} onOpenChange={() => setMovDetail(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Detalhes da Entrada</DialogTitle></DialogHeader>
          {movDetail && (
            <div className="space-y-3 text-sm mt-2">
              {movDetail.observacao?.includes('Devolução automática') ? (
                <>
                  <p className="text-lg font-semibold text-sf-green">Pedido Devolvido</p>
                  <p><strong>Pedido #{movDetail.pedido?.order_number || movDetail.observacao?.match(/Pedido (.*?)\)/)?.[1] || '—'}</strong> devolvido a UF: <strong>{movDetail.uf_origem || '—'}</strong></p>
                  {movDetail.pedido && (
                    <Button onClick={handleVerPedido} className="w-full mt-2">
                      <ExternalLink className="w-4 h-4 mr-1" /> Ver Pedido
                    </Button>
                  )}
                </>
              ) : (
                <>
                  <p><strong>Criado por:</strong> {movDetail.criadoPor || '—'}</p>
                  <p><strong>Lote:</strong> {movDetail.lote_codigo || '—'}</p>
                </>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Pedido detail dialog */}
      <Dialog open={!!detailPedido} onOpenChange={() => setDetailPedido(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Detalhes do Pedido #{detailPedido?.order_number}</DialogTitle></DialogHeader>
          {detailPedido && (
            <div className="space-y-2 text-sm">
              <div>
                <strong>Produtos:</strong>
                {(() => {
                  try {
                    const prods = JSON.parse(detailPedido.produto);
                    if (Array.isArray(prods)) {
                      return prods.map((p: any, i: number) => (
                        <p key={i} className="ml-2">• {getTagDisplayName(p.produto)} × {p.quantidade}</p>
                      ));
                    }
                  } catch {}
                  return <p className="ml-2">{getTagDisplayName(detailPedido.produto)} × {detailPedido.quantidade}</p>;
                })()}
              </div>
              <p><strong>Valor Total:</strong> R$ {Number(detailPedido.valor || 0).toFixed(2).replace('.', ',')}</p>
              <p><strong>CPF:</strong> {(detailPedido.contatos as any)?.cpf || '—'}</p>
              <p><strong>Endereço:</strong> {(detailPedido.contatos as any)?.endereco || '—'}</p>
              <p><strong>Complemento:</strong> {(detailPedido.contatos as any)?.complemento || '—'}</p>
              <p><strong>Bairro:</strong> {(detailPedido.contatos as any)?.bairro || '—'}</p>
              <p><strong>Cidade/UF:</strong> {(detailPedido.contatos as any)?.cidade_uf || '—'}</p>
              <p><strong>CEP:</strong> {(detailPedido.contatos as any)?.cep || '—'}</p>
              <p><strong>Canal:</strong> {detailPedido.canal}</p>
              <p><strong>UF Origem:</strong> {detailPedido.uf_postagem || '⚠️ Não definida'}</p>
              <p><strong>Status:</strong> {detailPedido.status_pedido === 'entregue' ? 'Entregue' : detailPedido.status_pedido === 'postado' ? 'Postado' : 'Aguardando Postagem'}</p>
              <p><strong>Rastreio:</strong> {detailPedido.codigo_rastreio || 'Aguardando rastreio'}</p>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Dialog adicionar/editar produto */}
      <Dialog open={showAddProduct} onOpenChange={setShowAddProduct}>
        <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editProduct ? 'Editar Produto' : 'Novo Produto'}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Nome Oficial</Label>
              <Input value={formNome} onChange={e => setFormNome(e.target.value)} placeholder="Ex: Produto Alpha" />
            </div>
            <div>
              <Label>Tag (nome curto)</Label>
              <Input value={formTag} onChange={e => setFormTag(e.target.value)} placeholder="Ex: Alpha" />
            </div>
            <div>
              <Label>Cor do Card</Label>
              <div className="flex items-center gap-2 mb-2">
                <input
                  type="color"
                  value={formCorCard}
                  onChange={e => setFormCorCard(e.target.value)}
                  className="w-10 h-10 rounded border cursor-pointer"
                />
                <Input
                  value={formCorCard}
                  onChange={e => setFormCorCard(e.target.value)}
                  className="flex-1"
                  placeholder="#ffffff"
                />
              </div>
              <p className="text-xs text-muted-foreground mb-2">Paleta de cores:</p>
              <div className="grid grid-cols-8 gap-1 max-h-32 overflow-y-auto">
                {CORES_CARDS.map(c => (
                  <button
                    key={c}
                    type="button"
                    className={cn('w-7 h-7 rounded border-2 transition-transform hover:scale-110', formCorCard === c ? 'border-blue-500 ring-2 ring-blue-300' : 'border-transparent')}
                    style={{ backgroundColor: c }}
                    onClick={() => setFormCorCard(c)}
                  />
                ))}
              </div>
            </div>
            <div>
              <Label>Cor do Texto</Label>
              <div className="flex gap-2">
                <button
                  type="button"
                  className={cn('w-8 h-8 rounded border-2', formCorTexto === '#000000' ? 'border-blue-500' : 'border-transparent')}
                  style={{ backgroundColor: '#000000' }}
                  onClick={() => setFormCorTexto('#000000')}
                />
                <button
                  type="button"
                  className={cn('w-8 h-8 rounded border-2', formCorTexto === '#ffffff' ? 'border-blue-500' : 'border-transparent')}
                  style={{ backgroundColor: '#ffffff', border: '1px solid #ccc' }}
                  onClick={() => setFormCorTexto('#ffffff')}
                />
              </div>
            </div>
            <div>
              <Label>Grupo (opcional)</Label>
              <Select value={formGrupo} onValueChange={setFormGrupo}>
                <SelectTrigger><SelectValue placeholder="Selecione um grupo" /></SelectTrigger>
                <SelectContent>
                  {grupos.map(g => <SelectItem key={g.id} value={g.id}>{g.nome}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Tamanho da Caixa</Label>
              <Select value={formBoxSize} onValueChange={setFormBoxSize}>
                <SelectTrigger><SelectValue placeholder="Selecione o tamanho" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="MINI">MINI - Caixa pequena</SelectItem>
                  <SelectItem value="P">P - Caixa pequena</SelectItem>
                  <SelectItem value="M">M - Caixa média</SelectItem>
                  <SelectItem value="G">G - Caixa grande</SelectItem>
                  <SelectItem value="GG">GG - Caixa extra grande</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Qtd Máx na Caixa</Label>
              <Input 
                type="number" 
                min={1} 
                value={formBoxQtyMax} 
                onChange={e => setFormBoxQtyMax(Number(e.target.value))} 
                placeholder="10" 
              />
              <p className="text-xs text-muted-foreground mt-1">Se a quantidade exceder, muda para caixa maior</p>
            </div>
            <div>
              <Label>Peso (g por unidade)</Label>
              <Input
                type="number"
                min={1}
                value={formPeso}
                onChange={e => setFormPeso(Number(e.target.value))}
                placeholder="300"
              />
              <p className="text-xs text-muted-foreground mt-1">Peso em gramas. Usado para cálculo de frete.</p>
            </div>
            <div>
              <Label>Preço (R$)</Label>
              <Input
                type="number"
                step="0.01"
                min={0}
                value={formPreco}
                onChange={e => setFormPreco(e.target.value)}
                placeholder="180.00"
              />
              <p className="text-xs text-muted-foreground mt-1">
                Usado pelo bot de fechamento (Pix, total, resumo do pedido). Não é usado em lançamentos financeiros — lá o valor é manual.
              </p>
            </div>
            <Button onClick={handleSaveProduct} disabled={submitting} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground">
              {submitting ? 'Salvando...' : 'Salvar'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Dialog confirmar delete */}
      <AlertDialog open={!!deleteProduct} onOpenChange={() => setDeleteProduct(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir Produto?</AlertDialogTitle>
            <AlertDialogDescription>
              Isso vai excluir "{deleteProduct?.nome_oficial}". Esta ação não pode ser desfeita.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteProduct} className="bg-red-500 hover:bg-red-600 text-white">Excluir</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Dialog criar/editar grupo */}
      <Dialog open={showCreateGroup} onOpenChange={(open) => { if (!open) { setEditGroup(null); setFormGroupNome(''); setFormGroupCor('#ffffff'); } setShowCreateGroup(open); }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>{editGroup ? 'Editar Grupo' : 'Novo Grupo'}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Nome do Grupo</Label>
              <Input value={formGroupNome} onChange={e => setFormGroupNome(e.target.value)} placeholder="Ex: Pack's" />
            </div>
            <div>
              <Label>Cor do Grupo</Label>
              <div className="flex items-center gap-2">
                <input
                  type="color"
                  value={formGroupCor}
                  onChange={e => setFormGroupCor(e.target.value)}
                  className="w-10 h-10 rounded border cursor-pointer"
                />
                <Input
                  value={formGroupCor}
                  onChange={e => setFormGroupCor(e.target.value)}
                  className="flex-1"
                  placeholder="#ffffff"
                />
              </div>
            </div>
            {editGroup ? (
              <Button onClick={handleUpdateGroup} disabled={submittingGroup} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground">
                {submittingGroup ? 'Atualizando...' : 'Atualizar'}
              </Button>
            ) : (
              <Button onClick={handleCreateGroup} disabled={submittingGroup} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground">
                {submittingGroup ? 'Criando...' : 'Criar Grupo'}
              </Button>
            )}
          </div>
        </DialogContent>
      </Dialog>

      {/* Dialog confirmar delete grupo */}
      <AlertDialog open={!!deleteGroup} onOpenChange={() => setDeleteGroup(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir Grupo?</AlertDialogTitle>
            <AlertDialogDescription>
              Isso vai excluir "{deleteGroup?.nome}" e desvincular {produtos.filter(p => p.grupo_id === deleteGroup?.id).length} produtos deste grupo.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteGroup} className="bg-red-500 hover:bg-red-600 text-white">Excluir</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Dialog adicionar UF */}
      <Dialog open={showAddUf} onOpenChange={setShowAddUf}>
        <DialogContent className="max-w-xs">
          <DialogHeader><DialogTitle>Nova UF de Estoque</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>UF (sigla)</Label>
              <Select value={newUf} onValueChange={setNewUf}>
                <SelectTrigger><SelectValue placeholder="Selecione a UF" /></SelectTrigger>
                <SelectContent>
                  {UF_LIST_FALLBACK.filter(uf => !estoqueUfs.includes(uf)).map(uf => (
                    <SelectItem key={uf} value={uf}>{uf}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button
              disabled={!newUf || submittingUf}
              className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground"
              onClick={async () => {
                if (!newUf) return;
                setSubmittingUf(true);
                const { error } = await supabase.from('estoque_ufs' as any).insert({ uf: newUf });
                setSubmittingUf(false);
                if (error) { toast.error('Erro ao adicionar UF: ' + error.message); return; }
                toast.success(`UF ${newUf} adicionada!`);
                setNewUf('');
                setShowAddUf(false);
                fetchAll();
              }}
            >
              {submittingUf ? 'Adicionando...' : 'Adicionar UF'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Dialog confirmar delete UF */}
      <AlertDialog open={!!deleteUfTarget} onOpenChange={() => setDeleteUfTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remover UF "{deleteUfTarget}"?</AlertDialogTitle>
            <AlertDialogDescription>
              Isso vai remover a UF "{deleteUfTarget}" dos filtros e dropdowns. 
              <strong> Atenção:</strong> Se esta UF possuir regiões, elas também serão excluídas permanentemente. 
              Os dados históricos de estoque não serão afetados.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              className="bg-red-500 hover:bg-red-600 text-white"
              onClick={async () => {
                if (!deleteUfTarget) return;
                const { error } = await supabase.from('estoque_ufs' as any).delete().eq('uf', deleteUfTarget);
                if (error) { toast.error('Erro: ' + error.message); return; }
                toast.success(`UF ${deleteUfTarget} removida!`);
                setDeleteUfTarget(null);
                fetchAll();
              }}
            >
              Remover
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Dialog confirmar limpeza de movimentações antigas */}
      <AlertDialog open={confirmDeleteOld} onOpenChange={setConfirmDeleteOld}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Tem certeza?</AlertDialogTitle>
            <AlertDialogDescription>
              Esta opção apagará os registros de movimentação com mais de 90 dias. 
              O snapshot do estoque será criado antes da exclusão para garantir que os números dos cards não sejam alterados.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleCleanupOldRecords}
              disabled={cleaningUp}
              className="bg-red-500 hover:bg-red-600 text-white"
            >
              {cleaningUp ? 'Apagando...' : 'Confirmar'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      {/* Modal Add Region */}
      <Dialog open={showAddRegion} onOpenChange={setShowAddRegion}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Cadastrar Nova Região</DialogTitle></DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Selecione a UF Base</Label>
              <Select value={selectedUfForRegion} onValueChange={setSelectedUfForRegion}>
                <SelectTrigger><SelectValue placeholder="Escolha a UF..." /></SelectTrigger>
                <SelectContent>
                  {estoqueUfs.map(uf => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Tag da Região (Ex: Alvorada, Zona Sul)</Label>
              <Input 
                placeholder="Nome da região..." 
                value={newRegionTag} 
                onChange={e => setNewRegionTag(e.target.value)} 
              />
            </div>
            {selectedUfForRegion && (
              <p className="text-xs text-muted-foreground bg-blue-50 p-2 rounded">
                <strong>Nota:</strong> Se esta for a primeira região de {selectedUfForRegion}, todos os itens atuais da UF serão migrados para <strong>{selectedUfForRegion}1</strong> automaticamente.
              </p>
            )}
            <Button onClick={handleCreateRegion} className="w-full bg-sf-green" disabled={submittingUf}>
              {submittingUf ? 'Criando...' : 'Criar Região'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
      {/* Dialog confirmar delete Região */}
      <AlertDialog open={!!deleteRegionTarget} onOpenChange={() => setDeleteRegionTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remover Região "{deleteRegionTarget?.codigo}"?</AlertDialogTitle>
            <AlertDialogDescription>
              Esta ação removerá a região selecionada. Os dados de estoque atuais desta região serão preservados como históricos, mas o código não aparecerá mais nos filtros.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              className="bg-red-500 hover:bg-red-600 text-white"
              onClick={handleDeleteRegion}
            >
              Remover Região
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

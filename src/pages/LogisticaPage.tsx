import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { formatBRL } from '@/lib/format';
import { Printer, Lock, Truck, Loader2, Download, Trash2, MoreVertical, CheckCircle, CircleDollarSign, XCircle } from 'lucide-react';
import { getTagDisplayName } from '@/lib/productDisplayNames';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { useIsAdmin } from '@/hooks/useIsAdmin';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';
import { useAuth } from '@/hooks/useAuth';

type ProdutoPesoRow = {
  tag: string;
  peso: number | null;
};

type PedidoProdutoItem = {
  produto?: string;
  quantidade?: number;
};

const getEdgeFnHeaders = async () => {
  const { data: { session } } = await supabase.auth.getSession();
  const key =
    import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
    import.meta.env.VITE_SUPABASE_ANON_KEY;
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${session?.access_token || key}`,
    'apikey': key,
  };
};


export default function LogisticaPage() {
  const { profile, user } = useAuth();
  const isAdmin = useIsAdmin();
  const isRepresentante = profile?.tipo_usuario === 'representante';
  const [loading, setLoading] = useState(true);
  const [pedidos, setPedidos] = useState<any[]>([]);
  const [ufFilter, setUfFilter] = useState('Todos');
  const [remetentes, setRemetentes] = useState<Record<string, any>>({});
  const [selectedUfForm, setSelectedUfForm] = useState<string | null>(null);
  const [formData, setFormData] = useState<any>({});
  const [saving, setSaving] = useState(false);
  const [generatingAll, setGeneratingAll] = useState(false);
  const [generatingId, setGeneratingId] = useState<string | null>(null);
  const [deleteEtiquetaTarget, setDeleteEtiquetaTarget] = useState<any>(null);
  const [deletingEtiqueta, setDeletingEtiqueta] = useState(false);
  const [marcarPostadoTarget, setMarcarPostadoTarget] = useState<any>(null);
  const [markingPostado, setMarkingPostado] = useState(false);
  const [estoqueUfs, setEstoqueUfs] = useState<string[]>([]);
  const [ufRegioes, setUfRegioes] = useState<{ id: string; uf: string; tag: string; codigo: string }[]>([]);
  const [fretesCotados, setFretesCotados] = useState<Record<string, number>>({});
  const [payingId, setPayingId] = useState<string | null>(null);
  const [payingAll, setPayingAll] = useState(false);
  const [etiquetasLocais, setEtiquetasLocais] = useState<Record<string, { url: string; codigo: string; valor: number; paga: boolean }>>({});
  const [printingId, setPrintingId] = useState<string | null>(null);
  const [produtosInfo, setProdutosInfo] = useState<Record<string, { box_size: string | null; box_qty_max: number | null }>>({});
  const [gatewaysConectados, setGatewaysConectados] = useState<{ superfrete: boolean; melhorenvio: boolean }>({ superfrete: false, melhorenvio: false });
  const [updatingGateway, setUpdatingGateway] = useState<string | null>(null);

  // Auto-zoom out apenas em mobile para que todos os botões do card caibam sem scroll horizontal
  useEffect(() => {
    if (typeof window === 'undefined') return;
    if (window.innerWidth >= 640) return; // só mobile (sm breakpoint)
    const meta = document.querySelector('meta[name="viewport"]') as HTMLMetaElement | null;
    if (!meta) return;
    const original = meta.getAttribute('content') || 'width=device-width, initial-scale=1.0';
    meta.setAttribute('content', 'width=device-width, initial-scale=0.85, maximum-scale=1.0, user-scalable=yes');
    return () => {
      meta.setAttribute('content', original);
    };
  }, []);

  // Ordem hierárquica de tamanhos de caixa
  const BOX_ORDER = ['mini', 'p', 'm', 'g', 'gg'];
  const normalizeBox = (b?: string | null) => (b || '').toString().trim().toLowerCase();
  const boxRank = (b?: string | null) => {
    const idx = BOX_ORDER.indexOf(normalizeBox(b));
    return idx === -1 ? 0 : idx;
  };
  const boxLabel = (b?: string | null) => {
    const n = normalizeBox(b);
    if (!n) return '';
    if (n === 'mini') return 'Mini';
    return n.toUpperCase();
  };

  // Calcula a maior caixa entre os produtos do pedido (independente da modalidade).
  // Regra: usa o MAIOR box_size cadastrado entre os produtos. Se nenhum produto
  // tiver box_size cadastrado, assume Mini como padrão (todo card deve exibir caixa).
  const getCaixaCalculada = (pedido: any): { label: string; raw: string } => {
    const items = getPedidoItems(pedido);
    let maxBox = '';
    for (const it of items) {
      const tag = it.produto;
      if (!tag) continue;
      const info = produtosInfo[tag];
      if (info?.box_size && boxRank(info.box_size) > boxRank(maxBox)) {
        maxBox = normalizeBox(info.box_size);
      }
    }
    if (!maxBox) maxBox = 'mini';
    return { label: boxLabel(maxBox), raw: maxBox };
  };

  // Verifica se MINI ultrapassa box_qty_max de algum produto
  const miniExcedeu = (pedido: any): boolean => {
    if (normalizeBox(pedido.modalidade) !== 'mini') return false;
    const items = getPedidoItems(pedido);
    const totalQtd = items.reduce((s, it) => s + (it.quantidade || 0), 0);
    for (const it of items) {
      const tag = it.produto;
      if (!tag) continue;
      const info = produtosInfo[tag];
      const max = info?.box_qty_max ?? 10;
      if (totalQtd > max) return true;
    }
    return false;
  };

  // UF de destino do contato (extrai os últimos 2 chars de cidade_uf)
  const getUfDestino = (pedido: any): string => {
    const cu = pedido.contatos?.cidade_uf || '';
    const m = cu.match(/([A-Z]{2})\s*$/i);
    return m ? m[1].toUpperCase() : (pedido.uf_cliente || '').toUpperCase();
  };

  // SuperFrete service IDs (oficial): 1=PAC, 2=SEDEX, 17=Mini Envios
  const getModalidadeService = (modalidade?: string): number => {
    if (!modalidade) {
      console.warn('Modalidade vazia, usando padrão SEDEX');
      return 2;
    }
    const mod = String(modalidade).trim().toLowerCase();
    console.log('getModalidadeService converting:', modalidade, '->', mod);
    if (mod === 'mini') return 17;
    if (mod === 'pac') return 1;
    if (mod === 'sedex') return 2;
    console.warn('Modalidade desconhecida:', modalidade, '- usando padrão SEDEX');
    return 2;
  };

  const getPedidoItems = (pedido: any): PedidoProdutoItem[] => {
    try {
      const parsed = JSON.parse(pedido.produto);
      if (Array.isArray(parsed)) return parsed;
    } catch {
      // noop
    }

    return [{ produto: pedido.produto, quantidade: pedido.quantidade || 1 }];
  };

  const getPesoMap = async (items: PedidoProdutoItem[]) => {
    const tags = Array.from(new Set(items.map(item => item.produto).filter(Boolean)));
    if (tags.length === 0) return new Map<string, number>();

    const { data } = await supabase
      .from('produtos')
      .select('tag, peso')
      .in('tag', tags);

    return new Map(
      ((data || []) as ProdutoPesoRow[]).map((produto) => [produto.tag, produto.peso || 300]),
    );
  };

  const calcularPesoTotal = async (pedido: any) => {
    const items = getPedidoItems(pedido);
    const pesoMap = await getPesoMap(items);

    const totalPeso = items.reduce((sum, item) => {
      const tag = item.produto || '';
      const peso = pesoMap.get(tag) || 300;
      const qtd = item.quantidade || 1;
      return sum + (peso * qtd);
    }, 0);

    return totalPeso || 300;
  };

  const getFreteDisplayValue = (pedido: any) => {
    // Primeiro verifica estado local (atualização instantânea)
    const local = etiquetasLocais[pedido.id];
    if (local && local.valor) return local.valor;
    
    const cotado = fretesCotados[pedido.id];
    if (typeof cotado === 'number') return cotado;
    if (pedido.etiqueta_valor) {
      return Number(pedido.etiqueta_valor);
    }
    if (pedido.etiqueta_codigo) {
      return fretesCotados[pedido.id] || null;
    }
    return null;
  };

  // Helper para verificar se tem etiqueta (local ou banco)
  const temEtiqueta = (pedido: any): boolean => {
    const local = etiquetasLocais[pedido.id];
    if (local?.codigo) return true;
    if (pedido.etiqueta_codigo) return true;
    return false;
  };

  // Helper para verificar se etiqueta está paga
  const isEtiquetaPaga = (pedido: any): boolean => {
    const local = etiquetasLocais[pedido.id];
    if (local?.paga !== undefined) return local.paga;
    return pedido.etiqueta_paga === true;
  };

  // Helper para obter URL da etiqueta
  const getEtiquetaUrl = (pedido: any): string | null => {
    const local = etiquetasLocais[pedido.id];
    if (local?.url) return local.url;
    return pedido.etiqueta_url || null;
  };

  // Helper para obter código da etiqueta
  const getEtiquetaCodigo = (pedido: any): string | null => {
    const local = etiquetasLocais[pedido.id];
    if (local?.codigo) return local.codigo;
    return pedido.etiqueta_codigo || null;
  };

  useEffect(() => { fetchAll(); }, []);

  useEffect(() => {
    const channel = supabase
      .channel('pedidos-logistica')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'pedidos' }, () => {
        fetchPedidos();
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, []);

  useEffect(() => {
    console.log('useEffect cotarFretes - pedidos:', pedidos.length, 'remetentes:', Object.keys(remetentes).length, 'loading:', loading);
    if (pedidos.length > 0 && Object.keys(remetentes).length > 0 && !loading) {
      cotarFretes();
    }
  }, [pedidos.map(p => p.id).join(','), Object.keys(remetentes).join(','), loading]);

  const cotarFrete = async (pedido: any): Promise<number | null> => {
    const rem = remetentes[pedido.uf_postagem?.replace(/[0-9]/g, '') || pedido.uf_postagem];
    if (!rem?.cep_origem) return null;

    const { data: config } = await supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').single();
    if (!config?.valor) return null;

    const contato = pedido.contatos;
    if (!contato?.cep) return null;

    const totalPeso = await calcularPesoTotal(pedido);

    console.log('Peso total calculado:', totalPeso, 'para pedido:', pedido.id);

    const service = getModalidadeService(pedido.modalidade);
    console.log('CotandoFrete - service:', pedido.modalidade, '->', service);

    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/cotar-frete`, {
        method: 'POST',
        headers: await getEdgeFnHeaders(),
        body: JSON.stringify({
          from_cep: rem.cep_origem.replace(/\D/g, ''),
          to_cep: contato.cep.replace(/\D/g, ''),
          peso: totalPeso || 300,
          service,
          api_key: config.valor,
        }),
      });
      if (!res.ok) {
        const errorBody = await res.text();
        console.error('Erro cotar-frete:', res.status, errorBody);
        return null;
      }
      const data = await res.json();
      console.log('cotar-frete response:', data);
      return data.price || null;
    } catch (e) { 
      console.error('Erro cotar-frete catch:', e);
      return null; 
    }
  };

  const cotarFretes = async () => {
    const { data: config } = await supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').single();
    if (!config?.valor) return;

    const pendentes = pedidos.filter(p => p.uf_postagem && !fretesCotados[p.id]);
    if (pendentes.length === 0) return;

    // Paralelizar cotações (era sequencial, causando lentidão proporcional ao nº de pedidos)
    const resultados = await Promise.all(
      pendentes.map(async p => ({ id: p.id, valor: await cotarFrete(p).catch(() => null) }))
    );

    const novosFretes: Record<string, number> = {};
    for (const r of resultados) {
      if (r.valor) novosFretes[r.id] = r.valor;
    }
    if (Object.keys(novosFretes).length > 0) {
      setFretesCotados(prev => ({ ...prev, ...novosFretes }));
    }
  };

  const fetchAll = async () => {
    setLoading(true);
    await Promise.all([fetchPedidos(), fetchRemetentes(), fetchUfs(), fetchGateways()]);
    setLoading(false);
  };

  const fetchGateways = async () => {
    const { data } = await supabase
      .from('configuracoes')
      .select('chave, valor')
      .in('chave', ['chave_api_superfrete', 'chave_api_melhorenvio']);
    const sf = (data || []).find(d => d.chave === 'chave_api_superfrete');
    const me = (data || []).find(d => d.chave === 'chave_api_melhorenvio');
    setGatewaysConectados({
      superfrete: !!(sf?.valor && sf.valor.trim().length > 10),
      melhorenvio: !!(me?.valor && me.valor.trim().length > 10),
    });
  };

  const updatePedidoGateway = async (pedidoId: string, gateway: string) => {
    setUpdatingGateway(pedidoId);
    const { error } = await supabase
      .from('pedidos')
      .update({ gateway_etiqueta: gateway } as any)
      .eq('id', pedidoId);
    setUpdatingGateway(null);
    if (error) {
      toast.error('Erro ao atualizar gateway');
      return;
    }
    setPedidos(prev => prev.map(p => p.id === pedidoId ? { ...p, gateway_etiqueta: gateway } : p));
  };

  const fetchUfs = async () => {
    const [{ data }, { data: regionsData }, { data: prodData }] = await Promise.all([
      supabase.from('estoque_ufs' as any).select('uf').order('uf'),
      supabase.from('uf_regioes' as any).select('*').order('codigo'),
      supabase.from('produtos').select('tag, box_size, box_qty_max'),
    ]);
    if (data && data.length > 0) {
      setEstoqueUfs((data as any[]).map((u: any) => u.uf));
    }
    setUfRegioes((regionsData as any[] || []) as { id: string; uf: string; tag: string; codigo: string }[]);
    const map: Record<string, { box_size: string | null; box_qty_max: number | null }> = {};
    for (const p of (prodData || []) as any[]) {
      map[p.tag] = { box_size: p.box_size, box_qty_max: p.box_qty_max };
    }
    setProdutosInfo(map);
  };

  const fetchPedidos = async () => {
    let query = supabase
      .from('pedidos')
      .select('*, contatos(nome, cpf, endereco, complemento, bairro, cidade_uf, cep, telefone), etiqueta_paga, etiqueta_codigo, etiqueta_url, etiqueta_valor')
      .eq('status_pedido', 'aguardando_rastreio')
      .neq('modalidade', 'entrega_maos')
      .order('data', { ascending: false });

    if (isRepresentante) {
      query = query.eq('representante_id', user?.id);
    }

    const { data } = await query;
    setPedidos(data || []);
  };

  const fetchRemetentes = async () => {
    const { data } = await supabase.from('remetentes_uf').select('*');
    const map: Record<string, any> = {};
    (data || []).forEach(r => { map[r.uf] = r; });
    setRemetentes(map);
  };

  const openUfForm = (uf: string) => {
    const baseUf = uf.replace(/[0-9]/g, '');
    setSelectedUfForm(baseUf);
    setFormData(remetentes[baseUf] || { uf: baseUf });
  };

  const handleCepBlur = async () => {
    const cep = formData.cep_origem?.replace(/\D/g, '');
    if (!cep || cep.length !== 8) return;
    try {
      const res = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
      const data = await res.json();
      if (!data.erro) {
        setFormData((prev: any) => ({ ...prev, cidade: `${data.localidade}/${data.uf}`, bairro: data.bairro || prev.bairro, endereco: data.logradouro || prev.endereco }));
      }
    } catch {}
  };

  const saveRemetente = async () => {
    if (!selectedUfForm) return;
    setSaving(true);
    
    const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
    const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/salvar_remetente`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Prefer': 'return=minimal',
        },
        body: JSON.stringify({
          p_uf_in: selectedUfForm,
          p_cep_origem: formData.cep_origem || '',
          p_cidade: formData.cidade || '',
          p_bairro: formData.bairro || '',
          p_endereco: formData.endereco || '',
          p_numero: formData.numero || '',
          p_complemento: formData.complemento || '',
          p_nome_remetente: formData.nome_remetente || '',
          p_contato_remetente: formData.contato_remetente || '',
          p_cpf: formData.cpf || '',
          p_descricao_produto: formData.descricao_produto || '',
          p_valor_unitario: formData.valor_unitario ? parseFloat(String(formData.valor_unitario).replace(',', '.')) : null,
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(errorText);
      }

      console.log('Remetente salvo');

      toast.success('Dados do remetente salvos!');
      await fetchRemetentes();
      setSelectedUfForm(null);
    } catch (err: any) {
      console.error('Erro ao salvar remetente:', err);
      toast.error('Erro ao salvar remetente: ' + err.message);
    } finally {
      setSaving(false);
    }
  };

  const updatePedidoUf = async (pedidoId: string, newUf: string) => {
    const pedido = pedidos.find(p => p.id === pedidoId);
    if (!pedido) return;
    const oldUf = pedido.uf_postagem;

    try {
      // Se já existe UF e está mudando: atualiza uf_origem das saídas existentes
      if (oldUf && oldUf !== newUf) {
        const { error: movErr } = await supabase
          .from('estoque_movimentacoes')
          .update({ uf_origem: newUf })
          .eq('pedido_id', pedidoId)
          .eq('tipo', 'saida');
        if (movErr) throw movErr;

        if (isAdmin) {
          await supabase.from('log_atividades').insert({
            usuario: profile?.nome || 'Sistema',
            acao: `Trocou UF de postagem ${oldUf}→${newUf}`,
            tabela_afetada: 'pedidos',
            registro_id: pedidoId,
            detalhe: `Pedido ${pedido.order_number || ''} de ${(pedido.contatos as any)?.nome || ''}`,
          });
        }
      }

      const { error: pedErr } = await supabase.from('pedidos').update({ uf_postagem: newUf }).eq('id', pedidoId);
      if (pedErr) throw pedErr;

      toast.success(oldUf ? `UF alterada de ${oldUf} para ${newUf}` : 'Origem definida!');
      fetchPedidos();
    } catch (err: any) {
      console.error('Erro ao trocar UF:', err);
      toast.error('Erro ao trocar UF: ' + err.message);
    }
  };

  

  const validarDadosEtiqueta = (pedido: any) => {
    const erros: string[] = [];
    
    if (!pedido.uf_postagem) erros.push('UF de postagem não definida');
    
    const rem = remetentes[pedido.uf_postagem?.replace(/[0-9]/g, '') || pedido.uf_postagem];
    if (!rem?.cep_origem) erros.push('Remetente não configurado para esta UF');
    if (!rem?.nome_remetente) erros.push('Nome do remetente não configurado');
    
    const contato = pedido.contatos;
    if (!contato?.cep) erros.push('CEP do destinatário não encontrado');
    if (!contato?.endereco) erros.push('Endereço do destinatário não encontrado');
    if (!contato?.cidade_uf) erros.push('Cidade/UF do destinatário não encontrada');
    
    return erros;
  };

  const gerarEtiqueta = async (pedido: any) => {
    // GUARD anti-duplicata: se já gerou, ignora (previne race / clique duplo / batch repetido)
    if (pedido.etiqueta_codigo || pedido.etiqueta_url || etiquetasLocais[pedido.id]?.codigo) {
      console.log('[gerar-etiqueta] pedido já tem etiqueta, ignorando duplicata', pedido.id);
      return;
    }
    if (generatingId === pedido.id) {
      console.log('[gerar-etiqueta] já gerando este pedido, ignorando', pedido.id);
      return;
    }

    const validacao = validarDadosEtiqueta(pedido);
    if (validacao.length > 0) {
      toast.error(`Dados incompletos: ${validacao.join(', ')}`);
      return;
    }
    
    setGeneratingId(pedido.id);

    // GUARD remoto: re-confirma no banco que ainda não tem etiqueta (defesa contra race com outro usuário/aba)
    try {
      const { data: fresh } = await supabase.from('pedidos')
        .select('etiqueta_codigo, etiqueta_url')
        .eq('id', pedido.id)
        .maybeSingle();
      if (fresh?.etiqueta_codigo || fresh?.etiqueta_url) {
        console.log('[gerar-etiqueta] etiqueta já existe no banco, abortando', pedido.id);
        setGeneratingId(null);
        // Sincroniza state local pra UI refletir
        fetchPedidos();
        return;
      }
    } catch (e) {
      console.warn('[gerar-etiqueta] falha no check remoto, prosseguindo', e);
    }
    
    try {
      const { data: config } = await supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').single();
      if (!config?.valor) {
        toast.error('Configure a chave API do Super Frete na aba Integrações');
        setGeneratingId(null);
        return;
      }

      console.log('=== INICIANDO GERAR ETIQUETA ===', pedido.id);
      console.log('Pedido modalidade:', pedido.modalidade);

// Calcular frete antes de emitir (cotação real via rates)
      const valorFrete = await cotarFrete(pedido);
      console.log('ValorFrete cotado:', valorFrete);

      const rem = remetentes[pedido.uf_postagem?.replace(/[0-9]/g, '') || pedido.uf_postagem];
      const contato = pedido.contatos;
      const totalPeso = await calcularPesoTotal(pedido);
      const service = getModalidadeService(pedido.modalidade);
      
      console.log('Modalidade convertida:', pedido.modalidade, '-> service:', service);

      console.log('Gerando etiqueta - Peso total:', totalPeso, ' CEP Dest:', contato.cep);

      const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
      const res = await fetch(`${SUPABASE_URL}/functions/v1/gerar-etiqueta`, {
        method: 'POST',
        headers: await getEdgeFnHeaders(),
        body: JSON.stringify({
          from_name: rem.nome_remetente,
          from_document: rem.cpf,
          from_address: rem.endereco,
          from_number: rem.numero,
          from_complement: rem.complemento,
          from_district: rem.bairro,
          from_city: rem.cidade.split('/')[0],
          from_state: pedido.uf_postagem.replace(/[0-9]/g, ''),
          from_cep: rem.cep_origem,
          from_phone: rem.contato_remetente,
          to_name: contato.nome,
          to_document: contato.cpf,
          to_address: contato.endereco,
          to_district: contato.bairro,
          to_city: contato.cidade_uf?.replace(/\/\w+$/, ''),
          to_state: contato.cidade_uf?.slice(-2),
          to_cep: contato.cep,
          to_phone: contato.telefone,
          peso: totalPeso || 300,
          width: 11,
          height: 2,
          length: 16,
          service,
          api_key: config.valor,
          valor_frete_cotado: valorFrete,
          // DAC: descrição/qtd/valor — usa o que está no remetente_uf (ex: "homeopatia", R$ 80)
          products: (() => {
            const items = getPedidoItems(pedido);
            const totalQtd = items.reduce((s, i) => s + (i.quantidade || 1), 0) || 1;
            const desc = rem.descricao_produto || 'Produto';
            const valorUnit = Number(rem.valor_unitario) || 0;
            return [{
              name: desc,
              quantity: totalQtd,
              unitary_value: valorUnit,
            }];
          })(),
        }),
      });

      if (!res.ok) {
        let errData: any = {};
        let rawText = '';
        try {
          rawText = await res.text();
          errData = JSON.parse(rawText);
        } catch {
          errData = { error: rawText || `HTTP ${res.status}` };
        }
        console.error('gerar-etiqueta error:', { status: res.status, errData });
        const detalhes = errData.details
          ? ' — ' + (typeof errData.details === 'string' ? errData.details : JSON.stringify(errData.details))
          : '';
        toast.error(`Erro ao gerar etiqueta (${res.status}): ${errData.error || errData.message || 'verifique a chave API'}${detalhes}`);
        setGeneratingId(null);
        return;
      }

      const result = await res.json();
      console.log('gerar-etiqueta success:', result);
      
      const etiquetaUrl = result.label || result.print_url || result.pdf || '';
      // ID SuperFrete (necessário para pagar/cancelar) — fica em etiqueta_codigo
      const superfreteId = result.id || result.order_id || '';
      // OBS: codigo_rastreio (Correios/Jadlog) só vem APÓS pagar — não tentamos pegar aqui
      // Valor real cobrado pela SuperFrete (vem direto na resposta do cart)
      const valorReal = typeof result.price === 'number' ? result.price 
                       : (typeof result.price === 'string' ? parseFloat(result.price) : null);
      const valorFinal = valorReal ?? valorFrete ?? null;

      console.log('valorFinal a salvar:', valorFinal, '(SuperFrete price:', valorReal, '| cotação:', valorFrete, ')');

      await supabase.from('pedidos').update({
        etiqueta_url: etiquetaUrl,
        etiqueta_codigo: superfreteId,
        etiqueta_valor: valorFinal,
      }).eq('id', pedido.id);

      if (valorFinal) {
        setFretesCotados(prev => ({ ...prev, [pedido.id]: valorFinal }));
      }

      toast.success('Etiqueta gerada! Agora clique em Pagar para emitir o rastreio');
      
      const novoEstado = {
        url: etiquetaUrl,
        codigo: superfreteId,
        valor: valorFinal ?? 0,
        paga: false,
      };
      setEtiquetasLocais(prev => ({ ...prev, [pedido.id]: novoEstado }));
      
      setPedidos(prev => prev.map(ped => {
        if (ped.id === pedido.id) {
          return { 
            ...ped, 
            etiqueta_url: etiquetaUrl, 
            etiqueta_codigo: superfreteId,
            etiqueta_valor: valorFinal,
          };
        }
        return ped;
      }));
      
      fetchPedidos();
    } catch (err) {
      console.error(err);
      toast.error('Erro ao gerar etiqueta');
    } finally {
      setGeneratingId(null);
    }
  };

  const handleMarcarPostado = async () => {
    if (!marcarPostadoTarget) return;
    setMarkingPostado(true);
    try {
      const { error } = await supabase.from('pedidos')
        .update({ status_pedido: 'postado' })
        .eq('id', marcarPostadoTarget.id);
      
      if (error) throw error;

      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Sistema',
        acao: 'Marcou como postado manualmente',
        tabela_afetada: 'pedidos',
        registro_id: marcarPostadoTarget.id,
        detalhe: `Pedido de ${(marcarPostadoTarget.contatos as any)?.nome}`
      });

toast.success('Pedido marcado como postado');
      
      setPedidos(prev => prev.filter(pedido => pedido.id !== marcarPostadoTarget.id));
      setMarcarPostadoTarget(null);
    } catch (err: any) {
      toast.error('Erro ao marcar como postado: ' + err.message);
    } finally {
      setMarkingPostado(false);
    }
  };

  const imprimirEtiqueta = async (pedido: any) => {
    const codigo = getEtiquetaCodigo(pedido);

    if (!codigo) {
      toast.error('Etiqueta não gerada');
      return;
    }

    // SEMPRE buscar URL fresca da SuperFrete via /order/info/{id}.
    // A URL salva no banco vem do momento da geração e pode dar "Internal Server Error"
    // (a URL definitiva só é confiável no campo print.url retornado pela API após o pagamento).
    // Pré-abre janela ANTES de qualquer await (mantém user-gesture / evita popup-blocker).
    const popup = window.open('about:blank', '_blank');

    setPrintingId(pedido.id);
    try {
      const { data: config } = await supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').single();
      if (!config?.valor) {
        toast.error('Configure a chave API do Super Frete');
        popup?.close();
        return;
      }

      const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
      const ctrl = new AbortController();
      const tid = setTimeout(() => ctrl.abort(), 15000);
      const res = await fetch(`${SUPABASE_URL}/functions/v1/imprimir-etiqueta`, {
        method: 'POST',
        headers: await getEdgeFnHeaders(),
        body: JSON.stringify({ order_id: codigo, api_key: config.valor }),
        signal: ctrl.signal,
      }).finally(() => clearTimeout(tid));

      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        toast.error('Erro ao buscar PDF: ' + (err.error || res.status));
        popup?.close();
        return;
      }
      const data = await res.json();
      const url = data.url;
      const status = data.status;

      if (!url) {
        // Mensagem específica conforme o estado da etiqueta na SuperFrete
        if (status === 'released' || status === 'pending') {
          toast.error('Etiqueta ainda não foi paga na SuperFrete. Pague antes de imprimir.');
        } else {
          toast.error('PDF ainda não disponível. Aguarde alguns segundos e tente novamente.');
        }
        popup?.close();
        return;
      }

      // Salva URL atualizada pra reuso (se quiser cachear de novo no futuro)
      await supabase.from('pedidos').update({ etiqueta_url: url }).eq('id', pedido.id);
      setEtiquetasLocais(prev => ({
        ...prev,
        [pedido.id]: { ...(prev[pedido.id] || { codigo: codigo!, valor: 0, paga: true }), url }
      }));

      // Aponta a janela já aberta. Fallback: se popup foi bloqueado, abre normal.
      if (popup && !popup.closed) {
        popup.location.href = url;
      } else {
        window.open(url, '_blank');
      }
    } catch (e: any) {
      toast.error('Erro ao imprimir: ' + (e?.message || 'desconhecido'));
      popup?.close();
    } finally {
      setPrintingId(null);
    }
  };

  const pagarEtiqueta = async (pedido: any) => {
    const codigo = getEtiquetaCodigo(pedido);
    if (!codigo) {
      toast.error('Etiqueta não gerada');
      return;
    }

    setPayingId(pedido.id);
    try {
      const { data: config } = await supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').single();
      if (!config?.valor) {
        toast.error('Configure a chave API do Super Frete na aba Integrações');
        return;
      }

      const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
      const ctrl = new AbortController();
      const tid = setTimeout(() => ctrl.abort(), 25000);
      const res = await fetch(`${SUPABASE_URL}/functions/v1/pagar-etiqueta`, {
        method: 'POST',
        headers: await getEdgeFnHeaders(),
        body: JSON.stringify({
          order_id: codigo,
          api_key: config.valor,
        }),
        signal: ctrl.signal,
      }).finally(() => clearTimeout(tid));

      if (!res.ok) {
        const errData = await res.json();
        const errorMsg = errData.error || errData.message || 'Erro ao pagar';
        const lower = errorMsg.toLowerCase();
        const alreadyPaid =
          lower.includes('paga') || lower.includes('already') ||
          lower.includes('released') || lower.includes('emitted') ||
          lower.includes('checkout') || lower.includes('posted') ||
          lower.includes('comprad') || lower.includes('purchased') ||
          lower.includes('ja foi') || lower.includes('já foi');

        if (alreadyPaid) {
          // Etiqueta ja estava paga no SuperFrete: sincroniza status no banco
          try {
            const infoRes = await fetch(`${SUPABASE_URL}/functions/v1/imprimir-etiqueta`, {
              method: 'POST',
              headers: await getEdgeFnHeaders(),
              body: JSON.stringify({ order_id: codigo, api_key: config.valor }),
            });
            if (infoRes.ok) {
              const info = await infoRes.json();
              const updates: any = { etiqueta_paga: true };
              if (info.tracking) updates.codigo_rastreio = info.tracking;
              if (info.url) updates.etiqueta_url = info.url;
              await supabase.from('pedidos').update(updates).eq('id', pedido.id);
              toast.success('Etiqueta ja estava paga — status sincronizado');
              fetchPedidos();
              return;
            }
          } catch (syncErr) {
            console.error('Falha ao sincronizar etiqueta paga:', syncErr);
          }
        }

        if (lower.includes('saldo') || lower.includes('insufficient')) {
          toast.error('Saldo insuficiente no Super Frete!');
        } else {
          toast.error(`Erro ao pagar etiqueta: ${errorMsg}`);
        }
        return;
      }

      const result = await res.json();
      
      if (result.success || result.tracking) {
        // Atualiza local primeiro
        setEtiquetasLocais(prev => ({
          ...prev,
          [pedido.id]: { ...prev[pedido.id], paga: true, url: result.print_url || prev[pedido.id]?.url || '' }
        }));
        
        // Atualiza no banco — preserva ID SuperFrete em etiqueta_codigo, atualiza rastreio se vier novo
        const updates: any = { etiqueta_paga: true };
        if (result.tracking && result.tracking !== pedido.codigo_rastreio) {
          updates.codigo_rastreio = result.tracking;
        }
        if (result.print_url) {
          updates.etiqueta_url = result.print_url;
        }
        await supabase.from('pedidos').update(updates).eq('id', pedido.id);
        
        toast.success('Etiqueta paga e emitida com sucesso!');
        fetchPedidos();
      } else {
        toast.error('Pagamento não confirmado');
      }
    } catch (err) {
      console.error(err);
      toast.error('Erro ao pagar etiqueta');
    } finally {
      setPayingId(null);
    }
  };

  const pagarTodas = async () => {
    const allEligible = filteredPedidos.filter(p => p.uf_postagem && temEtiqueta(p) && !isEtiquetaPaga(p));
    const eligible = allEligible.filter(p => ((p as any).gateway_etiqueta || 'superfrete') === 'superfrete');
    const skippedME = allEligible.length - eligible.length;
    if (eligible.length === 0) {
      toast.error(skippedME > 0 ? `${skippedME} pedido(s) Melhor Envio aguardam integração (Fase 2)` : 'Nenhuma etiqueta gerada para pagar');
      return;
    }
    if (skippedME > 0) toast.info(`${skippedME} pedido(s) Melhor Envio serão ignorados (Fase 2)`);

    setPayingAll(true);
    let success = 0;
    const errors: string[] = [];

    for (const p of eligible) {
      try {
        const { data: config } = await supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').single();
        if (!config?.valor) {
          errors.push('API não configurada');
          continue;
        }

        const codigo = getEtiquetaCodigo(p);
        if (!codigo) {
          errors.push('Sem código');
          continue;
        }

        const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
        const res = await fetch(`${SUPABASE_URL}/functions/v1/pagar-etiqueta`, {
          method: 'POST',
          headers: await getEdgeFnHeaders(),
          body: JSON.stringify({ order_id: codigo, api_key: config.valor }),
        });

        if (res.ok) {
          const result = await res.json();
          if (result.success || result.tracking) {
            setEtiquetasLocais(prev => ({
              ...prev,
              [p.id]: { ...prev[p.id], paga: true, url: result.print_url || prev[p.id]?.url || '' }
            }));
            const updates: any = { etiqueta_paga: true };
            if (result.tracking && result.tracking !== p.codigo_rastreio) updates.codigo_rastreio = result.tracking;
            if (result.print_url) updates.etiqueta_url = result.print_url;
            await supabase.from('pedidos').update(updates).eq('id', p.id);
            success++;
          }
        } else {
          const errData = await res.json();
          const nome = (p.contatos as any)?.nome || p.id.slice(0,8);
          if (errData.error?.toLowerCase().includes('saldo')) {
            errors.push(`${nome}: Saldo insuficiente!`);
          } else {
            errors.push(nome);
          }
        }
      } catch {
        errors.push(p.id.slice(0,8));
      }
    }

    setPayingAll(false);
    if (success > 0) toast.success(`${success} etiqueta(s) paga(s)!`);
    if (errors.length > 0) toast.error(`Erros: ${errors.join(', ')}`);
    fetchPedidos();
  };

  const handleDeleteEtiqueta = async () => {
    if (!deleteEtiquetaTarget) return;
    setDeletingEtiqueta(true);
    try {
      const { data: config } = await supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').single();
      const codigo = deleteEtiquetaTarget.etiqueta_codigo;

      if (config?.valor && codigo) {
        try {
          const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
          const res = await fetch(`${SUPABASE_URL}/functions/v1/cancelar-etiqueta`, {
            method: 'POST',
            headers: await getEdgeFnHeaders(),
            body: JSON.stringify({
              order_id: codigo,
              api_key: config.valor,
              reason: 'Desistência da compra',
            }),
          });
          const result = await res.json();
          console.log('cancelar-etiqueta result:', result);
          if (result.error && !result.cleared_locally) {
            console.warn('SuperFrete cancel falhou:', result.error);
          }
        } catch (e) {
          console.error('cancelar-etiqueta fetch error:', e);
        }
      }

      // Sempre limpar campos locais (UX consistente)
      const { error: updErr } = await supabase.from('pedidos').update({
        etiqueta_url: null,
        etiqueta_codigo: null,
        etiqueta_valor: null,
        etiqueta_paga: null,
        codigo_rastreio: null,
      }).eq('id', deleteEtiquetaTarget.id);

      if (updErr) throw updErr;

      await supabase.from('log_atividades').insert({
        usuario: profile?.nome || 'Sistema',
        acao: 'Cancelou etiqueta',
        tabela_afetada: 'pedidos',
        registro_id: deleteEtiquetaTarget.id,
        detalhe: `Pedido de ${(deleteEtiquetaTarget.contatos as any)?.nome}`,
      });

      setEtiquetasLocais(prev => {
        const next = { ...prev };
        delete next[deleteEtiquetaTarget.id];
        return next;
      });

      toast.success('Etiqueta cancelada');
      fetchPedidos();
    } catch (err: any) {
      console.error('handleDeleteEtiqueta error:', err);
      toast.error('Erro ao cancelar etiqueta: ' + (err?.message || 'desconhecido'));
    } finally {
      setDeletingEtiqueta(false);
      setDeleteEtiquetaTarget(null);
    }
  };

  const gerarTudo = async () => {
    // Re-fetch fresh do banco pra evitar gerar etiqueta pra pedidos que já receberam (race / state stale)
    const candidateIds = filteredPedidos.filter(p => p.uf_postagem && !p.etiqueta_url).map(p => p.id);
    let jaTemEtiqueta = new Set<string>();
    if (candidateIds.length > 0) {
      const { data: fresh } = await supabase.from('pedidos')
        .select('id, etiqueta_codigo, etiqueta_url')
        .in('id', candidateIds);
      jaTemEtiqueta = new Set((fresh || []).filter(p => p.etiqueta_codigo || p.etiqueta_url).map(p => p.id));
    }
    const allEligible = filteredPedidos.filter(p => p.uf_postagem && !p.etiqueta_url && !jaTemEtiqueta.has(p.id));
    const eligible = allEligible.filter(p => ((p as any).gateway_etiqueta || 'superfrete') === 'superfrete');
    const skippedME = allEligible.length - eligible.length;
    const waiting = filteredPedidos.filter(p => !p.uf_postagem);
    if (eligible.length === 0) { toast.info(skippedME > 0 ? `${skippedME} pedido(s) Melhor Envio aguardam integração (Fase 2)` : 'Nenhum pedido elegível para geração'); return; }
    if (skippedME > 0) toast.info(`${skippedME} pedido(s) Melhor Envio serão ignorados (Fase 2)`);
    setGeneratingAll(true);
    
    let success = 0;
    const errors: string[] = [];
    
    for (const p of eligible) {
      try {
        await gerarEtiqueta(p);
        success++;
      } catch (err: any) {
        const nome = (p.contatos as any)?.nome || p.id.slice(0,8);
        errors.push(nome);
      }
    }
    
    setGeneratingAll(false);
    
    if (success > 0 && errors.length === 0) {
      toast.success(`${success} etiqueta(s) gerada(s)`);
    } else if (success > 0 && errors.length > 0) {
      toast.success(`${success} etiqueta(s) gerada(s). ${errors.length} erro(s): ${errors.join(', ')}`);
    } else if (errors.length > 0) {
      toast.error(`Erros: ${errors.join(', ')}`);
    }
    
    if (waiting.length > 0) {
      toast.info(`${waiting.length} aguardando origem`);
    }
  };

  const getProductsDisplay = (pedido: any) => {
    try {
      const prods = JSON.parse(pedido.produto);
      if (Array.isArray(prods)) {
        return prods.map((p: any) => `${p.quantidade}x ${getTagDisplayName(p.produto)}`).join(', ');
      }
    } catch {}
    return `${pedido.quantidade}x ${getTagDisplayName(pedido.produto)}`;
  };

  const filteredPedidos = ufFilter === 'Todos' ? pedidos : pedidos.filter(p => p.uf_postagem === ufFilter);

  if (loading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-4 max-w-full overflow-x-hidden">
      <h1 className="text-2xl font-bold">Logística</h1>

      {/* UF Filter */}
      <div className="flex flex-wrap gap-2">
        {(() => {
          const activeUfsWithoutRegions = estoqueUfs.filter(uf => !ufRegioes.some(r => r.uf === uf));
          const regionCodes = ufRegioes.map(r => r.codigo);
          const allOptions = ['Todos', ...activeUfsWithoutRegions, ...regionCodes];

          return allOptions.map(opt => (
            <Button 
              key={opt} 
              variant={ufFilter === opt ? 'default' : 'outline'} 
              size="sm" 
              onClick={() => setUfFilter(opt)}
              className={ufFilter === opt ? 'bg-sf-green hover:bg-sf-green/90 text-primary-foreground' : ''}
            >
              {opt}
            </Button>
          ));
        })()}
        
        {ufFilter !== 'Todos' && (
          <Button variant="ghost" size="sm" onClick={() => openUfForm(ufFilter)}>
            ⚙️ Editar Remetente {ufFilter}
          </Button>
        )}
      </div>

      {/* Sender form */}
      {selectedUfForm && (
        <Card>
          <CardContent className="p-4 space-y-3">
            <p className="font-bold text-sm">Remetente — {selectedUfForm}</p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <Label className="text-xs">CEP de Origem</Label>
                <Input value={formData.cep_origem || ''} onChange={e => setFormData({ ...formData, cep_origem: e.target.value })} onBlur={handleCepBlur} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">Cidade/Estado</Label>
                <Input value={formData.cidade || ''} readOnly className="min-h-[44px] bg-muted" />
              </div>
              <div>
                <Label className="text-xs">Bairro</Label>
                <Input value={formData.bairro || ''} onChange={e => setFormData({ ...formData, bairro: e.target.value })} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">Endereço</Label>
                <Input value={formData.endereco || ''} onChange={e => setFormData({ ...formData, endereco: e.target.value })} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">Número</Label>
                <Input value={formData.numero || ''} onChange={e => setFormData({ ...formData, numero: e.target.value })} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">Complemento</Label>
                <Input value={formData.complemento || ''} onChange={e => setFormData({ ...formData, complemento: e.target.value })} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">Nome do Remetente</Label>
                <Input value={formData.nome_remetente || ''} onChange={e => setFormData({ ...formData, nome_remetente: e.target.value })} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">Contato do Remetente</Label>
                <Input value={formData.contato_remetente || ''} onChange={e => setFormData({ ...formData, contato_remetente: e.target.value })} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">CPF</Label>
                <Input value={formData.cpf || ''} onChange={e => setFormData({ ...formData, cpf: e.target.value })} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">Descrição do Produto</Label>
                <Input value={formData.descricao_produto || ''} onChange={e => setFormData({ ...formData, descricao_produto: e.target.value })} className="min-h-[44px]" />
              </div>
              <div>
                <Label className="text-xs">Valor Unitário Médio (R$)</Label>
                <Input value={formData.valor_unitario || ''} onChange={e => setFormData({ ...formData, valor_unitario: e.target.value })} className="min-h-[44px]" placeholder="0,00" />
              </div>
            </div>
            <Button onClick={saveRemetente} disabled={saving} className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px]">
              {saving ? 'Salvando...' : 'Salvar Remetente'}
            </Button>
          </CardContent>
        </Card>
      )}

{/* Action button */}
      {(() => {
        const isSF = (p: any) => ((p.gateway_etiqueta || 'superfrete') === 'superfrete');
        const etiquetasGeradasAll = filteredPedidos.filter(p => p.uf_postagem && p.etiqueta_codigo && !p.etiqueta_paga);
        const etiquetasGeradas = etiquetasGeradasAll.filter(isSF);
        const pedidosSemEtiquetaAll = filteredPedidos.filter(p => p.uf_postagem && !p.etiqueta_codigo);
        const pedidosSemEtiqueta = pedidosSemEtiquetaAll.filter(isSF);
        const meSemEtiqueta = pedidosSemEtiquetaAll.length - pedidosSemEtiqueta.length;
        const meGeradas = etiquetasGeradasAll.length - etiquetasGeradas.length;
        const podePagarTodas = etiquetasGeradas.length > 0 && !generatingAll && !payingAll && generatingId === null;
        const totalFreteAPagar = etiquetasGeradas.reduce((sum, p) => sum + (Number(p.etiqueta_valor) || 0), 0);

        return (
          <>
            <div className='flex items-center gap-4'>
              <Button onClick={gerarTudo} disabled={generatingAll || generatingId !== null || payingAll || pedidosSemEtiqueta.length === 0} className='bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px] px-8 font-medium shadow-lg shadow-green-100' title={meSemEtiqueta > 0 ? `${meSemEtiqueta} pedido(s) Melhor Envio serão processados na Fase 2` : ''}>
                {generatingAll ? <><Loader2 className='w-4 h-4 mr-2 animate-spin' /> Gerando...</> : <><Truck className='w-4 h-4 mr-2' /> GERAR TODAS ({pedidosSemEtiqueta.length})</>}
              </Button>

              <Button
                onClick={pagarTodas}
                disabled={!podePagarTodas}
                variant='outline'
                className='min-h-[44px] px-8 font-medium border-amber-500 text-amber-600 hover:bg-amber-50'
                title={etiquetasGeradas.length === 0 ? 'Gere todas as etiquetas para pagar' : (meGeradas > 0 ? `${meGeradas} pedido(s) Melhor Envio serão processados na Fase 2` : '')}
              >
                {payingAll ? <><Loader2 className='w-4 h-4 mr-2 animate-spin' /> Pagando...</> : <><CircleDollarSign className='w-4 h-4 mr-2' /> PAGAR TODAS ({etiquetasGeradas.length})</>}
              </Button>
            </div>

            {/* Métricas discretas - padrão Pedidos */}
            <div className="text-sm">
              <span className="text-muted-foreground">Total: </span>
              <span className="font-bold">{filteredPedidos.length}</span>
              <span className="mx-2 text-muted-foreground">|</span>
              <span className="text-muted-foreground">Frete a pagar: </span>
              <span className="font-medium text-amber-600">
                {formatBRL(totalFreteAPagar)}
              </span>
            </div>
          </>
        );
      })()}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4 -mx-1 sm:mx-0">
        {filteredPedidos.map(p => (
          <Card key={p.id} className={cn('border-2 border-border relative overflow-hidden min-w-0', p.status_pagamento === 'pendente' && 'border-amber-400 border-dashed')}>
            <CardContent className="p-3 sm:p-4 space-y-2 min-w-0">
              <div className="flex justify-between items-start">
                <p className="font-bold text-base">{(p.contatos as any)?.nome || '—'}</p>
                {isAdmin && (
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="ghost" size="icon" className="h-8 w-8">
                        <MoreVertical className="w-4 h-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onClick={() => setMarcarPostadoTarget(p)}>
                        <CheckCircle className="w-4 h-4 mr-2" /> Já Postado
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                )}
              </div>
              <div className="pt-0.5 space-y-0.5">
                <p className="text-sm font-semibold text-foreground">
                  {getProductsDisplay(p)}
                </p>
                {(() => {
                  const c = getCaixaCalculada(p);
                  if (!c.label) return null;
                  return <p className="text-sm text-muted-foreground">Caixa {c.label}</p>;
                })()}
              </div>
              <div className="flex flex-wrap items-center gap-2 text-sm pt-1">
                {/* UF de DESTINO (cliente) */}
                {(() => {
                  const ufDest = getUfDestino(p);
                  return ufDest ? (
                    <Badge className="bg-primary/10 text-primary border-primary/20 text-[10px] font-bold">→ {ufDest}</Badge>
                  ) : null;
                })()}
                <Select 
                  value={p.modalidade} 
                  disabled={!!p.etiqueta_codigo}
                  onValueChange={async (newModalidade) => {
                    const qtd = p.quantidade || 1;
                    const podeMini = newModalidade !== 'mini' || qtd <= 10;
                    
                    if (newModalidade === 'entrega_maos') {
                      await supabase.from('pedidos').update({ modalidade: 'entrega_maos' }).eq('id', p.id);
                      await supabase.from('log_atividades').insert({
                        usuario: profile?.nome || 'Sistema',
                        acao: 'Mudou modalidade para Entrega em Mãos',
                        tabela_afetada: 'pedidos',
                        registro_id: p.id,
                      });
                      toast.success('Pedido movido para Entrega em Mãos');
                      setPedidos(prev => prev.filter(ped => ped.id !== p.id));
                    } else {
                      await supabase.from('pedidos').update({ modalidade: newModalidade }).eq('id', p.id);
                      setPedidos(prev => prev.map(ped => ped.id === p.id ? { ...ped, modalidade: newModalidade } : ped));
                      
                      if (!podeMini) {
                        toast.warning(`Quantidade ${qtd} não cabe em MINI. Etiqueta será gerada com alerta.`);
                      }
                      
                      const novoValor = await cotarFrete({ ...p, modalidade: newModalidade });
                      if (novoValor) {
                        setFretesCotados(prev => ({ ...prev, [p.id]: novoValor }));
                        setPedidos(prev => prev.map(ped => ped.id === p.id ? { ...ped, etiqueta_valor: ped.etiqueta_url ? novoValor : ped.etiqueta_valor } : ped));
                      }
                    }
                  }}
                >
                  <SelectTrigger className="h-6 text-[10px] py-0 px-2 w-auto font-bold">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="mini">MINI</SelectItem>
                    <SelectItem value="pac">PAC</SelectItem>
                    <SelectItem value="sedex">SEDEX</SelectItem>
                    <SelectItem value="entrega_maos">Entrega em Mãos</SelectItem>
                  </SelectContent>
                </Select>
                {getFreteDisplayValue(p) && (
                  <strong className="text-foreground text-[12px]">
                    {formatBRL(Number(getFreteDisplayValue(p)))}
                  </strong>
                )}
                {miniExcedeu(p) && (
                  <Badge variant="destructive" className="text-[10px] bg-amber-500 hover:bg-amber-600">
                    ⚠️ Trocar Modalidade
                  </Badge>
                )}
              </div>

              {!p.uf_postagem ? (
                <div className="space-y-2">
                  <Label className="text-xs">Origem:</Label>
                  <div className="flex flex-col gap-2">
                    <Select onValueChange={v => {
                      const hasRegions = ufRegioes.some(r => r.uf === v);
                      if (!hasRegions) updatePedidoUf(p.id, v);
                      else {
                        // Apenas sinaliza que escolheu a UF, mas falta a região
                        // O dropdown de região aparecerá abaixo
                        setPedidos(prev => prev.map(ped => ped.id === p.id ? { ...ped, temp_uf: v } : ped));
                      }
                    }}>
                      <SelectTrigger className="min-h-[44px]"><SelectValue placeholder="Selecionar UF" /></SelectTrigger>
                      <SelectContent>
                        {estoqueUfs.map(uf => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}
                      </SelectContent>
                    </Select>

                    {(p.temp_uf || (p.uf_postagem && ufRegioes.some(r => r.uf === p.uf_postagem.replace(/[0-9]/g, '')))) && (
                      <Select onValueChange={v => updatePedidoUf(p.id, v)}>
                        <SelectTrigger className="min-h-[44px] border-blue-300"><SelectValue placeholder="Selecionar Região" /></SelectTrigger>
                        <SelectContent>
                          {ufRegioes
                            .filter(r => r.uf === (p.temp_uf || p.uf_postagem?.replace(/[0-9]/g, '')))
                            .map(r => <SelectItem key={r.codigo} value={r.codigo}>{r.codigo} ({r.tag})</SelectItem>)
                          }
                        </SelectContent>
                      </Select>
                    )}
                  </div>
                </div>
              ) : isAdmin ? (
                <div className="space-y-2">
                  <Label className="text-xs">UF Postagem/Região:</Label>
                  {temEtiqueta(p) ? (
                    <div className="flex items-center gap-2">
                      <Badge className="bg-primary/10 text-primary border-primary/20 text-[11px] font-bold">{p.uf_postagem}</Badge>
                    </div>
                  ) : (
                    <div className="flex flex-col gap-2">
                      <Select value={p.uf_postagem.replace(/[0-9]/g, '')} onValueChange={v => {
                        const hasRegions = ufRegioes.some(r => r.uf === v);
                        if (!hasRegions) updatePedidoUf(p.id, v);
                        else {
                          setPedidos(prev => prev.map(ped => ped.id === p.id ? { ...ped, temp_uf: v } : ped));
                        }
                      }}>
                        <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {estoqueUfs.map(uf => <SelectItem key={uf} value={uf}>{uf}</SelectItem>)}
                        </SelectContent>
                      </Select>

                      {ufRegioes.some(r => r.uf === (p.temp_uf || p.uf_postagem.replace(/[0-9]/g, ''))) && (
                        <Select value={p.temp_uf ? undefined : p.uf_postagem} onValueChange={v => updatePedidoUf(p.id, v)}>
                          <SelectTrigger className="min-h-[44px] border-blue-300"><SelectValue placeholder="Mudar Região" /></SelectTrigger>
                          <SelectContent>
                            {ufRegioes
                              .filter(r => r.uf === (p.temp_uf || p.uf_postagem.replace(/[0-9]/g, '')))
                              .map(r => <SelectItem key={r.codigo} value={r.codigo}>{r.codigo} ({r.tag})</SelectItem>)
                            }
                          </SelectContent>
                        </Select>
                      )}
                    </div>
                  )}
                </div>
              ) : null}

{(() => {
                const gatewayAtual = (p as any).gateway_etiqueta || 'superfrete';
                const ambosConectados = gatewaysConectados.superfrete && gatewaysConectados.melhorenvio;
                const algumConectado = gatewaysConectados.superfrete || gatewaysConectados.melhorenvio;
                const gatewayEfetivo = !ambosConectados && algumConectado
                  ? (gatewaysConectados.superfrete ? 'superfrete' : 'melhorenvio')
                  : gatewayAtual;
                const isMelhorEnvio = gatewayEfetivo === 'melhorenvio';
                const podeGerar = !!p.uf_postagem && gatewayEfetivo === 'superfrete' && gatewaysConectados.superfrete;
                const showGatewayDropdown = algumConectado && !isEtiquetaPaga(p);
                const dropdownLocked = temEtiqueta(p) || !ambosConectados || updatingGateway === p.id;
                return (
                  <div className="flex items-center gap-2 pt-1">
                    {showGatewayDropdown && (
                      <Select
                        value={gatewayEfetivo}
                        onValueChange={(v) => updatePedidoGateway(p.id, v)}
                        disabled={dropdownLocked}
                      >
                        <SelectTrigger className="h-8 w-[68px] text-xs px-2 mr-auto" title={temEtiqueta(p) ? 'Gateway travado: etiqueta já gerada' : (!ambosConectados ? 'Único gateway conectado' : 'Trocar gateway')}>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {gatewaysConectados.superfrete && <SelectItem value="superfrete">SF</SelectItem>}
                          {gatewaysConectados.melhorenvio && <SelectItem value="melhorenvio">ME</SelectItem>}
                        </SelectContent>
                      </Select>
                    )}
                    {!showGatewayDropdown && <div className="mr-auto" />}

                    {/* Estado: ETIQUETA PAGA */}
                    {isEtiquetaPaga(p) ? (
                      <>
                        <Button
                          size="icon"
                          className="min-h-[44px] w-10 bg-sf-green hover:bg-sf-green/90"
                          disabled={printingId === p.id}
                          onClick={() => imprimirEtiqueta(p)}
                          title="Imprimir"
                        >
                          {printingId === p.id ? <Loader2 className="w-4 h-4 animate-spin" /> : <Printer className="w-4 h-4" />}
                        </Button>
                        <Button size="icon" variant="outline" className="min-h-[44px] w-10 border-destructive text-destructive hover:bg-destructive/10" onClick={() => setDeleteEtiquetaTarget(p)} title="Cancelar Etiqueta">
                          <XCircle className="w-4 h-4" />
                        </Button>
                      </>
                    ) : temEtiqueta(p) ? (
                      <>
                        <Button
                          size="icon"
                          variant="outline"
                          className="min-h-[44px] w-10 text-destructive border-destructive hover:bg-destructive/10"
                          disabled={deletingEtiqueta}
                          onClick={() => setDeleteEtiquetaTarget(p)}
                          title="Cancelar"
                        >
                          <XCircle className="w-4 h-4" />
                        </Button>
                        <Button
                          size="sm"
                          className="min-h-[44px] bg-green-600 hover:bg-green-700 text-primary-foreground"
                          disabled={payingId === p.id}
                          onClick={() => pagarEtiqueta(p)}
                        >
                          {payingId === p.id ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <CircleDollarSign className="w-4 h-4 mr-1" />}
                          Pagar
                        </Button>
                      </>
                    ) : (
                      <Button
                        size="sm"
                        className="min-h-[44px]"
                        disabled={!podeGerar || generatingId === p.id || payingId !== null}
                        onClick={() => gerarEtiqueta(p)}
                        variant={podeGerar ? "default" : "secondary"}
                        title={isMelhorEnvio ? 'Integração Melhor Envio em breve' : (!p.uf_postagem ? 'Selecione UF de postagem' : '')}
                      >
                        {generatingId === p.id ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : !podeGerar ? <Lock className="w-4 h-4 mr-1" /> : <Printer className="w-4 h-4 mr-1" />}
                        Gerar
                      </Button>
                    )}
                  </div>
                );
              })()}
            </CardContent>
          </Card>
        ))}
        {filteredPedidos.length === 0 && <p className="text-muted-foreground col-span-full text-center py-8">Nenhum pedido aguardando postagem</p>}
      </div>

      {/* Delete etiqueta confirmation */}
      <AlertDialog open={!!deleteEtiquetaTarget} onOpenChange={() => setDeleteEtiquetaTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir etiqueta</AlertDialogTitle>
            <AlertDialogDescription>
              Excluir etiqueta de {(deleteEtiquetaTarget?.contatos as any)?.nome}? Esta ação cancelará o envio no Super Frete.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteEtiqueta} disabled={deletingEtiqueta} className="bg-destructive text-destructive-foreground">
              {deletingEtiqueta ? 'Excluindo...' : 'Excluir'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Marcar postado confirmation */}
      <AlertDialog open={!!marcarPostadoTarget} onOpenChange={() => setMarcarPostadoTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Marcar como postado?</AlertDialogTitle>
            <AlertDialogDescription>
              Confirmar que o pedido de {(marcarPostadoTarget?.contatos as any)?.nome} já foi postado?
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleMarcarPostado} disabled={markingPostado} className="bg-sf-green">
              {markingPostado ? 'Processando...' : 'Confirmar'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

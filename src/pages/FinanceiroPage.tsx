import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Skeleton } from '@/components/ui/skeleton';
import { Separator } from '@/components/ui/separator';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { formatBRL, formatDateShort } from '@/lib/format';
import { Plus, Pencil, Trash2, ChevronLeft, ChevronRight, Check, Loader2, Copy } from 'lucide-react';
import { getProductDisplayName } from '@/lib/productDisplayNames';
import { cn, copyToClipboard } from '@/lib/utils';
import { useIsMobile } from '@/hooks/use-mobile';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { Badge } from '@/components/ui/badge';
import { useIsAdmin } from '@/hooks/useIsAdmin';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { ChevronDown } from 'lucide-react';

const UF_OPTIONS = [
  'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
  'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SE','SP','TO'
];

// Ocultação visual: lista mostra apenas lançamentos recentes.
// NÃO afeta saldos dos sócios (calculados via query separada SEM filtro de data).
const DIAS_OCULTACAO_FIN = 180;
const getDataLimiteFin = () =>
  new Date(Date.now() - DIAS_OCULTACAO_FIN * 86400000).toISOString().slice(0, 10);

export default function FinanceiroPage() {
  const { user, profile } = useAuth();
  const isAdmin = useIsAdmin();
  const isMobile = useIsMobile();
  const [loading, setLoading] = useState(true);
  const [socioBalances, setSocioBalances] = useState<Record<string, number>>({});
  const [socioV, setSocioV] = useState(0);
  const [socioA, setSocioA] = useState(0);
  const [socioVLabel, setSocioVLabel] = useState('V');
  const [socioALabel, setSocioALabel] = useState('A');
  const [lancamentos, setLancamentos] = useState<any[]>([]);
  const [page, setPage] = useState(1);
  const [showLucro, setShowLucro] = useState(false);
  const [socioLabels, setSocioLabels] = useState<Record<string, string>>({});
  const [mySocioKey, setMySocioKey] = useState<string>('V');

  const [lucroValue, setLucroValue] = useState('');
  const [lucroError, setLucroError] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [editItem, setEditItem] = useState<any>(null);
  const [deleteTarget, setDeleteTarget] = useState<any>(null);
  const [detailItem, setDetailItem] = useState<any>(null);
  const [selectSocioTarget, setSelectSocioTarget] = useState<any>(null);
  const [detailPedido, setDetailPedido] = useState<any>(null);
  const [fetchingPedido, setFetchingPedido] = useState(false);

  // Form state
  const [formTipo, setFormTipo] = useState('VENDA');
  const [formSocio, setFormSocio] = useState('V');
  const [formCanal, setFormCanal] = useState('ADS');
  const [formValor, setFormValor] = useState('');
  const [formDescricao, setFormDescricao] = useState('');
  const [formContactSearch, setFormContactSearch] = useState('');
  const [formContacts, setFormContacts] = useState<any[]>([]);
  const [formSelectedContact, setFormSelectedContact] = useState<any>(null);
  const [formNewContact, setFormNewContact] = useState(false);
  const [formNewNome, setFormNewNome] = useState('');
  const [formNewTelefone, setFormNewTelefone] = useState('');
  const [formNewEndereco, setFormNewEndereco] = useState('');
  const [formNewNumero, setFormNewNumero] = useState('');
  const [searchTimeout, setSearchTimeout] = useState<ReturnType<typeof setTimeout> | null>(null);
  const [formNewComplemento, setFormNewComplemento] = useState('');
  const [formNewBairro, setFormNewBairro] = useState('');
  const [formNewCpf, setFormNewCpf] = useState('');
  const [formNewCidade, setFormNewCidade] = useState('');
  const [formNewUf, setFormNewUf] = useState('');
  const [formNewCep, setFormNewCep] = useState('');
  const [clientSaved, setClientSaved] = useState(false);
  const [cepLoading, setCepLoading] = useState(false);
  
  const [phoneDuplicate, setPhoneDuplicate] = useState<any>(null);
  const [allREPs, setAllREPs] = useState<any[]>([]);
  const [formRepresentanteId, setFormRepresentanteId] = useState<string | null>(null);
  const [allInstancias, setAllInstancias] = useState<{ id: string; nome: string }[]>([]);
  const [formInstanciaId, setFormInstanciaId] = useState<string | null>(null);
  const [instanciaLocked, setInstanciaLocked] = useState(false);
  const [formProdutos, setFormProdutos] = useState<{ produto_id: string; quantidade: number }[]>([{ produto_id: '', quantidade: 1 }]);
  const [allProdutos, setAllProdutos] = useState<any[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [formModalidade, setFormModalidade] = useState('mini');
  const [formUfPostagem, setFormUfPostagem] = useState('');
  const [formObs, setFormObs] = useState('');
  const [formStatusPagamento, setFormStatusPagamento] = useState<'pago' | 'pendente'>('pago');

  // Transfer state
  const [showTransfer, setShowTransfer] = useState(false);
  const [transferFrom, setTransferFrom] = useState('');
  const [transferTo, setTransferTo] = useState('');
  const [transferValue, setTransferValue] = useState('');
  const [socios, setSocios] = useState<{ key: string; nome: string; user_id: string | null }[]>([]);
  const [caixas, setCaixas] = useState<{ codigo: string; apelido: string }[]>([]);
  const [showAddCaixa, setShowAddCaixa] = useState(false);
  const [novaCaixaApelido, setNovaCaixaApelido] = useState('');
  const [savingCaixa, setSavingCaixa] = useState(false);
  const [ufsCadastradas, setUfsCadastradas] = useState<string[]>([]);

  const PER_PAGE = 50;

  // Resolve "criado_por" (que pode ser apelido, email, ou letra do sócio) para o nome de exibição.
  const resolveCriadoPor = (raw: any): string => {
    if (!raw || raw === '-') return '—';
    const s = String(raw).trim();
    // Match direto por socio_key (ex: 'V', 'A')
    if (socioLabels[s]) return socioLabels[s];
    if (socioLabels[s.toUpperCase()]) return socioLabels[s.toUpperCase()];
    // Match por email: procura sócio cujo apelido bate com prefixo do email
    const emailPrefix = s.includes('@') ? s.split('@')[0].toLowerCase() : null;
    if (emailPrefix) {
      const found = socios.find(so => so.nome?.toLowerCase() === emailPrefix);
      if (found) return found.nome;
      // Fallback: primeira letra do email
      const firstChar = emailPrefix.charAt(0).toUpperCase();
      if (socioLabels[firstChar]) return socioLabels[firstChar];
    }
    // Já é o apelido completo
    return s;
  };

  useEffect(() => { fetchAll(); }, []);

  const fetchAll = async () => {
    try {
    setLoading(true);

    const dataLimiteFin = getDataLimiteFin();

    const [lancsResult, lancsSaldoResult, prodsResult, repsResult, perfisResult, sociosResult, ufsResult, instanciasResult, caixasResult] = await Promise.all([
      // LISTA visual: filtrada pelos últimos 180 dias (com joins pesados para exibição)
      supabase.from('lancamentos_socios')
        .select('*, produtos(nome_oficial), contatos(id, nome, telefone, canal_origem, tag_kanban, endereco, complemento, bairro, cidade_uf, cidade, uf, cep, cpf, observacao, created_at)')
        .gte('data', dataLimiteFin)
        .order('created_at', { ascending: false }),
      // SALDOS: query LEVE SEM filtro de data — base completa para saldos reais
      supabase.from('lancamentos_socios')
        .select('socio, tipo, valor'),
      supabase.from('produtos').select('*, produtos_grupos(nome)').eq('ativo', true),
      supabase.from('contatos').select('id, nome').eq('canal_atual', 'REP').order('nome'),
      supabase.from('perfis_usuario').select('user_id, nome, socio_key').not('socio_key', 'is', null),
      supabase.from('perfis_usuario').select('user_id, nome, socio_key').not('socio_key', 'is', null).order('nome'),
      supabase.from('estoque_ufs' as any).select('uf').order('uf'),
      supabase.from('instancias').select('id, nome, ativo').eq('ativo', true).order('nome'),
      supabase.rpc('listar_caixas' as any),
    ]);

    const caixasList = ((caixasResult.data || []) as any[])
      .map((c: any) => ({ codigo: c.codigo, apelido: c.apelido }));
    setCaixas(caixasList);

    setUfsCadastradas(((ufsResult.data || []) as any[]).map((r: any) => r.uf).filter(Boolean));
    setAllInstancias(
      ((instanciasResult.data || []) as any[])
        .filter((i: any) => i.nome !== 'Instancia ADMIN')
        .map((i: any) => ({ id: i.id, nome: i.nome }))
    );

    // Build socio labels map: 'V' -> apelido, 'A' -> apelido
    const labels: Record<string, string> = {};
    let myKey = 'V';
    (perfisResult.data || []).forEach((p: any) => {
      if (p.socio_key) labels[p.socio_key] = p.nome || p.socio_key;
      if (p.user_id === user?.id) myKey = p.socio_key;
    });
    if (!labels['V']) labels['V'] = 'V';
    if (!labels['A']) labels['A'] = 'A';
    // adiciona caixas no mapa de labels pra coluna Sócio das movimentações
    // mostrar apelido em vez de 'C1', 'C2'...
    caixasList.forEach((c: { codigo: string; apelido: string }) => {
      labels[c.codigo] = `🏪 ${c.apelido}`;
    });

    // Dynamic socios list (max 6)
    const dynamicSocios = (sociosResult.data || [])
      .slice(0, 6)
      .map((s: any) => ({ key: s.socio_key || s.nome?.charAt(0).toUpperCase() || '?', nome: s.nome, user_id: s.user_id }));
    if (dynamicSocios.length === 0) {
      dynamicSocios.push({ key: 'V', nome: labels['V'], user_id: null });
      dynamicSocios.push({ key: 'A', nome: labels['A'], user_id: null });
    }
    setSocios(dynamicSocios);
    setSocioLabels(labels);
    setSocioVLabel(labels['V']);
    setSocioALabel(labels['A']);
    setMySocioKey(myKey);
    // Define o sócio do formulário como o sócio do usuário logado (default)
    setFormSocio(prev => (prev && dynamicSocios.some(s => s.key === prev) ? prev : myKey));

    const allLancs = lancsResult.data || [];
    const allLancsSaldo = lancsSaldoResult.data || []; // base completa para saldos
    
    // Calculate balances: sum ALL lancamentos per socio (incluindo CAPITAL_INICIAL e antigos >180d)
    // CRÍTICO: usa allLancsSaldo (sem filtro de data) para preservar saldo histórico real
    const balances: Record<string, number> = {};
    allLancsSaldo.forEach((l: any) => {
      if (l.socio) {
        balances[l.socio] = (balances[l.socio] || 0) + Number(l.valor);
      }
    });

    setSocioBalances(balances);

    // Balances come 100% from database (including CAPITAL_INICIAL entries)
    // Usa allLancsSaldo (sem filtro de data) para garantir saldo histórico real
    const initialBalances: Record<string, number> = {};
    dynamicSocios.forEach(s => { initialBalances[s.key] = 0; });
    allLancsSaldo.filter((l: any) => l.tipo === 'CAPITAL_INICIAL').forEach((l: any) => {
      if (l.socio) initialBalances[l.socio] = (initialBalances[l.socio] || 0) + Number(l.valor);
    });

    // Set card balances from full sum
    dynamicSocios.forEach(s => { initialBalances[s.key] = balances[s.key] || 0; });
    setSocioV(balances['V'] || 0);
    setSocioA(balances['A'] || 0);
    
    // Agrupa transferências e lucros: 2 linhas viram 1
    // Pareamento estrito por: tipo + valor absoluto idêntico + sócios opostos + created_at mais próximo
    const grouped: any[] = [];
    const usedIds = new Set<string>();
    for (const l of allLancs) {
      if (usedIds.has(l.id)) continue;
      if (l.tipo === 'TRANSFERENCIA') {
        const candidates = allLancs.filter((p: any) =>
          !usedIds.has(p.id) && p.id !== l.id &&
          p.tipo === 'TRANSFERENCIA' &&
          p.socio !== l.socio &&
          Math.abs(Number(p.valor)) === Math.abs(Number(l.valor)) &&
          Math.sign(Number(p.valor)) !== Math.sign(Number(l.valor)) &&
          (
            (p.transferencia_direcao && l.transferencia_direcao && p.transferencia_direcao === l.transferencia_direcao) ||
            p.descricao === l.descricao
          )
        );
        const pair = candidates.sort((a: any, b: any) => {
          const da = Math.abs(new Date(a.created_at).getTime() - new Date(l.created_at).getTime());
          const db = Math.abs(new Date(b.created_at).getTime() - new Date(l.created_at).getTime());
          return da - db;
        })[0];
        if (pair) {
          const positive = Number(l.valor) > 0 ? l : pair;
          const direcao = l.transferencia_direcao || pair.transferencia_direcao || `${l.socio}→${pair.socio}`;
          grouped.push({
            ...positive,
            tipo: 'TRANSFERENCIA',
            transferencia_direcao: direcao,
            _isGroupedTransferencia: true,
            _transferValor: formatBRL(Math.abs(Number(l.valor))),
            _pairedIds: [l.id, pair.id],
          });
          usedIds.add(l.id);
          usedIds.add(pair.id);
        } else {
          const direcao = l.transferencia_direcao || '';
          grouped.push({
            ...l,
            tipo: 'TRANSFERENCIA',
            transferencia_direcao: direcao,
            _transferValor: formatBRL(Math.abs(Number(l.valor))),
          });
          usedIds.add(l.id);
        }
      } else if (l.tipo === 'LUCRO') {
        const candidates = allLancs.filter((p: any) =>
          !usedIds.has(p.id) && p.id !== l.id &&
          p.tipo === 'LUCRO' &&
          p.descricao === l.descricao &&
          p.socio !== l.socio &&
          Math.abs(Number(p.valor)) === Math.abs(Number(l.valor))
        );
        const pair = candidates.sort((a: any, b: any) => {
          const da = Math.abs(new Date(a.created_at).getTime() - new Date(l.created_at).getTime());
          const db = Math.abs(new Date(b.created_at).getTime() - new Date(l.created_at).getTime());
          return da - db;
        })[0];
        if (pair) {
          const lucroDirecao = labels[l.criado_por] || l.criado_por || '';
          grouped.push({
            ...l,
            tipo: 'LUCRO',
            transferencia_direcao: lucroDirecao,
            _isGroupedLucro: true,
            _lucroSocios: [l.socio, pair.socio],
            _pairedIds: [l.id, pair.id],
          });
          usedIds.add(l.id);
          usedIds.add(pair.id);
        } else {
          grouped.push(l);
          usedIds.add(l.id);
        }
      } else {
        grouped.push(l);
        usedIds.add(l.id);
      }
    }
    setLancamentos(grouped);

    setAllProdutos(prodsResult.data || []);
    setAllREPs(repsResult.data || []);
    } catch (err) {
      console.error('fetchAll error:', err);
    } finally {
      setLoading(false);
    }
  };

  const fetchPedidoDetail = async (id: string) => {
    if (!id) return;
    setFetchingPedido(true);
    try {
      const { data, error } = await supabase.from('pedidos')
        .select('*, contatos(nome, telefone, tag_kanban, cpf, endereco, complemento, bairro, cidade_uf, cep)')
        .eq('id', id)
        .single();
      if (error) throw error;
      setDetailPedido(data);
    } catch (err: any) {
      toast.error('Erro ao buscar detalhes do pedido');
    } finally {
      setFetchingPedido(false);
    }
  };

  const checkPhoneDuplicate = async (phone: string) => {
    setFormNewTelefone(phone);
    setPhoneDuplicate(null);
    if (phone.length < 8) return;
    const { data } = await supabase.from('contatos').select('id, nome, telefone').eq('telefone', phone).limit(1);
    if (data && data.length > 0) setPhoneDuplicate(data[0]);
  };

  const applyPhoneMask = (val: string) => {
    const num = val.replace(/\D/g, '');
    if (!num) return '';
    if (num.length <= 2) return `(${num}`;
    if (num.length <= 7) return `(${num.slice(0, 2)}) ${num.slice(2)}`;
    return `(${num.slice(0, 2)}) ${num.slice(2, 7)}-${num.slice(7, 11)}`;
  };

  const applyCepMask = (val: string) => {
    const num = val.replace(/\D/g, '');
    if (!num) return '';
    if (num.length <= 5) return num;
    return `${num.slice(0, 5)}-${num.slice(5, 8)}`;
  };

  const lookupCep = async (cepRaw: string) => {
    const num = cepRaw.replace(/\D/g, '');
    if (num.length !== 8) return;
    setCepLoading(true);
    try {
      const res = await fetch(`https://viacep.com.br/ws/${num}/json/`);
      const data = await res.json();
      if (!data.erro) {
        if (data.logradouro) setFormNewEndereco(data.logradouro);
        if (data.bairro) setFormNewBairro(data.bairro);
        if (data.localidade) setFormNewCidade(data.localidade);
        if (data.uf) setFormNewUf(data.uf);
      }
    } catch {
      // CEP not found, ignore
    } finally {
      setCepLoading(false);
    }
  };

  const searchContacts = async (val: string) => {
    setFormContactSearch(val);
    if (searchTimeout) clearTimeout(searchTimeout);
    if (val.length < 2) { setFormContacts([]); return; }
    const currentCanal = formCanal;
    const timeout = setTimeout(async () => {
      const { data } = await supabase.from('contatos')
        .select('id, nome, telefone, representante_id, cpf, cidade, uf, cep, endereco, complemento, bairro, canal_origem, canal_atual, instancia_id')
        .eq('canal_atual', currentCanal)
        .or(`nome.ilike.%${val}%,telefone.ilike.%${val}%,cpf.ilike.%${val}%`)
        .limit(10);
      setFormContacts(data || []);
    }, 300);
    setSearchTimeout(timeout);
  };

  const selectExistingContact = (c: any) => {
    setFormSelectedContact(c);
    if (c.representante_id) {
      setFormRepresentanteId(c.representante_id);
    }
    // Se contato já tem instância, trava o dropdown. Senão, deixa escolher.
    if (c.instancia_id) {
      setFormInstanciaId(c.instancia_id);
      setInstanciaLocked(true);
    } else {
      setFormInstanciaId(null);
      setInstanciaLocked(false);
    }
    setFormContacts([]);
    setFormContactSearch('');
    setClientSaved(true);
    setFormNewContact(false);
    setFormNewNome(c.nome || '');
    setFormNewTelefone(c.telefone || '');
    setFormNewCpf(c.cpf || '');
    setFormNewEndereco(c.endereco || '');
    setFormNewComplemento(c.complemento || '');
    setFormNewBairro(c.bairro || '');
    setFormNewCidade(c.cidade || '');
    setFormNewUf(c.uf || '');
    setFormNewCep(c.cep || '');
  };

  const handleSaveClient = () => {
    if (!formNewNome.trim()) { toast.error('Nome é obrigatório'); return; }
    setClientSaved(true);
    setFormNewContact(false);
  };

  const handleEditClient = () => {
    setClientSaved(false);
    setFormNewContact(true);
  };

  const handleRealizarLucro = async () => {
    try {
      const val = parseFloat(lucroValue.replace(',', '.'));
      setLucroError('');

      if (socios.length < 2) {
        setLucroError('É necessário pelo menos 2 sócios');
        return;
      }

      // Check all socios have same sign
      const allSocioBalances = socios.map(s => socioBalances[s.key] ?? 0);
      const allPositive = allSocioBalances.every(b => b >= 0);
      const allNegative = allSocioBalances.every(b => b < 0);

      if (!allPositive && !allNegative) {
        setLucroError('Todos os sócios devem ter o mesmo sinal (todos + ou todos -)');
        return;
      }

      // Max value = smallest balance among all socios
      const maxVal = Math.min(...allSocioBalances.map(Math.abs));

      if (val > maxVal) {
        setLucroError(`Valor máximo permitido: ${formatBRL(maxVal)}`);
        return;
      }

      const adminLabel =
        socioLabels[profile?.socio_key || ''] ||
        profile?.socio_key ||
        profile?.nome ||
        user?.email?.split('@')[0] ||
        'sistema';
      const timestamp = new Date().toISOString();
      const socioNames = socios.map(s => s.nome).join('/');

      // Sinal depende do cenário:
      // - Todos POSITIVOS → lucro sai da empresa pros sócios: lançamento -val
      //   (saldo do sócio diminui, ele "sacou" o lucro).
      // - Todos NEGATIVOS → realizar lucro ABATE a dívida: lançamento +val
      //   (aproxima o saldo de zero). maxVal = menor |saldo| garante que
      //   ninguém passa de zero — é o limite máximo de abatimento.
      const sinal = allNegative ? 1 : -1;
      const inserts = socios.map(s => ({
        socio: s.key,
        tipo: 'LUCRO' as const,
        valor: sinal * val,
        descricao: allNegative
          ? `Abate de saldo: ${socioNames} +${formatBRL(val)}`
          : `Lucro: ${socioNames} -${formatBRL(val)}`,
        realizado: true,
        realizado_em: timestamp,
        snapshot_saldo_v: socioBalances['V'] ?? 0,
        snapshot_saldo_a: socioBalances['A'] ?? 0,
        status_pagamento: '-',
        criado_por: adminLabel,
      }));

      const { error } = await supabase.from('lancamentos_socios').insert(inserts);
      if (error) throw error;

      toast.success('Lucro realizado!');
      setShowLucro(false);
      setLucroValue('');
      setLucroError('');
      fetchAll();
    } catch (err: any) {
      console.error('Lucro error:', err);
      toast.error('Erro ao realizar lucro: ' + (err.message || 'Erro desconhecido'));
    }
  };

  const handleTransfer = async () => {
    try {
      const val = parseFloat(transferValue.replace(',', '.'));
      if (!val || val <= 0) { toast.error('Valor deve ser positivo'); return; }
      if (!transferFrom || !transferTo) { toast.error('Selecione origem e destino'); return; }
      if (transferFrom === transferTo) { toast.error('Origem e destino devem ser diferentes'); return; }

      const adminLabel =
        socioLabels[profile?.socio_key || ''] ||
        profile?.socio_key ||
        profile?.nome ||
        user?.email?.split('@')[0] ||
        'sistema';
      // Origem/destino podem ser sócio OU caixa (ex: DeFlow) — resolve o label
      // nos dois mapas (antes só olhava socios → caixa virava "undefined→A").
      const resolveLabel = (key: string) =>
        socios.find(s => s.key === key)?.nome
        || caixas.find(c => c.codigo === key)?.apelido
        || key;
      const direction = `${resolveLabel(transferFrom)}→${resolveLabel(transferTo)}`;

      // Negative for sender
      const { error: errorFrom } = await supabase.from('lancamentos_socios').insert({
        socio: transferFrom,
        tipo: 'TRANSFERENCIA' as any,
        valor: -val,
        descricao: `Transferência ${direction}`,
        status_pagamento: '-',
        criado_por: adminLabel,
        transferencia_direcao: direction,
        snapshot_saldo_v: socioBalances['V'] ?? 0,
        snapshot_saldo_a: socioBalances['A'] ?? 0,
      });
      if (errorFrom) throw errorFrom;

      // Positive for receiver
      const { error: errorTo } = await supabase.from('lancamentos_socios').insert({
        socio: transferTo,
        tipo: 'TRANSFERENCIA' as any,
        valor: val,
        descricao: `Transferência ${direction}`,
        status_pagamento: '-',
        criado_por: adminLabel,
        transferencia_direcao: direction,
        snapshot_saldo_v: socioBalances['V'] ?? 0,
        snapshot_saldo_a: socioBalances['A'] ?? 0,
      });
      if (errorTo) throw errorTo;

      toast.success('Transferência realizada!');
      setShowTransfer(false);
      setTransferValue('');
      setTransferFrom('');
      setTransferTo('');
      fetchAll();
    } catch (err: any) {
      console.error('Transfer error:', err);
      toast.error('Erro ao transferir: ' + (err.message || 'Erro desconhecido'));
    }
  };

  const handleSubmitForm = async () => {
    console.log('=== SUBMIT START ===', { formTipo, formValor, formNewContact, clientSaved, formSelectedContact: formSelectedContact?.id, formNewNome });
    const valor = parseFloat(formValor.replace(',', '.'));
    if (!valor || isNaN(valor)) { toast.error('Valor inválido'); return; }

    if (formTipo === 'VENDA' && formCanal === 'C-REP' && formNewContact && !formRepresentanteId) {
      toast.error('Selecione um REPRESENTANTE para cliente C-REP');
      return;
    }

    setSubmitting(true);

    const submitAbort = new AbortController();
    const timeoutId = setTimeout(() => {
      console.error('SUBMIT TIMEOUT - Forçando reset');
      submitAbort.abort();
      setSubmitting(false);
      toast.error('Tempo limite excedido. Tente novamente.');
    }, 30000);

    try {
      if (formTipo === 'VENDA') {
        let contatoId: string | null = formSelectedContact?.id || null;

        const precisaCriarContato = formNewContact || (clientSaved && !formSelectedContact);

        if (precisaCriarContato) {
          if (!formNewNome.trim()) {
            toast.error('Nome do cliente é obrigatório!');
            clearTimeout(timeoutId);
            setSubmitting(false);
            return;
          }

          const enderecoFull = [formNewEndereco, formNewNumero].filter(Boolean).join(', ');
          const cidadeUfString = [formNewCidade, formNewUf].filter(Boolean).join('/');

          // Se tem telefone e ainda nao tem contatoId, verifica se ja existe
          if (formNewTelefone && !contatoId) {
            const { data: dup } = await supabase.from('contatos').select('id, nome, representante_id').eq('telefone', formNewTelefone).maybeSingle();
            if (dup) {
              if (formCanal === 'C-REP' && dup.representante_id && dup.representante_id !== formRepresentanteId) {
                toast.error('Este cliente já está atribuído a outro representante. Altere na aba Contatos.');
                clearTimeout(timeoutId);
                setSubmitting(false);
                return;
              }
              contatoId = dup.id;
            }
          }

          // Se ainda nao tem contatoId, cria novo contato via RPC (bypass PostgREST)
          if (!contatoId) {
            const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
            const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
            const { data: sessionData } = await supabase.auth.getSession();
            const accessToken = sessionData?.session?.access_token || SUPABASE_KEY;

            const contatoBody = {
              p_nome: formNewNome.trim(),
              p_canal_origem: formCanal,
              p_telefone: formNewTelefone || null,
              p_cpf: formNewCpf || null,
              p_endereco: enderecoFull || null,
              p_complemento: formNewComplemento || null,
              p_bairro: formNewBairro || null,
              p_cidade_uf: cidadeUfString || null,
              p_cep: formNewCep || null,
              p_cidade: formNewCidade || null,
              p_uf: formNewUf || null,
              p_representante_id: formCanal === 'C-REP' ? formRepresentanteId : null,
              p_instancia_id: formInstanciaId,
            };

            console.log('FINANCEIRO: create_contato RPC body:', contatoBody);

            const contatoResponse = await fetch(`${SUPABASE_URL}/rest/v1/rpc/create_contato`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'apikey': SUPABASE_KEY,
                'Authorization': `Bearer ${accessToken}`,
                'Prefer': 'return=representation',
              },
              body: JSON.stringify(contatoBody),
              signal: submitAbort.signal,
            });

            if (!contatoResponse.ok) {
              const errorText = await contatoResponse.text();
              console.error('FINANCEIRO: create_contato error:', errorText);
              toast.error('Erro ao criar contato: ' + errorText);
              clearTimeout(timeoutId);
              setSubmitting(false);
              return;
            }

            const createdData = await contatoResponse.json();
            contatoId = typeof createdData === 'object' && createdData?.id ? createdData.id : createdData;
            console.log('FINANCEIRO: Contact created via RPC:', contatoId);
          }
        }

        if (!contatoId || typeof contatoId !== 'string') {
          toast.error('Selecione ou crie um cliente');
          clearTimeout(timeoutId);
          setSubmitting(false);
          return;
        }

        // Se contato existente sem instância e usuário escolheu uma, atualiza
        if (formInstanciaId && formSelectedContact && !formSelectedContact.instancia_id) {
          await supabase.from('contatos')
            .update({ instancia_id: formInstanciaId, updated_at: new Date().toISOString() })
            .eq('id', contatoId);
        }

        console.log('FINANCEIRO: contatoId=', contatoId, 'valor=', valor, 'canal=', formCanal);

        const canalPedido = formCanal === 'C-REP' ? 'REP' : formCanal;

        const produtosRpc = formProdutos.filter(fp => fp.produto_id).map(fp => {
          const prod = allProdutos.find(p => p.id === fp.produto_id);
          const preco = prod?.preco;
          return {
            produto: getProductDisplayName(prod || {}),
            produto_id: fp.produto_id,
            quantidade: fp.quantidade,
            valor_unit: preco != null ? Number(preco) : null,
            preco: preco != null ? Number(preco) : null,
          };
        });

        const SUPABASE_URL2 = import.meta.env.VITE_SUPABASE_URL;
        const SUPABASE_KEY2 = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
        const { data: sessionData2 } = await supabase.auth.getSession();
        const accessToken2 = sessionData2?.session?.access_token || SUPABASE_KEY2;

        // socio (recebedor) = formSocio selecionado no form
        // criado_por = identifica QUEM criou o lançamento (usuário logado), independente do recebedor
        const loggedUserLabel =
          socioLabels[profile?.socio_key || ''] ||
          profile?.socio_key ||
          profile?.nome ||
          user?.email?.split('@')[0] ||
          (mySocioKey ? mySocioKey : 'sistema');
        // Mantém compatibilidade com a RPC: o backend usa p_criado_por para mapear o sócio recebedor (V/A/P).
        // Por isso enviamos o sócio selecionado (formSocio) como sócio recebedor,
        // e gravamos quem realmente criou separadamente em p_obs prefix para auditoria caso necessário.
        const recebedorKey = (formSocio || mySocioKey || 'V').toLowerCase();

        const body = {
          p_contato_id: contatoId,
          p_canal: canalPedido,
          p_valor: valor,
          p_status_pagamento: formStatusPagamento,
          p_modalidade: formModalidade,
          p_uf_postagem: formUfPostagem || null,
          // Sócio recebedor (mapeado para V/A/P pela RPC)
          p_criado_por: recebedorKey,
          p_obs: formObs || null,
          p_produtos: produtosRpc.length > 0 ? produtosRpc : null,
        };

        console.log('FINANCEIRO: criar_pedido body:', body);

        const response = await fetch(`${SUPABASE_URL2}/rest/v1/rpc/criar_pedido_v2`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_KEY2,
            'Authorization': `Bearer ${accessToken2}`,
            'Prefer': 'return=representation',
          },
          body: JSON.stringify(body),
          signal: submitAbort.signal,
        });

        console.log('FINANCEIRO: criar_pedido status:', response.status);

        if (!response.ok) {
          const errorText = await response.text();
          console.error('FINANCEIRO: criar_pedido error:', errorText);
          throw new Error('Erro ao criar pedido: ' + errorText);
        }

        const rpcResult = await response.json();
        console.log('FINANCEIRO: criar_pedido result:', rpcResult);

        if (!rpcResult || (!rpcResult.pedido_id && rpcResult.status !== 'ok' && rpcResult.status !== 'criado')) {
          throw new Error('Erro ao criar pedido. Tente novamente.');
        }

        // Após criar a venda, sobrescreve criado_por do lançamento e do pedido
        // com o usuário REAL que está logado (independente do sócio recebedor selecionado)
        const pedidoId = rpcResult.pedido_id;
        if (pedidoId && loggedUserLabel) {
          await Promise.all([
            supabase.from('lancamentos_socios')
              .update({ criado_por: loggedUserLabel })
              .eq('pedido_id', pedidoId),
            supabase.from('pedidos')
              .update({ criado_por: loggedUserLabel })
              .eq('id', pedidoId),
          ]);
        }

        console.log('FINANCEIRO: Venda processada com sucesso! Recebedor:', formSocio, '| Criador:', loggedUserLabel);
      } else {
        const adminLabel =
          socioLabels[profile?.socio_key || ''] ||
          profile?.socio_key ||
          profile?.nome ||
          user?.email?.split('@')[0] ||
          'sistema';
        const { error: insertError } = await supabase.from('lancamentos_socios').insert({
          socio: formSocio,
          tipo: formTipo,
          valor: -valor,
          descricao: formDescricao,
          status_pagamento: '-',
          criado_por: adminLabel,
          snapshot_saldo_v: socioBalances['V'] ?? 0,
          snapshot_saldo_a: socioBalances['A'] ?? 0,
        } as any);
        if (insertError) throw insertError;
        
        // EXTRA_METRICA: debita saldo do sócio mas NÃO afeta financeiro/métricas
        // (uso para investimentos: máquinas, escritório, etc.)
        const categoriaMap: Record<string, string> = { ADS: 'ads', ETIQUETA: 'etiqueta', MATERIAL: 'material', LOGISTICA: 'logistica', INFLUENCER: 'influencer', INFRAESTRUTURA: 'infraestrutura' };
        if (categoriaMap[formTipo]) {
          await supabase.from('financeiro').insert({ tipo: 'despesa', valor, categoria: categoriaMap[formTipo] });
        }
      }

      toast.success(formTipo === 'VENDA' ? 'Pedido criado com sucesso!' : 'Lançamento criado!');
      resetForm();
      fetchAll();
    } catch (err: any) {
      console.error('Submit error:', err);
      if (err?.name !== 'AbortError') {
        toast.error(err.message || 'Erro ao salvar. Tente novamente.');
      }
    } finally {
      clearTimeout(timeoutId);
      setSubmitting(false);
    }
  };

  const handleEdit = async () => {
    if (!editItem) return;
    const valor = parseFloat(formValor.replace(',', '.'));
    const oldValor = editItem.valor;
    await supabase.from('lancamentos_socios').update({ valor, descricao: formDescricao }).eq('id', editItem.id);
    await supabase.from('log_atividades').insert({
      usuario: profile?.nome || 'Desconhecido', acao: 'Editou lançamento', tabela_afetada: 'lancamentos_socios', registro_id: editItem.id,
      detalhe: `${formatBRL(oldValor)} → ${formatBRL(valor)}`,
    });
    toast.success('Lançamento atualizado!');
    setEditItem(null);
    fetchAll();
  };

  const handleUpdateStatus = async (item: any, newStatus: 'pago' | 'pendente', socio?: string) => {
    try {
      if (item.tipo !== 'VENDA') return;

      if (item.locked_at) {
        toast.error('Lançamento bloqueado - não pode alterar status Pago após fechamento do dia');
        return;
      }

      if (newStatus === 'pago' && !socio) {
        setSelectSocioTarget(item);
        return;
      }

      const { error: pError } = await supabase.from('pedidos').update({ status_pagamento: newStatus }).eq('id', item.pedido_id);
      if (pError) throw pError;

      if (newStatus === 'pago') {
        const { error: lsError } = await supabase.from('lancamentos_socios').insert({
          socio: socio,
          tipo: 'VENDA',
          valor: item.valor,
          canal: item.canal,
          contato_id: item.contato_id,
          descricao: item.descricao || `Venda Pendente #${item.pedido_id}`,
          status_pagamento: 'pago',
          criado_por: profile?.nome || 'Sistema'
        });
        if (lsError) throw lsError;

        await supabase.from('financeiro')
          .update({ tipo: 'receita' })
          .or(`descricao.eq.${item.canal} - Venda Pendente #${item.pedido_id},descricao.ilike.%Venda Pendente #${item.pedido_id}%`);
      }

      toast.success(`Status atualizado para ${newStatus.toUpperCase()}`);
      setSelectSocioTarget(null);
      fetchAll();
    } catch (err: any) {
      toast.error('Erro ao atualizar status: ' + err.message);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    if (deleteTarget.locked_at) {
      toast.error('Lançamento bloqueado - não pode excluir após fechamento do dia');
      setDeleteTarget(null);
      return;
    }

    try {
      // Se for VENDA com pedido_id, usa RPC de exclusão completa (cascade)
      if (deleteTarget.tipo === 'VENDA' && deleteTarget.pedido_id) {
        const { data: rpcResult, error: rpcError } = await supabase.rpc('deletar_venda_completa', {
          p_lancamento_id: deleteTarget.id,
        });
        if (rpcError) throw rpcError;
        if (rpcResult && (rpcResult as any).status === 'error') {
          throw new Error((rpcResult as any).message);
        }
        await supabase.from('log_atividades').insert({
          usuario: profile?.nome || 'Desconhecido', acao: 'Excluiu venda completa (pedido + estoque)', tabela_afetada: 'lancamentos_socios', registro_id: deleteTarget.id,
          detalhe: `${formatBRL(deleteTarget.valor)} — VENDA — Pedido #${deleteTarget.pedido_id} — ${formatDateShort(deleteTarget.data)}`,
        });
      }
      // Se for agrupado (transferencia ou lucro explícito), usa _pairedIds
      else if (deleteTarget._pairedIds && deleteTarget._pairedIds.length > 0) {
        await supabase.from('lancamentos_socios').delete().in('id', deleteTarget._pairedIds);
        await supabase.from('log_atividades').insert({
          usuario: profile?.nome || 'Desconhecido', acao: `Excluiu lançamento agrupado ${deleteTarget.tipo}`, tabela_afetada: 'lancamentos_socios',
          detalhe: `${formatBRL(deleteTarget.valor)} — ${deleteTarget.tipo} — ${formatDateShort(deleteTarget.data)}`,
        });
      }
      // Backward compat: Se for LUCRO agrupado via descricao
      else if (deleteTarget.tipo === 'LUCRO' && deleteTarget._isGroupedLucro) {
        const { data: relatedLancs } = await supabase
          .from('lancamentos_socios')
          .select('id')
          .eq('tipo', 'LUCRO')
          .eq('descricao', deleteTarget.descricao);
        
        if (relatedLancs && relatedLancs.length > 0) {
          const idsToDelete = relatedLancs.map((l: any) => l.id);
          await supabase.from('lancamentos_socios').delete().in('id', idsToDelete);
          await supabase.from('log_atividades').insert({
            usuario: profile?.nome || 'Desconhecido', acao: 'Excluiu lançamento LUCRO', tabela_afetada: 'lancamentos_socios',
            detalhe: `${formatBRL(deleteTarget.valor)} — LUCRO — ${formatDateShort(deleteTarget.data)}`,
          });
        }
      } else {
        // Delete normal (custos, etc)
        await supabase.from('lancamentos_socios').delete().eq('id', deleteTarget.id);
        await supabase.from('log_atividades').insert({
          usuario: profile?.nome || 'Desconhecido', acao: 'Excluiu lançamento', tabela_afetada: 'lancamentos_socios', registro_id: deleteTarget.id,
          detalhe: `${formatBRL(deleteTarget.valor)} — ${deleteTarget.tipo} — ${formatDateShort(deleteTarget.data)}`,
        });
      }

      toast.success('Lançamento excluído!');
    } catch (err: any) {
      console.error('Delete error:', err);
      toast.error('Erro ao excluir: ' + (err.message || 'Erro desconhecido'));
    }
    setDeleteTarget(null);
    fetchAll();
  };

  const resetForm = () => {
    setShowForm(false); setFormTipo('VENDA'); setFormSocio(mySocioKey || 'V'); setFormCanal('ADS'); setFormValor('');
    setFormDescricao(''); setFormSelectedContact(null); setFormNewContact(false); setFormNewNome('');
    setFormNewTelefone(''); setFormNewEndereco(''); setFormNewNumero(''); setFormNewComplemento('');
    setFormNewBairro(''); setFormNewCpf('');
    setFormNewCidade(''); setFormNewUf(''); setFormNewCep('');
    setPhoneDuplicate(null); setFormProdutos([{ produto_id: '', quantidade: 1 }]); setFormContactSearch('');
    setFormModalidade('mini'); setFormUfPostagem(''); setFormStatusPagamento('pago'); setFormObs('');
    setClientSaved(false); setCepLoading(false); setFormRepresentanteId(null);
    setFormInstanciaId(null); setInstanciaLocked(false);
  };

  const openEdit = (item: any) => {
    if (item.locked_at) {
      toast.error('Lançamento bloqueado - não pode editar após fechamento do dia');
      return;
    }
    setEditItem(item);
    setFormValor(String(Math.abs(item.valor)));
    setFormDescricao(item.descricao || '');
    setShowForm(true);
  };

  const paged = lancamentos.slice((page - 1) * PER_PAGE, page * PER_PAGE);
  const totalPages = Math.ceil(lancamentos.length / PER_PAGE);

  const allBalancesForLucro = socios.map(s => socioBalances[s.key] ?? 0);
  const allPositive = allBalancesForLucro.every(b => b >= 0);
  const allNegative = allBalancesForLucro.every(b => b < 0);
  const canRealizarLucro = socios.length >= 2 && (allPositive || allNegative);
  const lucroMax = canRealizarLucro ? Math.min(...allBalancesForLucro.map(Math.abs)) : 0;

  if (loading) return <Skeleton className="h-96" />;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <h1 className="text-2xl font-bold">Financeiro</h1>
        {caixas.length < 5 && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => { setNovaCaixaApelido(''); setShowAddCaixa(true); }}
            title="Adicionar caixa (não-sócio, ex: gateway crypto)"
          >
            + Caixa
          </Button>
        )}
      </div>

      {/* Sócios + Caixas cards */}
      <div className="flex flex-col items-center gap-3">
        <div className="flex gap-3 flex-wrap justify-center max-w-4xl">
          {socios.map(s => {
            const saldo = socioBalances[s.key] ?? 0;
            return (
              <Card key={s.key} className="min-w-[160px]">
                <CardContent className="p-4 text-center">
                  <p className="text-sm font-bold text-muted-foreground">{s.nome}</p>
                  <p className={cn('text-xl font-bold', saldo < 0 ? 'text-destructive' : 'text-primary')}>{formatBRL(saldo)}</p>
                </CardContent>
              </Card>
            );
          })}
          {caixas.map(c => {
            const saldo = socioBalances[c.codigo] ?? 0;
            return (
              <Card key={c.codigo} className="min-w-[160px] border-amber-200 bg-amber-50/50 dark:bg-amber-950/20">
                <CardContent className="p-4 text-center">
                  <p className="text-sm font-bold text-amber-700 dark:text-amber-300 flex items-center justify-center gap-1">
                    🏪 {c.apelido}
                  </p>
                  <p className={cn('text-xl font-bold', saldo < 0 ? 'text-destructive' : 'text-amber-700 dark:text-amber-300')}>{formatBRL(saldo)}</p>
                  <p className="text-[10px] text-muted-foreground mt-0.5">Caixa · não divide lucro</p>
                </CardContent>
              </Card>
            );
          })}
        </div>
        <div className="flex gap-3">
          <Button onClick={() => { setShowLucro(true); setLucroError(''); }} className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground">Realizar Lucro</Button>
          <Button variant="outline" onClick={() => setShowTransfer(true)}>Transferir ⇄</Button>
        </div>
      </div>

      {/* Lancamentos list */}
      <div className="overflow-x-auto">
        <table className="w-full text-sm table-fixed">
          <thead>
            <tr className="border-b font-bold">
              <th className="text-left py-2 w-[18%]">Data</th>
              <th className="text-left py-2 w-[10%]" title="Operador (sócio ou caixa)">Op.</th>
              <th className="text-left py-2 w-[20%]">Tipo</th>
              <th className="text-right py-2 w-[28%]">Valor</th>
              <th className="py-2 w-[24%]"></th>
            </tr>
          </thead>
          <tbody>
            {paged.map(l => {
              const now = new Date();
              const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
              const isToday = l.data === todayStr;
              const canEdit = isToday && !l.locked_at;
              return (
              <tr 
                key={l.id} 
                className={cn('border-b hover:bg-muted/30 cursor-pointer', 
                  l.tipo === 'VENDA' ? 'bg-green-100/60 dark:bg-green-900/20' :
                  l.tipo === 'PARCELA_VENDA' ? 'bg-green-100/60 dark:bg-green-900/20' :
                  l.tipo === 'TRANSFERENCIA' ? 'bg-blue-100/50 dark:bg-blue-900/20' :
                  l.tipo === 'LUCRO' ? 'bg-yellow-100/70 dark:bg-yellow-900/25' :
                  l.tipo === 'EXTRA_METRICA' ? 'bg-purple-100/60 dark:bg-purple-900/20' :
                  (l.tipo === 'MATERIAL' || l.tipo === 'ETIQUETA' || l.tipo === 'ADS' || l.tipo === 'LOGISTICA' || l.tipo === 'INFLUENCER' || l.tipo === 'INFRAESTRUTURA') ? 'bg-red-100/60 dark:bg-red-900/20' :
                  'bg-muted/30'
                )}
                onClick={() => setDetailItem(l)}
              >
                <td className="py-2 truncate">{formatDateShort(l.data)}</td>
                <td className="py-2">{l.tipo === 'TRANSFERENCIA' ? (l.transferencia_direcao || '—') : (l.tipo === 'LUCRO' ? resolveCriadoPor(l.criado_por) : (socioLabels[l.socio] || l.socio || '—'))}</td>
                <td className="py-2 truncate">{l.tipo === 'PARCELA_VENDA' ? 'PARCELA DE VENDA' : l.tipo === 'EXTRA_METRICA' ? 'EXTRA MÉTRICA' : l.tipo}</td>
                <td className={cn('py-2 text-right font-medium whitespace-nowrap', Number(l.valor) < 0 && l.tipo !== 'TRANSFERENCIA' && 'text-destructive')}>{l.tipo === 'TRANSFERENCIA' ? (l._transferValor || formatBRL(Math.abs(Number(l.valor)))) : formatBRL(Number(l.valor))}</td>
                <td className="py-2" onClick={e => e.stopPropagation()}>
                  {canEdit && l.tipo !== 'TRANSFERENCIA' && l.tipo !== 'LUCRO' && (
                  <div className="flex gap-1 justify-end">
                    <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openEdit(l)}><Pencil className="w-3 h-3" /></Button>
                    <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => setDeleteTarget(l)}><Trash2 className="w-3 h-3" /></Button>
                  </div>
                  )}
                  {canEdit && l.tipo === 'TRANSFERENCIA' && (
                  <div className="flex gap-1 justify-end">
                    <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => setDeleteTarget(l)}><Trash2 className="w-3 h-3" /></Button>
                  </div>
                  )}
                  {canEdit && l.tipo === 'LUCRO' && (
                  <div className="flex gap-1 justify-end">
                    <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => setDeleteTarget(l)}><Trash2 className="w-3 h-3" /></Button>
                  </div>
                  )}
                </td>
              </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="flex justify-between items-center">
        <div />
        <div className="flex gap-2">
          <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}><ChevronLeft className="w-4 h-4" /> Anterior</Button>
          <span className="text-sm flex items-center">{page}/{totalPages || 1}</span>
          <Button variant="outline" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>Próxima <ChevronRight className="w-4 h-4" /></Button>
        </div>
      </div>

      {/* Aviso visual: lista mostra só últimos 180 dias (saldos refletem total real) */}
      <div className="flex justify-center pt-2 pb-4">
        <p className="text-xs text-muted-foreground italic">
          Exibindo lançamentos dos últimos {DIAS_OCULTACAO_FIN} dias — saldos dos sócios mostram o total real.
        </p>
      </div>

      {/* FAB */}
      <Button onClick={() => { resetForm(); setShowForm(true); }} className="fixed bottom-6 right-6 rounded-full h-14 w-14 shadow-lg bg-sf-green hover:bg-sf-green/90 text-primary-foreground z-50" size="icon">
        <Plus className="w-6 h-6" />
      </Button>

      {/* Dialog: Adicionar Caixa */}
      <Dialog open={showAddCaixa} onOpenChange={(o) => { if (!savingCaixa) setShowAddCaixa(o); }}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>🏪 Adicionar Caixa</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <p className="text-xs text-muted-foreground">
              Caixa registra recebimentos (vendas, parcelas) sem participar da divisão de
              lucro entre sócios. Útil pra carteiras de gateway (cripto, Pix terceirizado).
              Pode realizar transferência pra sócio. Não recebe transferência.
            </p>
            <div>
              <Label>Apelido do Caixa</Label>
              <Input
                value={novaCaixaApelido}
                onChange={(e) => setNovaCaixaApelido(e.target.value)}
                placeholder="ex: DeFlow Cripto, Pix Mercado Pago"
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && novaCaixaApelido.trim()) {
                    (document.activeElement as HTMLElement)?.blur();
                    document.getElementById('btn-criar-caixa')?.click();
                  }
                }}
              />
            </div>
            <Button
              id="btn-criar-caixa"
              className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground"
              disabled={savingCaixa || !novaCaixaApelido.trim()}
              onClick={async () => {
                setSavingCaixa(true);
                const { data, error } = await supabase.rpc('criar_caixa' as any, { p_apelido: novaCaixaApelido.trim() });
                setSavingCaixa(false);
                if (error) { toast.error('Erro: ' + error.message); return; }
                const r = data as any;
                if (!r?.ok) { toast.error('Erro: ' + (r?.error || 'falha desconhecida')); return; }
                toast.success(`Caixa "${r.apelido}" criada (${r.codigo})`);
                setShowAddCaixa(false);
                setNovaCaixaApelido('');
                fetchAll();
              }}
            >
              {savingCaixa ? 'Criando…' : 'Criar Caixa'}
            </Button>
            <p className="text-[10px] text-muted-foreground text-center">
              Limite: 5 caixas. Atual: {caixas.length}/5
            </p>
          </div>
        </DialogContent>
      </Dialog>

      {/* Realizar Lucro dialog */}
      <Dialog open={showLucro} onOpenChange={setShowLucro}>
        <DialogContent>
          <DialogHeader><DialogTitle>Realizar Lucro</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">Todos os sócios perdem o valor do lucro (abatimento)</p>
            <div>
              <Label>Valor</Label>
              <Input placeholder="R$ 0,00" value={lucroValue} onChange={e => { setLucroValue(e.target.value); setLucroError(''); }} />
              <p className="text-xs text-muted-foreground mt-1">Máximo: {formatBRL(lucroMax)}</p>
              {lucroError && <p className="text-xs text-destructive mt-1 font-semibold">{lucroError}</p>}
            </div>
            <Button type="button" onClick={handleRealizarLucro} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground">Confirmar</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Transfer dialog */}
      <Dialog open={showTransfer} onOpenChange={setShowTransfer}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Transferir entre Sócios</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>De (sócio ou caixa)</Label>
              <Select value={transferFrom} onValueChange={setTransferFrom}>
                <SelectTrigger><SelectValue placeholder="Selecionar origem" /></SelectTrigger>
                <SelectContent>
                  {socios.map(s => <SelectItem key={s.key} value={s.key}>{s.nome}</SelectItem>)}
                  {caixas.map(c => <SelectItem key={c.codigo} value={c.codigo}>🏪 {c.apelido}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Para (sócio)</Label>
              <Select value={transferTo} onValueChange={setTransferTo}>
                <SelectTrigger><SelectValue placeholder="Selecionar sócio" /></SelectTrigger>
                <SelectContent>
                  {/* Caixa NÃO recebe transferência — só faz. Por isso filtra fora dos destinos. */}
                  {socios.filter(s => s.key !== transferFrom).map(s => <SelectItem key={s.key} value={s.key}>{s.nome}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Valor (R$)</Label>
              <Input placeholder="0,00" value={transferValue} onChange={e => setTransferValue(e.target.value)} />
            </div>
            <Button className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground" onClick={handleTransfer}>Confirmar</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Lançamento form dialog — mobile optimized */}
      <Dialog open={showForm} onOpenChange={() => { resetForm(); setEditItem(null); }}>
        <DialogContent className={cn(
          isMobile ? 'fixed inset-0 max-w-none w-full h-full rounded-none m-0 translate-x-0 translate-y-0 top-0 left-0 flex flex-col' : 'max-w-md max-h-[80vh] overflow-y-auto'
        )}>
          <DialogHeader><DialogTitle>{editItem ? 'Editar Lançamento' : 'Novo Lançamento'}</DialogTitle></DialogHeader>
          <div className={cn('space-y-4', isMobile ? 'flex-1 overflow-y-auto pb-20 px-1' : '')}>
            {!editItem && (
              <>
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Tipo</Label>
                  <Select value={formTipo} onValueChange={setFormTipo}>
                    <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="VENDA">VENDA</SelectItem>
                      <SelectItem value="ADS">ADS</SelectItem>
                      <SelectItem value="ETIQUETA">ETIQUETA</SelectItem>
                      <SelectItem value="MATERIAL">MATERIAL</SelectItem>
                      <SelectItem value="LOGISTICA">LOGÍSTICA</SelectItem>
                      <SelectItem value="INFLUENCER">INFLUENCER</SelectItem>
                      <SelectItem value="INFRAESTRUTURA">INFRAESTRUTURA</SelectItem>
                      <SelectItem value="EXTRA_METRICA">EXTRA MÉTRICA</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {formTipo === 'VENDA' && (
                  <div className="flex items-center justify-between">
                    <Label className="text-xs text-muted-foreground uppercase tracking-wide">Status</Label>
                    <div className="flex items-center gap-2">
                      <span className={cn('text-sm font-medium', formStatusPagamento === 'pendente' ? 'text-orange-500' : 'text-primary')}>
                        {formStatusPagamento === 'pago' ? 'Pago' : 'Pendente'}
                      </span>
                      <Switch
                        checked={formStatusPagamento === 'pago'}
                        onCheckedChange={v => setFormStatusPagamento(v ? 'pago' : 'pendente')}
                        className="data-[state=checked]:bg-sf-green"
                      />
                    </div>
                  </div>
                )}
                <Separator />
              </>
            )}
            {(formTipo !== 'VENDA' || formStatusPagamento === 'pago') && (
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Sócio / Caixa</Label>
                  <div className="flex flex-wrap gap-2 mt-1">
                    {socios.map(s => (
                      <Button key={s.key} variant={formSocio === s.key ? 'default' : 'outline'} className="min-h-[44px] flex-1" onClick={() => setFormSocio(s.key)}>{s.nome}</Button>
                    ))}
                    {caixas.map(c => (
                      <Button
                        key={c.codigo}
                        variant={formSocio === c.codigo ? 'default' : 'outline'}
                        className={cn(
                          'min-h-[44px] flex-1',
                          formSocio === c.codigo
                            ? 'bg-amber-600 hover:bg-amber-700 text-white'
                            : 'border-amber-300 text-amber-700 hover:bg-amber-50 dark:hover:bg-amber-950/30'
                        )}
                        onClick={() => setFormSocio(c.codigo)}
                      >
                        🏪 {c.apelido}
                      </Button>
                    ))}
                  </div>
                </div>
            )}
            <Separator />
            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Valor (R$)</Label>
              <Input value={formValor} onChange={e => setFormValor(e.target.value)} placeholder="0,00" className="min-h-[44px]" />
            </div>

            {formTipo === 'VENDA' && !editItem && (
              <>
                <Separator />
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Canal</Label>
                  <Select value={formCanal} onValueChange={setFormCanal}>
                    <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ADS">ADS</SelectItem>
                      <SelectItem value="BASE">BASE</SelectItem>
                      <SelectItem value="REP">REP</SelectItem>
                      <SelectItem value="C-REP">C-REP</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {formCanal === 'C-REP' && formNewContact && (
                  <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground uppercase tracking-wide">Representante Responsável</Label>
                    <Select value={formRepresentanteId || ''} onValueChange={setFormRepresentanteId}>
                      <SelectTrigger className="min-h-[44px]">
                        <SelectValue placeholder="Selecionar representante..." />
                      </SelectTrigger>
                      <SelectContent>
                        {allREPs.map(r => <SelectItem key={r.id} value={r.id}>{r.nome}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                )}
                {formCanal === 'C-REP' && !formNewContact && formSelectedContact && formSelectedContact.representante_id && (
                  <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground uppercase tracking-wide">Representante Responsável</Label>
                    <div className="px-3 py-2 border rounded-md bg-muted/50 text-sm min-h-[44px] flex items-center">
                      {allREPs.find(r => r.id === formSelectedContact.representante_id)?.nome || 'Representante vinculado'}
                      <span className="ml-auto text-xs text-muted-foreground">(vinculado ao cliente)</span>
                    </div>
                  </div>
                )}
                <Separator />
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Cliente</Label>
                  {!formNewContact && !formSelectedContact && !clientSaved ? (
                    <>
                      <Input placeholder="Buscar cliente..." value={formContactSearch} onChange={e => searchContacts(e.target.value)} className="min-h-[44px] mt-1" />
                      {formContacts.length > 0 && (
                        <div className="border rounded mt-1 max-h-32 overflow-y-auto">
                          {formContacts.map(c => (
                            <button key={c.id} className="w-full text-left px-3 py-2 hover:bg-muted text-sm min-h-[44px]" onClick={() => selectExistingContact(c)}>
                              {c.nome} — {c.telefone}
                            </button>
                          ))}
                        </div>
                      )}
                      <Button variant="link" size="sm" className="mt-1" onClick={() => { setFormNewContact(true); setClientSaved(false); }}>+ Criar novo cliente</Button>
                    </>
                  ) : clientSaved && !formNewContact ? (
                    /* Client pre-saved: show only name + pencil */
                    <div className="border rounded-md p-3 bg-muted/30 mt-2">
                      <div className="flex items-center justify-between">
                        <div>
                          <p className="font-bold text-sm">{formNewNome || formSelectedContact?.nome}</p>
                          <p className="text-xs text-muted-foreground">{formNewTelefone || formSelectedContact?.telefone}</p>
                          {formNewCidade && <p className="text-xs text-muted-foreground">{formNewCidade}{formNewUf ? `/${formNewUf}` : ''}</p>}
                        </div>
                        <Button variant="ghost" size="icon" onClick={handleEditClient}>
                          <Pencil className="w-4 h-4" />
                        </Button>
                      </div>
                      <Button variant="link" size="sm" className="px-0 mt-1 h-auto" onClick={() => { setFormSelectedContact(null); setFormNewContact(false); setClientSaved(false); setFormNewNome(''); setFormNewTelefone(''); setFormNewCpf(''); setFormNewEndereco(''); setFormNewNumero(''); setFormNewComplemento(''); setFormNewBairro(''); setFormNewCidade(''); setFormNewUf(''); setFormNewCep(''); }}>
                        Trocar cliente
                      </Button>
                    </div>
                  ) : (
                    /* Client form (new or editing) */
                    <div className={cn('space-y-2 mt-2', isMobile && 'space-y-3')}>
                      <Input placeholder="Nome" value={formNewNome} onChange={e => setFormNewNome(e.target.value)} className="min-h-[44px]" />
                      <Input placeholder="CPF" value={formNewCpf} onChange={e => setFormNewCpf(e.target.value)} className="min-h-[44px]" />
                      <div className="flex gap-2">
                        <div className="flex items-center justify-center px-3 border rounded-md bg-muted text-sm min-h-[44px]">🇧🇷 +55</div>
                        <Input 
                          placeholder={formCanal === 'C-REP' ? "(XX) XXXXX-XXXX Opcional" : "(XX) XXXXX-XXXX"} 
                          value={formNewTelefone} 
                          onChange={e => {
                            const masked = applyPhoneMask(e.target.value);
                            setFormNewTelefone(masked);
                            checkPhoneDuplicate(masked);
                          }} 
                          className="min-h-[44px] flex-1" 
                        />
                      </div>
                      {phoneDuplicate && (
                        <div className="bg-amber-50 dark:bg-amber-950 border border-amber-300 dark:border-amber-700 rounded p-2 text-sm">
                          <p className="text-amber-700 dark:text-amber-300">⚠️ Este número já está cadastrado como <strong>{phoneDuplicate.nome}</strong>. Deseja usar este contato?</p>
                          <div className="flex gap-2 mt-2">
                            <Button size="sm" variant="outline" className="min-h-[44px]" onClick={() => selectExistingContact(phoneDuplicate)}>Usar contato existente</Button>
                            <Button size="sm" variant="ghost" className="min-h-[44px]" onClick={() => setPhoneDuplicate(null)}>Criar mesmo assim</Button>
                          </div>
                        </div>
                      )}
                      <Input placeholder="Endereço (Rua)" value={formNewEndereco} onChange={e => setFormNewEndereco(e.target.value)} className="min-h-[44px]" />
                      <Input placeholder="Número" value={formNewNumero} onChange={e => setFormNewNumero(e.target.value)} className="min-h-[44px]" />
                      {/* CEP right below Número */}
                      <div className="relative">
                        <Input
                          placeholder="CEP (XXXXX-XXX)"
                          value={formNewCep}
                          onChange={e => {
                            const masked = applyCepMask(e.target.value);
                            setFormNewCep(masked);
                            if (masked.replace(/\D/g, '').length === 8) {
                              lookupCep(masked);
                            }
                          }}
                          className="min-h-[44px]"
                        />
                        {cepLoading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-muted-foreground" />}
                      </div>
                      <Input placeholder="Complemento (opcional)" value={formNewComplemento} onChange={e => setFormNewComplemento(e.target.value)} className="min-h-[44px]" />
                      <Input placeholder="Bairro" value={formNewBairro} onChange={e => setFormNewBairro(e.target.value)} className="min-h-[44px]" />
                      {/* Cidade and UF separate */}
                      <div className="flex gap-2">
                        <Input placeholder="Cidade" value={formNewCidade} onChange={e => setFormNewCidade(e.target.value)} className="min-h-[44px] flex-1" />
                        <Select value={formNewUf} onValueChange={setFormNewUf}>
                          <SelectTrigger className="min-h-[44px] w-24">
                            <SelectValue placeholder="UF" />
                          </SelectTrigger>
                          <SelectContent>
                            {UF_OPTIONS.map(uf => (
                              <SelectItem key={uf} value={uf}>{uf}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="flex gap-2">
                        <Button
                          className="bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px] flex-1"
                          onClick={handleSaveClient}
                        >
                          <Check className="w-4 h-4 mr-1" /> Salvar Cliente
                        </Button>
                        <Button variant="link" size="sm" onClick={() => { setFormNewContact(false); setFormSelectedContact(null); setClientSaved(false); }}>{formSelectedContact ? 'Trocar cliente' : 'Buscar cliente existente'}</Button>
                      </div>
                    </div>
                  )}
                </div>
                {formTipo === 'VENDA' && allInstancias.length > 0 && (
                  <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground uppercase tracking-wide">Instância</Label>
                    <Select
                      value={formInstanciaId || ''}
                      onValueChange={setFormInstanciaId}
                      disabled={instanciaLocked}
                    >
                      <SelectTrigger className="min-h-[44px]">
                        <SelectValue placeholder="Selecionar instância..." />
                      </SelectTrigger>
                      <SelectContent>
                        {allInstancias.map(i => (
                          <SelectItem key={i.id} value={i.id}>Instância {i.nome}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    {instanciaLocked && (
                      <p className="text-[10px] text-muted-foreground">Vinculada ao cliente — não editável aqui</p>
                    )}
                  </div>
                )}
                <Separator />
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Produtos</Label>
                  {formProdutos.map((fp, idx) => (
                    <div key={idx} className={cn('mt-2', isMobile ? 'flex flex-col gap-2' : 'flex gap-2')}>
                      <Select value={fp.produto_id} onValueChange={v => { const n = [...formProdutos]; n[idx].produto_id = v; setFormProdutos(n); }}>
                        <SelectTrigger className={cn('min-h-[44px]', !isMobile && 'flex-1')}><SelectValue placeholder="Produto" /></SelectTrigger>
                        <SelectContent>
                          {allProdutos.map(p => (
                            <SelectItem key={p.id} value={p.id}>
                              {getProductDisplayName(p)}
                              {p.produtos_grupos?.nome && <span className="text-muted-foreground ml-1 text-xs">({p.produtos_grupos.nome})</span>}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Input type="number" min={1} value={fp.quantidade} onChange={e => { const n = [...formProdutos]; n[idx].quantidade = Number(e.target.value); setFormProdutos(n); }} className={cn('min-h-[44px]', isMobile ? 'w-full' : 'w-20')} placeholder="Qtd" />
                    </div>
                  ))}
                  <Button variant="link" size="sm" onClick={() => setFormProdutos([...formProdutos, { produto_id: '', quantidade: 1 }])}>➕ Adicionar produto</Button>
                </div>
                <Separator />
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Modalidade</Label>
                  <Select value={formModalidade} onValueChange={setFormModalidade}>
                    <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="mini">Mini</SelectItem>
                      <SelectItem value="pac">PAC</SelectItem>
                      <SelectItem value="sedex">SEDEX</SelectItem>
                      <SelectItem value="entrega_maos">Entrega em Mãos</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Origem (UF Postagem)</Label>
                  <Select value={formUfPostagem} onValueChange={setFormUfPostagem}>
                    <SelectTrigger className="min-h-[44px]"><SelectValue placeholder="Selecionar" /></SelectTrigger>
                    <SelectContent>
                      {ufsCadastradas.length === 0 ? (
                        <div className="px-2 py-1.5 text-xs text-muted-foreground">Nenhuma UF cadastrada</div>
                      ) : (
                        ufsCadastradas.map(uf => (
                          <SelectItem key={uf} value={uf}>{uf}</SelectItem>
                        ))
                      )}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Observação (Opcional)</Label>
                  <Textarea 
                    value={formObs} 
                    onChange={e => setFormObs(e.target.value)} 
                    placeholder="Notas sobre a venda..." 
                    className="mt-1 min-h-[80px]"
                  />
                </div>
              </>
            )}

            {formTipo !== 'VENDA' && !editItem && (
              <>
                <Separator />
                <div><Label className="text-xs text-muted-foreground uppercase tracking-wide">Descrição</Label><Input value={formDescricao} onChange={e => setFormDescricao(e.target.value)} className="min-h-[44px]" /></div>
              </>
            )}
            {editItem && <div><Label>Descrição</Label><Input value={formDescricao} onChange={e => setFormDescricao(e.target.value)} className="min-h-[44px]" /></div>}

            {!isMobile && (
              <Button onClick={editItem ? handleEdit : handleSubmitForm} disabled={submitting} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px]">
                {submitting ? 'Salvando...' : editItem ? 'Salvar' : 'Adicionar'}
              </Button>
            )}
          </div>

          {isMobile && (
            <div className="fixed bottom-0 left-0 right-0 p-4 bg-background border-t border-border z-50">
              <Button onClick={editItem ? handleEdit : handleSubmitForm} disabled={submitting} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px]">
                {submitting ? 'Salvando...' : editItem ? 'Salvar' : 'Adicionar'}
              </Button>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Delete confirm */}
      <AlertDialog open={!!deleteTarget} onOpenChange={() => setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader><AlertDialogTitle>Excluir lançamento?</AlertDialogTitle><AlertDialogDescription>Esta ação não pode ser desfeita.</AlertDialogDescription></AlertDialogHeader>
          <AlertDialogFooter><AlertDialogCancel>Cancelar</AlertDialogCancel><AlertDialogAction onClick={handleDelete} className="bg-destructive text-destructive-foreground">Excluir</AlertDialogAction></AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Select Sócio dialog */}
      <Dialog open={!!selectSocioTarget} onOpenChange={() => setSelectSocioTarget(null)}>
        <DialogContent className="max-w-xs">
          <DialogHeader><DialogTitle>Selecionar Sócio</DialogTitle></DialogHeader>
          <div className="flex gap-4 flex-wrap">
            {socios.map(s => (
              <Button key={s.key} className="flex-1 min-h-[44px]" onClick={() => handleUpdateStatus(selectSocioTarget, 'pago', s.key)}>{s.nome}</Button>
            ))}
          </div>
        </DialogContent>
      </Dialog>

      {/* Detail Popup */}
      <Dialog open={!!detailItem} onOpenChange={() => setDetailItem(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Detalhes do Lançamento</DialogTitle></DialogHeader>
          {detailItem && (
            <div className="space-y-3 py-2">
              {detailItem.tipo === 'VENDA' || detailItem.tipo === 'PARCELA_VENDA' ? (
                <>
                  {detailItem.tipo === 'PARCELA_VENDA' && (
                    <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Tipo:</span><span className="font-medium text-green-600">PARCELA DE VENDA</span></div>
                  )}
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Recebido por:</span><span className="font-medium">{socioLabels[detailItem.socio] || detailItem.socio || '—'}</span></div>
                  <div className="flex justify-between border-b pb-1">
                    <span className="text-muted-foreground">Cliente:</span>
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{detailItem.contatos?.nome || '—'}</span>
                      {detailItem.contatos && (
                        <Button variant="outline" size="sm" className="h-6 text-[10px] px-2" onClick={() => setSelectSocioTarget({ ...detailItem.contatos, isContactDetail: true })}>
                          Ver Cliente
                        </Button>
                      )}
                    </div>
                  </div>
                  <div className="flex justify-between border-b pb-1">
                    <span className="text-muted-foreground">Criado por:</span>
                    <span className="font-medium">
                      {(!detailItem.criado_por || detailItem.criado_por === '-') ? (socioLabels[detailItem.socio] || detailItem.socio || '—') : resolveCriadoPor(detailItem.criado_por)}
                    </span>
                  </div>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">{detailItem.tipo === 'PARCELA_VENDA' ? 'Valor da Parcela:' : 'Valor Total:'}</span><span className="font-medium text-sf-green">{formatBRL(Math.abs(detailItem.valor))}</span></div>
                  {(detailItem.snapshot_saldo_v != null || detailItem.snapshot_saldo_a != null) && (
                    <div className="border-b pb-1 pt-1">
                      <span className="text-muted-foreground text-xs block mb-1">Saldos (antes → depois):</span>
                      {socios.map(s => {
                        const snap = s.key === 'V' ? detailItem.snapshot_saldo_v : detailItem.snapshot_saldo_a;
                        if (snap == null) return null;
                        
                        // VENDA: Participa apenas quem recebeu
                        if (s.key !== detailItem.socio) return null;
                        
                        const depois = snap + Math.abs(detailItem.valor);
                        return (
                          <div key={s.key} className="flex justify-between text-sm">
                            <span>{s.nome}:</span>
                            <span className="font-medium">{formatBRL(snap)} + {formatBRL(Math.abs(detailItem.valor))} = {formatBRL(depois)}</span>
                          </div>
                        );
                      })}
                    </div>
                  )}
                  {detailItem.descricao && detailItem.descricao.trim() !== '' && !/^Venda\s*#/i.test(detailItem.descricao) && !/^Venda\s+Pendente/i.test(detailItem.descricao) && (
                    <div className="flex justify-between border-b pb-1 gap-2">
                      <span className="text-muted-foreground shrink-0">Observação:</span>
                      <span className="font-medium text-right break-words">{detailItem.descricao}</span>
                    </div>
                  )}
                </>
              ) : detailItem.tipo === 'TRANSFERENCIA' ? (
                <>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Tipo:</span><span className="font-medium">{detailItem.tipo}</span></div>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Direção:</span><span className="font-medium">{detailItem.transferencia_direcao || detailItem.descricao || '—'}</span></div>
                  <div className="flex justify-between border-b pb-1">
                    <span className="text-muted-foreground">Criado por:</span>
                    <span className="font-medium">
                      {(!detailItem.criado_por || detailItem.criado_por === '-') ? (socioLabels[detailItem.socio] || detailItem.socio || '—') : resolveCriadoPor(detailItem.criado_por)}
                    </span>
                  </div>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Valor:</span><span className="font-medium">{formatBRL(Math.abs(detailItem.valor))}</span></div>
                  {(detailItem.snapshot_saldo_v != null || detailItem.snapshot_saldo_a != null) && (
                    <div className="border-b pb-1 pt-1">
                      <span className="text-muted-foreground text-xs block mb-1">Saldos (antes → depois):</span>
                      {socios.map(s => {
                        const snap = s.key === 'V' ? detailItem.snapshot_saldo_v : detailItem.snapshot_saldo_a;
                        if (snap == null) return null;
                        
                        const dir = detailItem.transferencia_direcao || detailItem.descricao || '';
                        let fromName = '';
                        let toName = '';
                        if (dir.includes('→')) [fromName, toName] = dir.split('→').map(x => x.trim());
                        else if (dir.includes('->')) [fromName, toName] = dir.split('->').map(x => x.trim());

                        // Verifica se o sócio é remetente ou destinatário
                        let isSender = (s.nome === fromName) || (s.key === fromName);
                        let isReceiver = (s.nome === toName) || (s.key === toName);

                        // Fallback caso a direção não esteja formatada
                        if (!isSender && !isReceiver) {
                           if (dir.includes(s.nome) || dir.includes(s.key)) {
                              if (detailItem.valor < 0) {
                                isSender = (s.key === detailItem.socio);
                                isReceiver = !isSender;
                              } else {
                                isReceiver = (s.key === detailItem.socio);
                                isSender = !isReceiver;
                              }
                           } else {
                              // Sócio não está envolvido nesta transferência
                              return null; 
                           }
                        }

                        // TRANSFERÊNCIA: Participa apenas quem enviou ou recebeu
                        if (!isSender && !isReceiver) return null;
                        
                        const delta = isSender ? -Math.abs(detailItem.valor) : Math.abs(detailItem.valor);
                        const depois = snap + delta;
                        return (
                          <div key={s.key} className="flex justify-between text-sm">
                            <span>{s.nome}:</span>
                            <span className="font-medium">{formatBRL(snap)} {delta >= 0 ? '+' : '-'} {formatBRL(Math.abs(delta))} = {formatBRL(depois)}</span>
                          </div>
                        );
                      })}
                    </div>
                  )}
                  {detailItem.descricao && detailItem.descricao.trim() !== '' && !/^Transferência/i.test(detailItem.descricao) && (
                    <div className="flex justify-between border-b pb-1 gap-2">
                      <span className="text-muted-foreground shrink-0">Observação:</span>
                      <span className="font-medium text-right break-words">{detailItem.descricao}</span>
                    </div>
                  )}
                </>
              ) : detailItem.tipo === 'LUCRO' ? (
                <>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Tipo:</span><span className="font-medium">{detailItem.tipo}</span></div>
                  <div className="flex justify-between border-b pb-1">
                    <span className="text-muted-foreground">Criado por:</span>
                    <span className="font-medium">{resolveCriadoPor(detailItem.criado_por)}</span>
                  </div>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">{detailItem.valor >= 0 ? 'Valor abatido:' : 'Valor realizado:'}</span><span className="font-medium text-destructive">{formatBRL(Math.abs(detailItem.valor))}</span></div>
                  {(detailItem.snapshot_saldo_v != null || detailItem.snapshot_saldo_a != null) && (
                    <div className="border-b pb-1 pt-1">
                      <span className="text-muted-foreground text-xs block mb-1">Saldos (antes → depois):</span>
                      {socios.map(s => {
                        const snap = s.key === 'V' ? detailItem.snapshot_saldo_v : detailItem.snapshot_saldo_a;
                        if (snap == null) return null;
                        // valor do lançamento é SINALIZADO: abate = +val (soma,
                        // aproxima de zero), lucro normal = -val (subtrai).
                        const depois = snap + detailItem.valor;
                        const op = detailItem.valor >= 0 ? '+' : '-';
                        return (
                          <div key={s.key} className="flex justify-between text-sm">
                            <span>{s.nome}:</span>
                            <span className="font-medium">{formatBRL(snap)} {op} {formatBRL(Math.abs(detailItem.valor))} = {formatBRL(depois)}</span>
                          </div>
                        );
                      })}
                    </div>
                  )}
                  {detailItem.descricao && detailItem.descricao.trim() !== '' && !/^Lucro:/i.test(detailItem.descricao) && (
                    <div className="flex justify-between border-b pb-1 gap-2">
                      <span className="text-muted-foreground shrink-0">Observação:</span>
                      <span className="font-medium text-right break-words">{detailItem.descricao}</span>
                    </div>
                  )}
                </>
              ) : (
                <>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Tipo:</span><span className="font-medium">{detailItem.tipo === 'EXTRA_METRICA' ? 'EXTRA MÉTRICA' : detailItem.tipo}</span></div>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Socio:</span><span className="font-medium">{socioLabels[detailItem.socio] || detailItem.socio || '—'}</span></div>
                  <div className="flex justify-between border-b pb-1"><span className="text-muted-foreground">Valor:</span><span className="font-medium">{formatBRL(Math.abs(detailItem.valor))}</span></div>
                  {(detailItem.snapshot_saldo_v != null || detailItem.snapshot_saldo_a != null) && (
                    <div className="border-b pb-1 pt-1">
                      <span className="text-muted-foreground text-xs block mb-1">Saldos (antes → depois):</span>
                      {socios.map(s => {
                        const snap = s.key === 'V' ? detailItem.snapshot_saldo_v : detailItem.snapshot_saldo_a;
                        if (snap == null) return null;
                        
                        // DESPESA/CUSTO: Participa apenas quem sofreu a despesa
                        if (s.key !== detailItem.socio) return null;
                        
                        const depois = snap - Math.abs(detailItem.valor);
                        return (
                          <div key={s.key} className="flex justify-between text-sm">
                            <span>{s.nome}:</span>
                            <span className="font-medium">{formatBRL(snap)} - {formatBRL(Math.abs(detailItem.valor))} = {formatBRL(depois)}</span>
                          </div>
                        );
                      })}
                    </div>
                  )}
                  {detailItem.descricao && detailItem.descricao.trim() !== '' && (
                    <div className="flex justify-between border-b pb-1 gap-2">
                      <span className="text-muted-foreground shrink-0">Observação:</span>
                      <span className="font-medium text-right break-words">{detailItem.descricao}</span>
                    </div>
                  )}
                </>
              )}</div>
          )}
        </DialogContent>
      </Dialog>

      {/* Pedido detail dialog (Reused from PedidosPage) */}
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
                        <p key={i} className="ml-2">• {p.produto} × {p.quantidade}</p>
                      ));
                    }
                  } catch {}
                  return <p className="ml-2">{detailPedido.produto} × {detailPedido.quantidade}</p>;
                })()}
              </div>
              <p><strong>Valor Total:</strong> {formatBRL(Number(detailPedido.valor))}</p>
              <p><strong>CPF:</strong> {(detailPedido.contatos as any)?.cpf || '—'}</p>
              <p><strong>Endereço:</strong> {(detailPedido.contatos as any)?.endereco || '—'}</p>
              <p><strong>Complemento:</strong> {(detailPedido.contatos as any)?.complemento || '—'}</p>
              <p><strong>Bairro:</strong> {(detailPedido.contatos as any)?.bairro || '—'}</p>
              <p><strong>Cidade/UF:</strong> {(detailPedido.contatos as any)?.cidade_uf || '—'}</p>
              <p><strong>CEP:</strong> {(detailPedido.contatos as any)?.cep || '—'}</p>
              <p><strong>Canal:</strong> {detailPedido.canal}</p>
              <p><strong>Status:</strong> {detailPedido.status_pedido === 'entregue' ? 'Entregue' : detailPedido.status_pedido === 'postado' ? 'Postado' : 'Aguardando Postagem'}</p>
              <p><strong>Rastreio:</strong> {detailPedido.codigo_rastreio || 'Aguardando rastreio'}</p>
            </div>
          )}
        </DialogContent>
      </Dialog>
      <Dialog open={!!selectSocioTarget?.isContactDetail} onOpenChange={() => setSelectSocioTarget(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Dados do Cliente</DialogTitle></DialogHeader>
          {selectSocioTarget && (
            <div className="space-y-2 text-sm">
              <p><strong>Nome:</strong> {selectSocioTarget.nome}</p>
              <div className="flex items-center gap-2">
                <p><strong>Telefone:</strong> {selectSocioTarget.telefone || '—'}</p>
                {selectSocioTarget.telefone && (
                  <Button variant="ghost" size="icon" className="h-6 w-6 p-0" onClick={() => copyToClipboard(selectSocioTarget.telefone).then(s => s && toast.success('Telefone copiado!'))}>
                    <Copy className="w-3 h-3" />
                  </Button>
                )}
              </div>
              <p><strong>CPF:</strong> {selectSocioTarget.cpf || '—'}</p>
              <Separator className="my-2" />
              <p><strong>Endereço:</strong> {selectSocioTarget.endereco || '—'}</p>
              <p><strong>Bairro:</strong> {selectSocioTarget.bairro || '—'}</p>
              <p><strong>Cidade/UF:</strong> {selectSocioTarget.cidade_uf || '—'}</p>
              <p><strong>CEP:</strong> {selectSocioTarget.cep || '—'}</p>
              {selectSocioTarget.observacao && (
                <>
                  <Separator className="my-2" />
                  <p><strong>Obs:</strong> {selectSocioTarget.observacao}</p>
                </>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

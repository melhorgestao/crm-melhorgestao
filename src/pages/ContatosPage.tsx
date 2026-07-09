import { useEffect, useState, useMemo } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Skeleton } from '@/components/ui/skeleton';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { formatBRL, formatDateShort } from '@/lib/format';
import { Copy, Download, Trophy, Merge, MapPin, Plus, Pencil, Check, Loader2 } from 'lucide-react';
import { cn, copyToClipboard } from '@/lib/utils';
import { useIsMobile } from '@/hooks/use-mobile';

const UF_OPTIONS = [
  'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
  'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SE','SP','TO'
];

// Países (DDI) pra cadastro de contatos internacionais. Brasil é o default.
// Códigos ÚNICOS (value do Select). EUA/Canadá compartilham o +1.
const COUNTRIES = [
  { code: '55',  flag: '🇧🇷', name: 'Brasil' },
  { code: '1',   flag: '🇺🇸', name: 'EUA/Canadá' },
  { code: '351', flag: '🇵🇹', name: 'Portugal' },
  { code: '54',  flag: '🇦🇷', name: 'Argentina' },
  { code: '598', flag: '🇺🇾', name: 'Uruguai' },
  { code: '595', flag: '🇵🇾', name: 'Paraguai' },
  { code: '56',  flag: '🇨🇱', name: 'Chile' },
  { code: '57',  flag: '🇨🇴', name: 'Colômbia' },
  { code: '52',  flag: '🇲🇽', name: 'México' },
  { code: '34',  flag: '🇪🇸', name: 'Espanha' },
  { code: '44',  flag: '🇬🇧', name: 'Reino Unido' },
  { code: '33',  flag: '🇫🇷', name: 'França' },
  { code: '49',  flag: '🇩🇪', name: 'Alemanha' },
  { code: '39',  flag: '🇮🇹', name: 'Itália' },
  { code: '41',  flag: '🇨🇭', name: 'Suíça' },
  { code: '81',  flag: '🇯🇵', name: 'Japão' },
];

// Máscara genérica internacional: só dígitos (até 15 = máximo E.164).
const applyIntlMask = (val: string) => val.replace(/\D/g, '').slice(0, 15);

// Detecta país + número nacional a partir do telefone salvo (dígitos).
// BR: nacional sem 55 (10 díg fixo, ou 11 díg móvel com 9º dígito).
// Estrangeiro: casa o MAIOR prefixo de DDI conhecido.
const detectCountry = (stored: string | null | undefined): { code: string; national: string } => {
  const d = (stored || '').replace(/\D/g, '');
  if (!d) return { code: '55', national: '' };
  if ((d.length === 12 || d.length === 13) && d.startsWith('55')) return { code: '55', national: d.slice(2) };
  if (d.length === 10 || (d.length === 11 && d[2] === '9')) return { code: '55', national: d };
  const foreign = COUNTRIES.filter(c => c.code !== '55').map(c => c.code).sort((a, b) => b.length - a.length);
  for (const code of foreign) if (d.startsWith(code)) return { code, national: d.slice(code.length) };
  return { code: '55', national: d };
};

export default function ContatosPage() {
  const { profile, user } = useAuth();
  const queryClient = useQueryClient();
  const isMobile = useIsMobile();
  const isRepresentante = profile?.tipo_usuario === 'representante';
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<any>(null);
  const [contactPedidos, setContactPedidos] = useState<any[]>([]);
  const [editNome, setEditNome] = useState('');
  const [editTelefone, setEditTelefone] = useState('');
  const [editCanalAtual, setEditCanalAtual] = useState('BASE');
  const [editCountry, setEditCountry] = useState('55');
  const [editRepresentanteId, setEditRepresentanteId] = useState<string | null>(null);
  const [editInstanciaId, setEditInstanciaId] = useState<string | null>(null);
  const [editIsCliente, setEditIsCliente] = useState(false);
  const [editEndereco, setEditEndereco] = useState('');
  const [editNumero, setEditNumero] = useState('');
  const [editComplemento, setEditComplemento] = useState('');
  const [editBairro, setEditBairro] = useState('');
  const [editCidade, setEditCidade] = useState('');
  const [editUf, setEditUf] = useState('');
  const [editCep, setEditCep] = useState('');
  const [editCpf, setEditCpf] = useState('');
  const [editObs, setEditObs] = useState('');
  const [editPhoneDuplicate, setEditPhoneDuplicate] = useState<any>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showMerge, setShowMerge] = useState(false);
  const [mergeContacts, setMergeContacts] = useState<any[]>([]);
  const [cepLoading, setCepLoading] = useState(false);
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Sort state - default: alphabetical by name (A-Z)
  const [sortColumn, setSortColumn] = useState<'nome' | 'created_at'>('nome');
  const [sortAsc, setSortAsc] = useState(true);
  // 'all' = todas instâncias | <uuid> = instância específica
  const [instanciaFilter, setInstanciaFilter] = useState<string>('all');
  const [filterClientes, setFilterClientes] = useState(false);
  const [filterCanais, setFilterCanais] = useState<Set<string>>(new Set());

  const toggleCanal = (canal: string) => {
    setFilterCanais(prev => {
      const next = new Set(prev);
      if (next.has(canal)) next.delete(canal); else next.add(canal);
      return next;
    });
  };
  const canaisKey = useMemo(() => Array.from(filterCanais).sort().join(','), [filterCanais]);

  const toggleSort = (col: 'nome' | 'created_at') => {
    if (sortColumn === col) {
      setSortAsc(!sortAsc);
    } else {
      setSortColumn(col);
      setSortAsc(col === 'nome');
    }
  };

  // Debounce search input to avoid excessive database queries
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(search);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);

  // New contact form state
  const [showNewContact, setShowNewContact] = useState(false);
  const [newNome, setNewNome] = useState('');
  const [newTelefone, setNewTelefone] = useState('');
  const [newCpf, setNewCpf] = useState('');
  const [newEndereco, setNewEndereco] = useState('');
  const [newNumero, setNewNumero] = useState('');
  const [newComplemento, setNewComplemento] = useState('');
  const [newBairro, setNewBairro] = useState('');
  const [newCidade, setNewCidade] = useState('');
  const [newUf, setNewUf] = useState('');
  const [newCep, setNewCep] = useState('');
  const [newCanal, setNewCanal] = useState('ADS');
  const [newCountry, setNewCountry] = useState('55');
  const [newInstanciaId, setNewInstanciaId] = useState<string | null>(null);
  const [newIsCliente, setNewIsCliente] = useState(false);
  const [newCepLoading, setNewCepLoading] = useState(false);
  const [newContactSaved, setNewContactSaved] = useState(false);
  const [newSubmitting, setNewSubmitting] = useState(false);
  const [phoneDuplicate, setPhoneDuplicate] = useState<any>(null);
  const [newRepresentanteId, setNewRepresentanteId] = useState<string | null>(null);
  const [repSearch, setRepSearch] = useState('');
  const [allREPs, setAllREPs] = useState<any[]>([]);

  const PER_PAGE_FETCH = 50;

  const {
    data: contatosPages,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    isLoading,
    error
  } = useInfiniteQuery({
    queryKey: ['contatos_lista', debouncedSearch, sortColumn, sortAsc, instanciaFilter, filterClientes, canaisKey],
    queryFn: async ({ pageParam = 0 }) => {
      try {
        let query = supabase.from('contatos')
          .select('id, nome, telefone, canal_origem, canal_atual, tag_kanban, created_at, cidade_uf, cidade, uf, endereco, rua, numero, complemento, bairro, cep, ja_comprou, instancia_id, instancias(nome)')
          .order(sortColumn, { ascending: sortAsc })
          .range(pageParam * PER_PAGE_FETCH, (pageParam + 1) * PER_PAGE_FETCH - 1);

        if (isRepresentante) {
          query = query.eq('representante_id', user?.id);
        }

        if (instanciaFilter !== 'all') {
          query = query.eq('instancia_id', instanciaFilter);
        }
        if (filterClientes) {
          query = query.eq('ja_comprou', true);
        }
        if (filterCanais.size > 0) {
          query = query.in('canal_atual', Array.from(filterCanais));
        }

        if (debouncedSearch) {
          const s = `%${debouncedSearch}%`;
          query = query.or(`nome.ilike.${s},telefone.ilike.${s},cpf.ilike.${s}`);
        }

        const { data, error: queryError } = await query;
        if (queryError) {
          console.error('Erro na query de contatos:', queryError);
          toast.error(`Erro ao carregar contatos: ${queryError.message}`);
          throw queryError;
        }
        return data || [];
      } catch (err: any) {
        toast.error('Erro na conexão com o banco de dados');
        throw err;
      }
    },
    getNextPageParam: (lastPage, allPages) => lastPage.length === PER_PAGE_FETCH ? allPages.length : undefined,
    initialPageParam: 0,
    staleTime: 5 * 60 * 1000,
  });

  const contatos = useMemo(() => contatosPages?.pages.flat() || [], [contatosPages]);

  // Total count - independent of pagination, updates instantly
  const { data: totalContatos } = useQuery({
    queryKey: ['contatos_total', debouncedSearch, instanciaFilter, filterClientes, canaisKey],
    queryFn: async () => {
      let query = supabase.from('contatos').select('id', { count: 'exact', head: true });
      if (isRepresentante) {
        query = query.eq('representante_id', user?.id);
      }
      if (instanciaFilter !== 'all') {
        query = query.eq('instancia_id', instanciaFilter);
      }
      if (filterClientes) {
        query = query.eq('ja_comprou', true);
      }
      if (filterCanais.size > 0) {
        query = query.in('canal_atual', Array.from(filterCanais));
      }
      if (debouncedSearch) {
        const s = `%${debouncedSearch}%`;
        query = query.or(`nome.ilike.${s},telefone.ilike.${s},cpf.ilike.${s}`);
      }
      const { count } = await query;
      return count ?? 0;
    },
    staleTime: 5 * 60 * 1000,
  });

  useEffect(() => {
    const fetchREPs = async () => {
      const { data } = await supabase.from('contatos').select('id, nome').eq('canal_atual', 'REP').order('nome');
      setAllREPs(data || []);
    };
    fetchREPs();
  }, []);

  const { data: allInstancias = [] } = useQuery({
    queryKey: ['instancias_filter'],
    queryFn: async () => {
      const { data } = await supabase.from('instancias').select('id, nome, ativo').eq('ativo', true).order('nome');
      return ((data || []) as any[]).filter((i: any) => i.nome !== 'Instancia ADMIN');
    },
    staleTime: 10 * 60 * 1000,
  });

  // Separa o número do endereço salvo no formato "Rua X, 123"
  // (mesmo formato gerado por handleCreateContact: [endereco, numero].join(', '))
  const parseEnderecoNumero = (full: string | null | undefined): { endereco: string; numero: string } => {
    if (!full) return { endereco: '', numero: '' };
    const m = full.match(/^(.+),\s*(\d+[A-Za-z]?|s\/?n|s\.?n\.?)\s*$/i);
    if (m) return { endereco: m[1].trim(), numero: m[2].trim() };
    return { endereco: full.trim(), numero: '' };
  };

  const openContact = async (c: any) => {
    // Fetch full contact data from DB to ensure all fields are present
    const { data: fullContact } = await supabase.from('contatos')
      .select('*')
      .eq('id', c.id)
      .single();
    const contact = fullContact || c;
    setSelected(contact);
    setEditNome(contact.nome || '');
    const det = detectCountry(contact.telefone);
    setEditCountry(det.code);
    setEditTelefone(det.code === '55' ? applyPhoneMask(det.national) : applyIntlMask(det.national));
    setEditCanalAtual(contact.canal_atual || contact.canal_origem || 'BASE');
    setEditRepresentanteId(contact.representante_id || null);
    setEditInstanciaId(contact.instancia_id || null);
    setEditIsCliente(!!contact.ja_comprou);
    setEditPhoneDuplicate(null);
    // Prioriza colunas separadas (fonte de verdade nova).
    // Fallback ao split de 'endereco' pra contatos legacy ainda não migrados.
    if ((contact as any).rua || (contact as any).numero) {
      setEditEndereco((contact as any).rua || '');
      setEditNumero((contact as any).numero || '');
    } else {
      const { endereco: enderecoRua, numero: enderecoNumero } = parseEnderecoNumero(contact.endereco);
      setEditEndereco(enderecoRua);
      setEditNumero(enderecoNumero);
    }
    setEditComplemento(contact.complemento || '');
    setEditBairro(contact.bairro || '');
    if (contact.cidade) {
      setEditCidade(contact.cidade);
    } else if (contact.cidade_uf) {
      const parts = contact.cidade_uf.split('/');
      setEditCidade(parts[0]?.trim() || '');
    } else {
      setEditCidade('');
    }
    if (contact.uf) {
      setEditUf(contact.uf);
    } else if (contact.cidade_uf) {
      const parts = contact.cidade_uf.split('/');
      setEditUf(parts[1]?.trim() || '');
    } else {
      setEditUf('');
    }
    setEditCep(contact.cep || '');
    setEditCpf(contact.cpf || '');
    setEditObs(contact.observacao || '');
    const { data } = await supabase.from('pedidos')
      .select('id, data, valor, status_pedido, produto, quantidade, canal, order_number')
      .eq('contato_id', c.id)
      .order('data', { ascending: false });
    setContactPedidos(data || []);
  };

  const checkEditPhoneDuplicate = async (phone: string) => {
    setEditPhoneDuplicate(null);
    if (!selected) return;
    if (phone.length < 8) return;
    const { data } = await supabase.from('contatos')
      .select('id, nome, telefone')
      .eq('telefone', phone)
      .neq('id', selected.id)
      .limit(1);
    if (data && data.length > 0) setEditPhoneDuplicate(data[0]);
  };

  const applyCepMask = (val: string) => {
    const num = val.replace(/\D/g, '');
    if (!num) return '';
    if (num.length <= 5) return num;
    return `${num.slice(0, 5)}-${num.slice(5, 8)}`;
  };

  // Remove non-dígitos e strip do código país "55" se presente (12-13 dígitos = país BR embutido).
  // Exemplos:
  //   "5511965285486" (13d) → "11965285486" (DDD 11 + mobile)
  //   "5511965285"    (10d, DDD 55 RS landline) → "5511965285"  (mantém — DDD válido)
  //   "11965285486"   (11d, sem país) → "11965285486"
  const normalizePhoneDigits = (raw: string): string => {
    let d = raw.replace(/\D/g, '');
    if ((d.length === 12 || d.length === 13) && d.startsWith('55')) d = d.slice(2);
    return d;
  };

  const applyPhoneMask = (val: string) => {
    const num = normalizePhoneDigits(val);
    if (!num) return '';
    if (num.length <= 2) return `(${num}`;
    if (num.length <= 7) return `(${num.slice(0, 2)}) ${num.slice(2)}`;
    return `(${num.slice(0, 2)}) ${num.slice(2, 7)}-${num.slice(7, 11)}`;
  };

  // Monta o número que vai pro banco/Evolution.
  //  - BR (55): nacional SEM 55 (Evolution completa o 55 no envio — convenção
  //    existente de toda a base).
  //  - Estrangeiro: internacional COMPLETO (DDI + nacional), enviado como está
  //    pro Evolution (não leva 55). Sobrevive ao trigger normalize_telefone_br.
  const buildStoredNumber = (countryCode: string, national: string): string | null => {
    const nat = (national || '').replace(/\D/g, '');
    if (!nat) return null;
    if (countryCode === '55') return normalizePhoneDigits(nat);
    return nat.startsWith(countryCode) ? nat : countryCode + nat;
  };

  const applyCpfMask = (val: string) => {
    const num = val.replace(/\D/g, '');
    if (!num) return '';
    if (num.length <= 3) return num;
    if (num.length <= 6) return `${num.slice(0, 3)}.${num.slice(3)}`;
    if (num.length <= 9) return `${num.slice(0, 3)}.${num.slice(3, 6)}.${num.slice(6)}`;
    return `${num.slice(0, 3)}.${num.slice(3, 6)}.${num.slice(6, 9)}-${num.slice(9, 11)}`;
  };

  const lookupCep = async (cepRaw: string, target: 'edit' | 'new') => {
    const num = cepRaw.replace(/\D/g, '');
    if (num.length !== 8) return;
    if (target === 'edit') setCepLoading(true);
    else setNewCepLoading(true);
    try {
      const res = await fetch(`https://viacep.com.br/ws/${num}/json/`);
      const data = await res.json();
      if (!data.erro) {
        if (target === 'edit') {
          if (data.logradouro) setEditEndereco(data.logradouro);
          if (data.bairro) setEditBairro(data.bairro);
          if (data.localidade) setEditCidade(data.localidade);
          if (data.uf) setEditUf(data.uf);
        } else {
          if (data.logradouro) setNewEndereco(data.logradouro);
          if (data.bairro) setNewBairro(data.bairro);
          if (data.localidade) setNewCidade(data.localidade);
          if (data.uf) setNewUf(data.uf);
        }
      }
    } catch {
      // CEP not found
    } finally {
      if (target === 'edit') setCepLoading(false);
      else setNewCepLoading(false);
    }
  };

  const checkPhoneDuplicate = async (phone: string) => {
    setPhoneDuplicate(null);
    if (phone.length < 8) return;
    const { data } = await supabase.from('contatos').select('id, nome, telefone').eq('telefone', phone).limit(1);
    if (data && data.length > 0) setPhoneDuplicate(data[0]);
  };

  const saveContact = async () => {
    if (!selected) return;
    if (!editNome.trim()) { toast.error('Nome é obrigatório'); return; }
    if (editCanalAtual === 'C-REP' && !editRepresentanteId) {
      toast.error('Selecione um representante para cliente C-REP');
      return;
    }

    // Fonte de verdade: rua + numero SEPARADOS. Trigger no DB regenera
    // 'endereco' e 'rua_numero' automaticamente pra compat com RPCs antigas.
    const cidadeUfString = [editCidade, editUf].filter(Boolean).join('/');

    const changes: any = {};
    if (editNome !== (selected.nome || '')) changes.nome = editNome.trim();
    // Compara o número montado (DDI + nacional pra estrangeiro; nacional pra BR)
    // com o que está salvo — só grava se realmente mudou.
    const builtTel = buildStoredNumber(editCountry, editTelefone);
    if ((builtTel || '') !== (selected.telefone || '')) {
      changes.telefone = builtTel;
    }
    if (editCanalAtual !== (selected.canal_atual || '')) changes.canal_atual = editCanalAtual;
    if (editRepresentanteId !== (selected.representante_id || null)) {
      changes.representante_id = editCanalAtual === 'C-REP' ? editRepresentanteId : null;
    }
    if (editEndereco !== ((selected as any).rua || '')) changes.rua = editEndereco || null;
    if (editNumero !== ((selected as any).numero || '')) changes.numero = editNumero || null;
    if (editComplemento !== (selected.complemento || '')) changes.complemento = editComplemento || null;
    if (editBairro !== (selected.bairro || '')) changes.bairro = editBairro || null;
    changes.cidade_uf = cidadeUfString || null;
    if (editCidade) changes.cidade = editCidade;
    if (editUf) changes.uf = editUf;
    if (editCep !== (selected.cep || '')) changes.cep = editCep || null;
    if (editCpf !== (selected.cpf || '')) changes.cpf = editCpf || null;
    if (editObs !== (selected.observacao || '')) changes.observacao = editObs;

    // Instância: só grava se mudou. UI trava o dropdown quando há instância
    // atribuída + histórico de pedido; guarda defensiva aqui também.
    const hasPedidos = contactPedidos.length > 0;
    if (editInstanciaId !== (selected.instancia_id || null)) {
      if (selected.instancia_id && hasPedidos) {
        toast.error('Instância travada: contato com histórico de pedido');
        return;
      }
      changes.instancia_id = editInstanciaId || null;
    }

    // Cliente (ja_comprou): não pode DESMARCAR se tiver histórico de pedido.
    if (editIsCliente !== !!selected.ja_comprou) {
      if (!editIsCliente && hasPedidos) {
        toast.error('Contato com histórico de pedido não pode deixar de ser Cliente');
        return;
      }
      changes.ja_comprou = editIsCliente;
      // Marca 'cliente' ao ativar; ao desativar (sem pedido) volta a contato neutro.
      changes.ultima_interacao = editIsCliente ? 'cliente' : null;
    }

    if (Object.keys(changes).length === 0) { toast.info('Nenhuma alteração'); return; }
    const { error } = await supabase.from('contatos').update(changes).eq('id', selected.id);
    if (error) { toast.error('Erro ao salvar: ' + error.message); console.error(error); return; }

    await supabase.from('log_atividades').insert({
      usuario: profile?.nome || 'Desconhecido', acao: 'Editou contato', tabela_afetada: 'contatos', registro_id: selected.id, detalhe: selected.nome,
    });
    toast.success('Contato atualizado!');
    // Mantém o 'selected' coerente (relock imediato se instância virou fixa).
    setSelected((prev: any) => prev ? { ...prev, ...changes } : prev);
    queryClient.invalidateQueries({ queryKey: ['contatos_lista'] });
    queryClient.invalidateQueries({ queryKey: ['contatos_total'] });
    if (selected.instancia_id) queryClient.invalidateQueries({ queryKey: ['instancia_metricas', selected.instancia_id] });
    if (editInstanciaId && editInstanciaId !== selected.instancia_id) {
      queryClient.invalidateQueries({ queryKey: ['instancia_metricas', editInstanciaId] });
    }
  };

  const handleCreateContact = async () => {
    if (!newNome.trim()) { toast.error('Nome é obrigatório'); return; }
    
    if (newCanal === 'C-REP' && !newRepresentanteId) {
      toast.error('Selecione um representante para cliente C-REP');
      return;
    }
    
    setNewSubmitting(true);
    try {
      const enderecoFull = [newEndereco, newNumero].filter(Boolean).join(', ');
      const cidadeUfString = [newCidade, newUf].filter(Boolean).join('/');

      const body = {
        p_nome: newNome,
        p_canal_origem: newCanal,
        p_telefone: buildStoredNumber(newCountry, newTelefone),
        p_cpf: newCpf || null,
        p_endereco: enderecoFull || null,
        p_complemento: newComplemento || null,
        p_bairro: newBairro || null,
        p_cidade_uf: cidadeUfString || null,
        p_cep: newCep || null,
        p_cidade: newCidade || null,
        p_uf: newUf || null,
        p_representante_id: newCanal === 'C-REP' ? newRepresentanteId : null,
        p_instancia_id: newInstanciaId || null,
        p_ja_comprou: newIsCliente,
      };

      const { error: rpcError } = await supabase.rpc('create_contato' as any, body);
      if (rpcError) {
        console.error('RPC error:', rpcError);
        toast.error('Erro ao salvar: ' + rpcError.message);
        setNewSubmitting(false);
        return;
      }

      // Revalida lista + total + métricas por instância (Clientes) pra refletir
      // o novo contato/cliente em todas as visões.
      queryClient.invalidateQueries({ queryKey: ['contatos_lista'] });
      queryClient.invalidateQueries({ queryKey: ['contatos_total'] });
      if (newInstanciaId) {
        queryClient.invalidateQueries({ queryKey: ['instancia_metricas', newInstanciaId] });
      }

      toast.success(newIsCliente ? 'Cliente criado!' : 'Contato criado!');
      resetNewContactForm();
    } catch (err: any) {
      toast.error('Erro ao salvar contato: ' + (err.message || 'Erro desconhecido'));
      console.error(err);
    } finally {
      setNewSubmitting(false);
    }
  };

  const resetNewContactForm = () => {
    setShowNewContact(false);
    setNewNome(''); setNewTelefone(''); setNewCpf(''); setNewEndereco('');
    setNewNumero(''); setNewComplemento(''); setNewBairro(''); setNewCidade('');
    setNewUf(''); setNewCep(''); setNewCanal('ADS'); setNewContactSaved(false);
    setPhoneDuplicate(null); setNewRepresentanteId(null); setRepSearch('');
    setNewInstanciaId(null); setNewIsCliente(false); setNewCountry('55');
  };

  const copyPhone = (phone: string) => { 
    copyToClipboard(phone).then(success => {
      if (success) toast.success('Número Copiado!');
      else toast.error('Falha ao copiar');
    });
  };

  const copyAddress = (c: any) => {
    const cidade = c.cidade || '';
    const uf = c.uf || '';
    const cidadeUf = cidade && uf ? `${cidade}/${uf}` : c.cidade_uf || '';
    const parts = [
      c.endereco,
      c.complemento ? `— ${c.complemento}` : null,
      c.bairro ? `Bairro: ${c.bairro}` : null,
      cidadeUf ? `Cidade/UF: ${cidadeUf}` : null,
      c.cep ? `CEP: ${c.cep}` : null,
    ].filter(Boolean).join('\n');
    copyToClipboard(parts || 'Endereço não informado').then(success => {
      if (success) toast.success('Endereço Copiado!');
      else toast.error('Falha ao copiar');
    });
  };

  // Export no formato de lista de clientes do Meta Ads (Custom Audience).
  //  - Colunas fn/ln/phone = identificadores que o Meta reconhece e auto-mapeia.
  //  - phone em E.164: só dígitos COM código do país. BR nacional (10 díg fixo
  //    ou 11 com 9º dígito) ganha o 55; estrangeiro já vem internacional completo.
  //  - Sem coluna de data. Campos entre aspas (nomes com vírgula/acento seguros).
  const exportCSV = () => {
    const toE164 = (t: string | null | undefined) => {
      const nd = (t || '').replace(/\D/g, '');
      if (!nd) return '';
      return (nd.length === 10 || (nd.length === 11 && nd.charAt(2) === '9')) ? '55' + nd : nd;
    };
    const esc = (v: any) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const rows = [['fn', 'ln', 'phone']];
    contatos.forEach(c => {
      const parts = (c.nome || '').trim().split(/\s+/).filter(Boolean);
      rows.push([parts[0] || '', parts.slice(1).join(' '), toE164(c.telefone)]);
    });
    const csv = rows.map(r => r.map(esc).join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = 'contatos-meta-ads.csv'; a.click();
  };

  const toggleSelect = (id: string) => {
    const next = new Set(selectedIds);
    if (next.has(id)) next.delete(id); else next.add(id);
    setSelectedIds(next);
  };

  const openMerge = () => {
    const selected2 = contatos.filter(c => selectedIds.has(c.id));
    if (selected2.length !== 2) { toast.error('Selecione exatamente 2 contatos'); return; }
    setMergeContacts(selected2.sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()));
    setShowMerge(true);
  };

  const handleMerge = async () => {
    const [winner, loser] = mergeContacts;
    await supabase.from('pedidos').update({ contato_id: winner.id }).eq('contato_id', loser.id);
    await supabase.from('lancamentos_socios').update({ contato_id: winner.id }).eq('contato_id', loser.id);
    await supabase.from('follow_up').update({ contato_id: winner.id }).eq('contato_id', loser.id);
    await supabase.from('contatos').delete().eq('id', loser.id);
    await supabase.from('log_atividades').insert({
      usuario: profile?.nome || 'Desconhecido', acao: 'Mesclou contatos', tabela_afetada: 'contatos', registro_id: winner.id,
      detalhe: `${winner.nome} ← ${loser.nome}`,
    });
    toast.success('Contatos mesclados com sucesso');
    setShowMerge(false);
    setSelectedIds(new Set());
    queryClient.invalidateQueries({ queryKey: ['contatos_lista'] });
  };

  if (isLoading) return <Skeleton className="h-[500px]" />;

  // Regras de trava na edição:
  //  - Instância travada só quando JÁ tem instância atribuída E há histórico de
  //    pedido. Sem instância OU sem pedido → liberada (rebalanceamento temporário).
  //  - Cliente: não pode DESMARCAR se há histórico de pedido (switch desabilita
  //    quando está ligado + tem pedido). Ligar é sempre permitido.
  const editHasPedidos = contactPedidos.length > 0;
  const editInstanciaLocked = !!selected?.instancia_id && editHasPedidos;
  const editClienteLockedOn = editIsCliente && editHasPedidos;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex flex-col">
          <h1 className="text-2xl font-bold">Contatos</h1>
          <span className="text-xs text-muted-foreground">
            {totalContatos !== undefined
              ? `${contatos.length.toLocaleString('pt-BR')} de ${totalContatos.toLocaleString('pt-BR')} contatos`
              : `${contatos.length} contatos carregados`}
          </span>
        </div>
        <div className="flex gap-2">
          {selectedIds.size === 2 && (
            <Button variant="outline" size="sm" onClick={openMerge}><Merge className="w-4 h-4 mr-1" /> Mesclar selecionados</Button>
          )}
          <Button variant="outline" size="sm" onClick={exportCSV}><Download className="w-4 h-4 mr-1" /> CSV</Button>
        </div>
      </div>
      <div className="flex flex-col gap-2">
        <div className="flex flex-col sm:flex-row gap-2 sm:items-center">
          <Input placeholder="Buscar por nome ou telefone" value={search} onChange={e => setSearch(e.target.value)} className="max-w-sm" />
          <Select value={instanciaFilter} onValueChange={setInstanciaFilter}>
            <SelectTrigger className="w-full sm:w-[200px]">
              <SelectValue placeholder="Filtrar..." />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos Contatos</SelectItem>
              {allInstancias.map((i: any) => (
                <SelectItem key={i.id} value={i.id}>Instância {i.nome}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="flex flex-wrap gap-x-4 gap-y-2 items-center text-sm">
          <label className="flex items-center gap-2 cursor-pointer">
            <Checkbox checked={filterClientes} onCheckedChange={(v) => setFilterClientes(!!v)} />
            <span>Clientes</span>
          </label>
          <span className="text-xs text-muted-foreground">|</span>
          {(['ADS', 'BASE', 'REP', 'C-REP'] as const).map(canal => (
            <label key={canal} className="flex items-center gap-2 cursor-pointer">
              <Checkbox checked={filterCanais.has(canal)} onCheckedChange={() => toggleCanal(canal)} />
              <span>{canal}</span>
            </label>
          ))}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto space-y-2 pr-1 custom-scrollbar">
        {isLoading && contatos.length === 0 ? (
          Array(8).fill(0).map((_, i) => <Skeleton key={i} className="h-20 w-full rounded-xl" />)
        ) : contatos.length === 0 ? (
          <div className="text-center py-12 text-muted-foreground bg-muted/20 rounded-2xl border-2 border-dashed">
            <p>Nenhum contato encontrado</p>
            {search && <Button variant="link" onClick={() => setSearch('')}>Limpar busca</Button>}
          </div>
        ) : (
          <div className="space-y-2">
            <div className="hidden md:block">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b font-bold">
                    <th className="text-left py-2 cursor-pointer select-none hover:bg-muted/50 rounded" onClick={() => toggleSort('nome')}>
                      Nome {sortColumn === 'nome' ? (sortAsc ? '↑' : '↓') : '↑↓'}
                    </th>
                    <th className="text-left py-2">Número</th>
                    <th className="text-left py-2">Canal</th>
                    <th className="text-left py-2">Instância</th>
                    <th className="text-left py-2">📍</th>
                    <th className="text-left py-2 cursor-pointer select-none hover:bg-muted/50 rounded" onClick={() => toggleSort('created_at')}>
                      Data Cadastro {sortColumn === 'created_at' ? (sortAsc ? '↑' : '↓') : '↑↓'}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {contatos.map((c) => (
                    <tr key={c.id} className="border-b border-border/50 hover:bg-muted/50 cursor-pointer" onClick={() => openContact(c)}>
                      <td className="py-2 font-medium">
                        {c.nome} {c.tag_kanban === 'VIP' && <Trophy className="inline w-3 h-3 text-sf-gold" />}
                      </td>
                      <td className="py-2 text-muted-foreground">{c.telefone || '—'}</td>
                      <td className="py-2">
                        <Badge variant="outline" className="text-[10px]">{c.canal_atual || c.canal_origem || '—'}</Badge>
                      </td>
                      <td className="py-2 text-xs text-muted-foreground">
                        {c.instancias?.nome || '—'}
                      </td>
                      <td className="py-2" onClick={e => e.stopPropagation()}>
                        <Popover>
                          <PopoverTrigger asChild>
                            <Button variant="ghost" size="icon" className="h-7 w-7">
                              <MapPin className={cn("w-4 h-4", (c.endereco || c.cidade_uf) ? "text-primary" : "text-muted-foreground opacity-40")} />
                            </Button>
                          </PopoverTrigger>
                          <PopoverContent className="w-72 p-3 text-sm space-y-1">
                            <p className="font-bold text-xs text-muted-foreground mb-2 uppercase tracking-wider">Endereço</p>
                            <p><strong>Endereço:</strong> {c.endereco || '—'}{c.complemento ? ` — ${c.complemento}` : ''}</p>
                            <p><strong>Bairro:</strong> {c.bairro || '—'}</p>
                            <p><strong>Cidade/UF:</strong> {c.cidade_uf || '—'}</p>
                            <p><strong>CEP:</strong> {c.cep || '—'}</p>
                            <Button size="sm" variant="outline" className="w-full mt-2 min-h-[44px]" onClick={() => copyAddress(c)}>
                              <Copy className="w-3 h-3 mr-1" /> Copiar Endereço
                            </Button>
                          </PopoverContent>
                        </Popover>
                      </td>
                      <td className="py-2 text-xs text-muted-foreground">{formatDateShort(c.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile Cards */}
            <div className="md:hidden space-y-2">
              {contatos.map((c) => (
                <div key={c.id} className="relative p-3 border rounded-xl hover:bg-muted/30 cursor-pointer" onClick={() => openContact(c)}>
                  {c.instancias?.nome && (
                    <span className="absolute top-1 right-2 text-[9px] text-muted-foreground/70 font-mono">
                      {c.instancias.nome}
                    </span>
                  )}
                  <div className="flex justify-between items-start">
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <span className="font-bold">{c.nome}</span>
                        <Badge variant="outline" className="text-[10px]">{c.canal_atual || c.canal_origem}</Badge>
                      </div>
                      <div className="text-xs text-muted-foreground mt-1">{c.telefone}</div>
                    </div>
                    {(c.endereco || c.cidade_uf) && (
                      <div onClick={e => e.stopPropagation()}>
                        <Popover>
                          <PopoverTrigger asChild>
                            <Button variant="ghost" size="icon" className="h-8 w-8">
                              <MapPin className={cn("w-4 h-4", (c.endereco || c.cidade_uf) ? "text-primary" : "text-muted-foreground opacity-40")} />
                            </Button>
                          </PopoverTrigger>
                          <PopoverContent className="w-72 p-3 text-sm space-y-1">
                            <p className="font-bold text-xs text-muted-foreground mb-2 uppercase tracking-wider">Endereço</p>
                            <p><strong>Endereço:</strong> {c.endereco || '—'}{c.complemento ? ` — ${c.complemento}` : ''}</p>
                            <p><strong>Bairro:</strong> {c.bairro || '—'}</p>
                            <p><strong>Cidade/UF:</strong> {c.cidade_uf || '—'}</p>
                            <p><strong>CEP:</strong> {c.cep || '—'}</p>
                            <Button size="sm" variant="outline" className="w-full mt-2 min-h-[44px]" onClick={() => copyAddress(c)}>
                              <Copy className="w-3 h-3 mr-1" /> Copiar Endereço
                            </Button>
                          </PopoverContent>
                        </Popover>
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>

            {hasNextPage && (
              <Button 
                variant="ghost" 
                className="w-full text-xs text-muted-foreground py-4"
                onClick={() => fetchNextPage()}
                disabled={isFetchingNextPage}
              >
                {isFetchingNextPage ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : null}
                Carregar mais...
              </Button>
            )}
          </div>
        )}
      </div>

      {/* FAB - Add Contact */}
      <Button onClick={() => { resetNewContactForm(); setShowNewContact(true); }} className="fixed bottom-6 right-6 rounded-full h-14 w-14 shadow-lg bg-sf-green hover:bg-sf-green/90 text-primary-foreground z-50" size="icon">
        <Plus className="w-6 h-6" />
      </Button>

      {/* New Contact Dialog */}
      <Dialog open={showNewContact} onOpenChange={() => resetNewContactForm()}>
        <DialogContent className={cn(
          isMobile ? 'fixed inset-0 max-w-none w-full h-full rounded-none m-0 translate-x-0 translate-y-0 top-0 left-0 flex flex-col' : 'max-w-md max-h-[80vh] overflow-y-auto'
        )}>
          <DialogHeader><DialogTitle>Novo Contato</DialogTitle></DialogHeader>
          <div className={cn('space-y-3', isMobile ? 'flex-1 overflow-y-auto pb-20 px-1' : '')}>
              <>
                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Canal de Origem</Label>
                  <Select value={newCanal} onValueChange={setNewCanal}>
                    <SelectTrigger className="min-h-[44px]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ADS">ADS</SelectItem>
                      <SelectItem value="BASE">BASE</SelectItem>
                      <SelectItem value="REP">REP</SelectItem>
                      <SelectItem value="C-REP">C-REP</SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                {newCanal === 'C-REP' && (
                  <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground uppercase tracking-wide">Representante Responsável</Label>
                    <Select value={newRepresentanteId || ''} onValueChange={setNewRepresentanteId}>
                      <SelectTrigger className="min-h-[44px]">
                        <SelectValue placeholder="Selecionar..." />
                      </SelectTrigger>
                      <SelectContent>
                        {allREPs.map(r => <SelectItem key={r.id} value={r.id}>{r.nome}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                )}

                <div>
                  <Label className="text-xs text-muted-foreground uppercase tracking-wide">Instância</Label>
                  <Select value={newInstanciaId || 'none'} onValueChange={(v) => setNewInstanciaId(v === 'none' ? null : v)}>
                    <SelectTrigger className="min-h-[44px]"><SelectValue placeholder="Sem instância" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">Sem instância</SelectItem>
                      {allInstancias.map((i: any) => (
                        <SelectItem key={i.id} value={i.id}>Instância {i.nome}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                {/* Cliente on/off — marca ja_comprou=true (sem histórico de pedido) */}
                <label className="flex items-center justify-between gap-3 rounded-md border px-3 py-2 min-h-[44px] cursor-pointer">
                  <div className="flex flex-col">
                    <span className="text-sm font-medium">Cliente</span>
                    <span className="text-[11px] text-muted-foreground">Marca como já comprou (sem histórico de pedido)</span>
                  </div>
                  <Switch checked={newIsCliente} onCheckedChange={setNewIsCliente} />
                </label>

                <Input placeholder="Nome *" value={newNome} onChange={e => setNewNome(e.target.value)} className="min-h-[44px]" />
                <Input placeholder="CPF" value={newCpf} onChange={e => setNewCpf(e.target.value)} className="min-h-[44px]" />
                <div className="flex gap-2">
                  <Select
                    value={newCountry}
                    onValueChange={(v) => {
                      const digits = newTelefone.replace(/\D/g, '');
                      setNewCountry(v);
                      setNewTelefone(v === '55' ? applyPhoneMask(digits) : applyIntlMask(digits));
                    }}
                  >
                    <SelectTrigger className="min-h-[44px] w-[120px] shrink-0"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {COUNTRIES.map(c => (
                        <SelectItem key={c.code} value={c.code}>{c.flag} +{c.code}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Input
                    placeholder={newCountry === '55'
                      ? (newCanal === 'C-REP' ? '(XX) XXXXX-XXXX Opcional' : '(XX) XXXXX-XXXX')
                      : 'Número com DDD (só dígitos)'}
                    value={newTelefone}
                    onChange={e => {
                      const masked = newCountry === '55' ? applyPhoneMask(e.target.value) : applyIntlMask(e.target.value);
                      setNewTelefone(masked);
                      checkPhoneDuplicate(buildStoredNumber(newCountry, masked) || '');
                    }}
                    className="min-h-[44px] flex-1"
                  />
                </div>
                <Input placeholder="Endereço (Rua)" value={newEndereco} onChange={e => setNewEndereco(e.target.value)} className="min-h-[44px]" />
                <Input placeholder="Número" value={newNumero} onChange={e => setNewNumero(e.target.value)} className="min-h-[44px]" />
                {/* CEP right below Número */}
                <div className="relative">
                  <Input
                    placeholder="CEP (XXXXX-XXX)"
                    value={newCep}
                    onChange={e => {
                      const masked = applyCepMask(e.target.value);
                      setNewCep(masked);
                      if (masked.replace(/\D/g, '').length === 8) {
                        lookupCep(masked, 'new');
                      }
                    }}
                    className="min-h-[44px]"
                  />
                  {newCepLoading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-muted-foreground" />}
                </div>
                <Input placeholder="Complemento (opcional)" value={newComplemento} onChange={e => setNewComplemento(e.target.value)} className="min-h-[44px]" />
                <Input placeholder="Bairro" value={newBairro} onChange={e => setNewBairro(e.target.value)} className="min-h-[44px]" />
                {/* Cidade and UF separate */}
                <div className="flex gap-2">
                  <Input placeholder="Cidade" value={newCidade} onChange={e => setNewCidade(e.target.value)} className="min-h-[44px] flex-1" />
                  <Select value={newUf} onValueChange={setNewUf}>
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
                <div className="flex gap-2 mt-2">
                  <Button
                    className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px] flex-1"
                    disabled={newSubmitting}
                    onClick={handleCreateContact}
                  >
                    {newSubmitting ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <Check className="w-4 h-4 mr-1" />} 
                    {newSubmitting ? 'Salvando...' : 'Salvar'}
                  </Button>
                </div>
              </>
          </div>

          {isMobile && (
            <div className="fixed bottom-0 left-0 right-0 p-4 bg-background border-t border-border z-50">
              <Button
                className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px]"
                disabled={newSubmitting}
                onClick={handleCreateContact}
              >
                {newSubmitting ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <Check className="w-4 h-4 mr-1" />} 
                {newSubmitting ? 'Salvando...' : 'Salvar'}
              </Button>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Contact detail popup */}
      <Dialog open={!!selected} onOpenChange={() => setSelected(null)}>
        <DialogContent className={cn(
          isMobile ? 'fixed inset-0 max-w-none w-full h-full rounded-none m-0 translate-x-0 translate-y-0 top-0 left-0 flex flex-col' : 'max-w-md max-h-[80vh] overflow-y-auto'
        )}>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {selected?.nome}
              {selected?.tag_kanban === 'VIP' && <Badge className="bg-sf-gold">VIP</Badge>}
            </DialogTitle>
          </DialogHeader>
          <div className={cn('space-y-3 text-sm', isMobile ? 'flex-1 overflow-y-auto pb-20 px-1' : '')}>
            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Canal Atual</Label>
              <Select value={editCanalAtual} onValueChange={setEditCanalAtual}>
                <SelectTrigger className="min-h-[44px] mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ADS">ADS</SelectItem>
                  <SelectItem value="BASE">BASE</SelectItem>
                  <SelectItem value="REP">REP</SelectItem>
                  <SelectItem value="C-REP">C-REP</SelectItem>
                  <SelectItem value="INTERNO">INTERNO</SelectItem>
                </SelectContent>
              </Select>
              {selected?.canal_origem && selected.canal_origem !== editCanalAtual && (
                <p className="text-[11px] text-muted-foreground mt-1 italic">Origem: {selected.canal_origem} (não editável)</p>
              )}
            </div>

            {editCanalAtual === 'C-REP' && (
              <div className="space-y-1">
                <Label className="text-xs text-muted-foreground uppercase tracking-wide">Representante Responsável</Label>
                <Select value={editRepresentanteId || ''} onValueChange={setEditRepresentanteId}>
                  <SelectTrigger className="min-h-[44px]">
                    <SelectValue placeholder="Selecionar..." />
                  </SelectTrigger>
                  <SelectContent>
                    {allREPs.map(r => <SelectItem key={r.id} value={r.id}>{r.nome}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            )}

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Instância</Label>
              <Select value={editInstanciaId || 'none'} onValueChange={(v) => setEditInstanciaId(v === 'none' ? null : v)} disabled={editInstanciaLocked}>
                <SelectTrigger className="min-h-[44px] mt-1"><SelectValue placeholder="Sem instância" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Sem instância</SelectItem>
                  {allInstancias.map((i: any) => (
                    <SelectItem key={i.id} value={i.id}>Instância {i.nome}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {editInstanciaLocked && (
                <p className="text-[11px] text-muted-foreground mt-1 italic">Travado: instância atribuída + histórico de pedido.</p>
              )}
            </div>

            {/* Cliente on/off — só desmarca se NÃO houver histórico de pedido */}
            <label className="flex items-center justify-between gap-3 rounded-md border px-3 py-2 min-h-[44px] cursor-pointer">
              <div className="flex flex-col">
                <span className="text-sm font-medium">Cliente</span>
                <span className="text-[11px] text-muted-foreground">
                  {editClienteLockedOn ? 'Com histórico de pedido — não pode desmarcar' : 'Marca como já comprou'}
                </span>
              </div>
              <Switch checked={editIsCliente} onCheckedChange={setEditIsCliente} disabled={editClienteLockedOn} />
            </label>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Nome</Label>
              <Input value={editNome} onChange={e => setEditNome(e.target.value)} className="mt-1 min-h-[44px]" placeholder="Nome *" />
            </div>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">CPF</Label>
              <Input value={editCpf} onChange={e => setEditCpf(applyCpfMask(e.target.value))} className="mt-1 min-h-[44px]" placeholder="XXX.XXX.XXX-XX" />
            </div>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Telefone</Label>
              <div className="flex gap-2 mt-1 items-stretch">
                <Select
                  value={editCountry}
                  onValueChange={(v) => {
                    const digits = editTelefone.replace(/\D/g, '');
                    setEditCountry(v);
                    setEditTelefone(v === '55' ? applyPhoneMask(digits) : applyIntlMask(digits));
                  }}
                >
                  <SelectTrigger className="min-h-[44px] w-[120px] shrink-0"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {COUNTRIES.map(c => (
                      <SelectItem key={c.code} value={c.code}>{c.flag} +{c.code}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Input
                  placeholder={editCountry === '55'
                    ? (editCanalAtual === 'C-REP' ? '(XX) XXXXX-XXXX Opcional' : '(XX) XXXXX-XXXX')
                    : 'Número com DDD (só dígitos)'}
                  value={editTelefone}
                  onChange={e => {
                    const masked = editCountry === '55' ? applyPhoneMask(e.target.value) : applyIntlMask(e.target.value);
                    setEditTelefone(masked);
                    checkEditPhoneDuplicate(buildStoredNumber(editCountry, masked) || '');
                  }}
                  className="min-h-[44px] flex-1"
                />
                {selected?.telefone && (
                  <Button variant="ghost" size="icon" className="h-[44px] w-[44px]" onClick={() => copyPhone(selected?.telefone || '')}>
                    <Copy className="w-4 h-4" />
                  </Button>
                )}
              </div>
              {editPhoneDuplicate && (
                <div className="bg-amber-50 dark:bg-amber-950 border border-amber-300 dark:border-amber-700 rounded p-2 text-xs mt-1">
                  <p className="text-amber-700 dark:text-amber-300">⚠️ Este número já está cadastrado para <strong>{editPhoneDuplicate.nome}</strong>.</p>
                </div>
              )}
            </div>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Endereço (Rua)</Label>
              <Input value={editEndereco} onChange={e => setEditEndereco(e.target.value)} className="mt-1 min-h-[44px]" placeholder="Rua / Avenida..." />
            </div>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Número</Label>
              <Input value={editNumero} onChange={e => setEditNumero(e.target.value)} className="mt-1 min-h-[44px]" placeholder="Número" />
            </div>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">CEP</Label>
              <div className="relative">
                <Input
                  value={editCep}
                  onChange={e => {
                    const masked = applyCepMask(e.target.value);
                    setEditCep(masked);
                    if (masked.replace(/\D/g, '').length === 8) {
                      lookupCep(masked, 'edit');
                    }
                  }}
                  className="mt-1 min-h-[44px]"
                  placeholder="XXXXX-XXX"
                />
                {cepLoading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-muted-foreground" />}
              </div>
            </div>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Complemento (opcional)</Label>
              <Input value={editComplemento} onChange={e => setEditComplemento(e.target.value)} className="mt-1 min-h-[44px]" placeholder="Apto, Bloco..." />
            </div>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Bairro</Label>
              <Input value={editBairro} onChange={e => setEditBairro(e.target.value)} className="mt-1 min-h-[44px]" />
            </div>

            <div className="flex gap-2">
              <div className="flex-1">
                <Label className="text-xs text-muted-foreground uppercase tracking-wide">Cidade</Label>
                <Input value={editCidade} onChange={e => setEditCidade(e.target.value)} className="mt-1 min-h-[44px]" placeholder="Cidade" />
              </div>
              <div className="w-24">
                <Label className="text-xs text-muted-foreground uppercase tracking-wide">UF</Label>
                <Select value={editUf} onValueChange={setEditUf}>
                  <SelectTrigger className="mt-1 min-h-[44px]">
                    <SelectValue placeholder="UF" />
                  </SelectTrigger>
                  <SelectContent>
                    {UF_OPTIONS.map(uf => (
                      <SelectItem key={uf} value={uf}>{uf}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div>
              <Label className="text-xs text-muted-foreground uppercase tracking-wide">Observação</Label>
              <Textarea value={editObs} onChange={e => setEditObs(e.target.value)} className="mt-1" rows={3} />
            </div>

            <Button onClick={saveContact} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground min-h-[44px]">
              <Check className="w-4 h-4 mr-1" /> Salvar
            </Button>

            <h4 className="font-bold mt-4">Histórico de Pedidos</h4>
            {contactPedidos.length === 0 ? <p className="text-muted-foreground">Nenhum pedido</p> : (
              contactPedidos.map(p => {
                let prodDisplay: string;
                try {
                  const prods = JSON.parse(p.produto);
                  if (Array.isArray(prods)) {
                    prodDisplay = prods.map((item: any) => `${item.produto} ×${item.quantidade}`).join(', ');
                  } else {
                    prodDisplay = `${p.produto} ×${p.quantidade}`;
                  }
                } catch {
                  prodDisplay = `${p.produto} ×${p.quantidade}`;
                }
                return (
                  <div key={p.id} className="border-b border-border/50 py-2">
                    {prodDisplay} — {formatBRL(Number(p.valor))} — {formatDateShort(p.data)} — {p.status_pedido === 'postado' ? 'Postado' : p.status_pedido === 'entregue' ? 'Entregue' : 'Aguardando'}
                  </div>
                );
              })
            )}
          </div>
        </DialogContent>
      </Dialog>

      {/* Merge dialog */}
      <Dialog open={showMerge} onOpenChange={setShowMerge}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Mesclar Contatos</DialogTitle></DialogHeader>
          {mergeContacts.length === 2 && (
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">O contato mais antigo será mantido. Todos os pedidos e registros do duplicado serão transferidos.</p>
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div className="border rounded p-3 bg-primary/5">
                  <Badge className="mb-2 bg-sf-green text-primary-foreground">Mantido</Badge>
                  <p className="font-bold">{mergeContacts[0].nome}</p>
                  <p>{mergeContacts[0].telefone}</p>
                  <p className="text-xs text-muted-foreground">{formatDateShort(mergeContacts[0].created_at)}</p>
                </div>
                <div className="border rounded p-3 bg-destructive/5">
                  <Badge variant="destructive" className="mb-2">Excluído</Badge>
                  <p className="font-bold">{mergeContacts[1].nome}</p>
                  <p>{mergeContacts[1].telefone}</p>
                  <p className="text-xs text-muted-foreground">{formatDateShort(mergeContacts[1].created_at)}</p>
                </div>
              </div>
              <Button onClick={handleMerge} className="w-full bg-sf-green hover:bg-sf-green/90 text-primary-foreground">Confirmar Mesclagem</Button>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

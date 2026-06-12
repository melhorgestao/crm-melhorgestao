import { NavLink } from 'react-router-dom';
import { LayoutDashboard, Columns3, ShoppingCart, DollarSign, BarChart3, Users, Package, Truck, Settings, Shield, Wallet, Percent, Smartphone } from 'lucide-react';
import { cn } from '@/lib/utils';

interface Props {
  isAdmin: boolean;
  profile: any;
  onNavigate?: () => void;
}

const adminTabs = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, key: 'dashboard' },
  { to: '/kanban', label: 'Kanban', icon: Columns3, key: 'kanban' },
  { to: '/pedidos', label: 'Pedidos', icon: ShoppingCart, key: 'pedidos' },
  { to: '/financeiro', label: 'Financeiro', icon: DollarSign, key: 'financeiro' },
  { to: '/metricas', label: 'Métricas', icon: BarChart3, key: 'metricas' },
  { to: '/contatos', label: 'Contatos', icon: Users, key: 'contatos' },
  { to: '/estoque', label: 'Estoque', icon: Package, key: 'estoque' },
  { to: '/logistica', label: 'Logística', icon: Truck, key: 'logistica' },
  { to: '/integracoes', label: 'Integrações', icon: Settings, key: 'integracoes' },
  { to: '/instancias', label: 'Instâncias', icon: Smartphone, key: 'instancias' },
  { to: '/admin', label: 'Administração', icon: Shield, key: 'admin' },
];

const repTabs = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, key: 'dashboard' },
  { to: '/kanban-rep', label: 'Kanban', icon: Columns3, key: 'kanban' },
  { to: '/pedidos-rep', label: 'Pedidos', icon: ShoppingCart, key: 'pedidos' },
  { to: '/contatos', label: 'Contatos', icon: Users, key: 'contatos' },
  { to: '/logistica', label: 'Logística', icon: Truck, key: 'logistica' },
  { to: '/integracoes', label: 'Integrações', icon: Settings, key: 'integracoes' },
  { to: '/comissoes', label: 'Comissões', icon: Percent, key: 'comissoes' },
];

export function AppSidebarNav({ isAdmin, profile, onNavigate }: Props) {
  const verMenu = profile?.ver_menu || ['todos'];
  const tipoUsuario = profile?.tipo_usuario;
  const isRepresentante = tipoUsuario === 'representante';
  const isKanbanOnly = verMenu.length === 1 && verMenu[0] === 'kanban';
  const isLogisticaOnly = verMenu.length === 1 && verMenu[0] === 'logistica';

  let tabs = adminTabs;
  if (isRepresentante) {
    tabs = repTabs;
  } else if (isKanbanOnly) {
    tabs = adminTabs.filter(t => t.key === 'kanban');
  } else if (isLogisticaOnly) {
    tabs = adminTabs.filter(t => t.key === 'logistica');
  }

  return (
    <nav className="flex-1 py-2 overflow-y-auto">
      {tabs.map(tab => (
        <NavLink
          key={tab.to}
          to={tab.to}
          end={tab.to === '/'}
          onClick={onNavigate}
          className={({ isActive }) =>
            cn(
              'flex items-center gap-3 px-4 py-2.5 text-sm font-medium transition-colors',
              isActive
                ? 'bg-primary/10 text-primary border-r-2 border-primary'
                : 'text-muted-foreground hover:bg-muted hover:text-foreground'
            )
          }
        >
          <tab.icon className="w-4 h-4" />
          {tab.label}
        </NavLink>
      ))}
    </nav>
  );
}

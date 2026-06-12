import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Route, Routes, Navigate } from "react-router-dom";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider, useAuth } from "@/hooks/useAuth";
import { AppLayout } from "@/components/AppLayout";
import { lazy, Suspense, ComponentType } from 'react';
import Login from "./pages/Login";
import NotFound from "./pages/NotFound";

// Lazy import com retry — protege contra chunk antigo/stale cache no desktop.
function lazyWithRetry<T extends ComponentType<any>>(factory: () => Promise<{ default: T }>) {
  return lazy(async () => {
    try {
      return await factory();
    } catch (err) {
      const msg = String((err as any)?.message || "");
      const isChunkErr =
        msg.includes("Failed to fetch dynamically imported module") ||
        msg.includes("Importing a module script failed") ||
        msg.includes("error loading dynamically imported module");
      if (isChunkErr) {
        const KEY = "__chunk_reload_at";
        const last = Number(sessionStorage.getItem(KEY) || "0");
        if (Date.now() - last > 30_000) {
          sessionStorage.setItem(KEY, String(Date.now()));
          window.location.reload();
        }
      }
      // segunda tentativa
      return await factory();
    }
  });
}

const Dashboard = lazyWithRetry(() => import("./pages/Dashboard"));
const KanbanPage = lazyWithRetry(() => import("./pages/KanbanPage"));
const KanbanRepPage = lazyWithRetry(() => import("./pages/KanbanRepPage"));
const PedidosPage = lazyWithRetry(() => import("./pages/PedidosPage"));
const PedidosRepPage = lazyWithRetry(() => import("./pages/PedidosRepPage"));
const FinanceiroPage = lazyWithRetry(() => import("./pages/FinanceiroPage"));
const MetricasPage = lazyWithRetry(() => import("./pages/MetricasPage"));
const ContatosPage = lazyWithRetry(() => import("./pages/ContatosPage"));
const EstoquePage = lazyWithRetry(() => import("./pages/EstoquePage"));
const LogisticaPage = lazyWithRetry(() => import("./pages/LogisticaPage"));
const IntegracoesPage = lazyWithRetry(() => import("./pages/IntegracoesPage"));
const AdminPage = lazyWithRetry(() => import("./pages/AdminPage"));
const InstanciasPage = lazyWithRetry(() => import("./pages/InstanciasPage"));
const CampanhasPage = lazyWithRetry(() => import("./pages/CampanhasPage"));
const ComissoesPage = lazyWithRetry(() => import("./pages/ComissoesPage"));

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30 * 1000,
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  if (loading) return <div className="flex items-center justify-center min-h-screen"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" /></div>;
  if (!user) return <Navigate to="/login" replace />;
  return <AppLayout>{children}</AppLayout>;
}

function AppRoutes() {
  const { user, loading, isAdmin, profile } = useAuth();
  const verMenu = (profile?.ver_menu as string[]) || ['todos'];
  const tipoUsuario = profile?.tipo_usuario;
  const isRepresentante = tipoUsuario === 'representante';
  const isKanbanOnly = verMenu.length === 1 && verMenu[0] === 'kanban';
  const isLogisticaOnly = verMenu.length === 1 && verMenu[0] === 'logistica';

  if (loading) return <div className="flex items-center justify-center min-h-screen"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" /></div>;

  const SuspenseFallback = <div className="flex items-center justify-center min-h-[50vh]"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" /></div>;

  return (
    <Suspense fallback={SuspenseFallback}>
      <Routes>
        <Route path="/login" element={user ? <Navigate to="/" replace /> : <Login />} />
        <Route path="/" element={
          <ProtectedRoute>
            {isRepresentante ? <KanbanRepPage /> : isKanbanOnly ? <KanbanPage /> : isLogisticaOnly ? <LogisticaPage /> : <Dashboard />}
          </ProtectedRoute>
        } />

        {isRepresentante ? (
          <>
            <Route path="/kanban-rep" element={<ProtectedRoute><KanbanRepPage /></ProtectedRoute>} />
            <Route path="/pedidos-rep" element={<ProtectedRoute><PedidosRepPage /></ProtectedRoute>} />
            <Route path="/contatos" element={<ProtectedRoute><ContatosPage /></ProtectedRoute>} />
            <Route path="/logistica" element={<ProtectedRoute><LogisticaPage /></ProtectedRoute>} />
            <Route path="/integracoes" element={<ProtectedRoute><IntegracoesPage /></ProtectedRoute>} />
            <Route path="/comissoes" element={<ProtectedRoute><ComissoesPage /></ProtectedRoute>} />
          </>
        ) : (
          <>
            <Route path="/kanban" element={<ProtectedRoute><KanbanPage /></ProtectedRoute>} />
            <Route path="/logistica" element={<ProtectedRoute><LogisticaPage /></ProtectedRoute>} />
            {!isKanbanOnly && !isLogisticaOnly && (
              <>
                <Route path="/pedidos" element={<ProtectedRoute><PedidosPage /></ProtectedRoute>} />
                <Route path="/financeiro" element={<ProtectedRoute><FinanceiroPage /></ProtectedRoute>} />
                <Route path="/metricas" element={<ProtectedRoute><MetricasPage /></ProtectedRoute>} />
                <Route path="/contatos" element={<ProtectedRoute><ContatosPage /></ProtectedRoute>} />
                <Route path="/estoque" element={<ProtectedRoute><EstoquePage /></ProtectedRoute>} />
                <Route path="/integracoes" element={<ProtectedRoute><IntegracoesPage /></ProtectedRoute>} />
                {isAdmin && (
                  <>
                    <Route path="/instancias" element={<ProtectedRoute><InstanciasPage /></ProtectedRoute>} />
                    <Route path="/campanhas" element={<ProtectedRoute><CampanhasPage /></ProtectedRoute>} />
                  </>
                )}
                <Route path="/admin" element={<ProtectedRoute><AdminPage /></ProtectedRoute>} />
              </>
            )}
          </>
        )}

        <Route path="*" element={<NotFound />} />
      </Routes>
    </Suspense>
  );
}

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <AuthProvider>
          <AppRoutes />
        </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;

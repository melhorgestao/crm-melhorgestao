import { ReactNode, useState, useRef } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { AppSidebarNav } from './AppSidebarNav';
import { NotificationBell } from './NotificationBell';
import { Menu, LogOut } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useTrackingAutomation } from '@/hooks/useTrackingAutomation';
import logo from '@/assets/santa-flor-logo.png';

export function AppLayout({ children }: { children: ReactNode }) {
  const { profile, signOut, isAdmin } = useAuth();
  // Sync de rastreio SuperFrete roda global — não depende da página aberta.
  useTrackingAutomation();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [logoSrc, setLogoSrc] = useState<string>(logo);
  const fileRef = useRef<HTMLInputElement>(null);

  const handleLogoUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      const url = URL.createObjectURL(file);
      setLogoSrc(url);
    }
  };

  return (
    <div className="flex min-h-screen bg-background">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex md:w-56 flex-col border-r border-border bg-card fixed inset-y-0 left-0 z-30">
        <div className="p-4 border-b border-border flex items-center gap-3">
          <img
            src={logoSrc}
            alt="Santa Flor"
            className="w-10 h-10 object-contain cursor-pointer rounded"
            onClick={() => fileRef.current?.click()}
            title="Clique para trocar o logo"
          />
          <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={handleLogoUpload} />
          <span className="font-bold text-foreground text-sm">Santa Flor</span>
        </div>
        <AppSidebarNav isAdmin={isAdmin} profile={profile} />
        <div className="mt-auto p-3 border-t border-border">
          <Button variant="ghost" size="sm" className="w-full justify-start text-muted-foreground" onClick={signOut}>
            <LogOut className="w-4 h-4 mr-2" /> Sair
          </Button>
        </div>
      </aside>

      {/* Mobile overlay */}
      {sidebarOpen && (
        <div className="fixed inset-0 z-40 md:hidden">
          <div className="absolute inset-0 bg-foreground/20" onClick={() => setSidebarOpen(false)} />
          <aside className="absolute left-0 top-0 bottom-0 w-56 bg-card border-r border-border flex flex-col">
            <div className="p-4 border-b border-border flex items-center gap-3">
              <img src={logoSrc} alt="Santa Flor" className="w-10 h-10 object-contain" />
              <span className="font-bold text-foreground text-sm">Santa Flor</span>
            </div>
            <AppSidebarNav isAdmin={isAdmin} profile={profile} onNavigate={() => setSidebarOpen(false)} />
            <div className="mt-auto p-3 border-t border-border">
              <Button variant="ghost" size="sm" className="w-full justify-start text-muted-foreground" onClick={signOut}>
                <LogOut className="w-4 h-4 mr-2" /> Sair
              </Button>
            </div>
          </aside>
        </div>
      )}

      {/* Main */}
      <div className="flex-1 md:ml-56 flex flex-col min-h-screen">
        <header className="h-14 border-b border-border flex items-center justify-between px-4 bg-card sticky top-0 z-20">
          <Button variant="ghost" size="icon" className="md:hidden" onClick={() => setSidebarOpen(true)}>
            <Menu className="w-5 h-5" />
          </Button>
          <div className="flex-1" />
          <NotificationBell />
        </header>
        <main className="flex-1 p-4 md:p-6 overflow-auto">
          {children}
        </main>
      </div>
    </div>
  );
}

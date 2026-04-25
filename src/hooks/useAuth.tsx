import { createContext, useContext, useEffect, useState, ReactNode, useRef } from 'react';
import { User, Session } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';

interface UserProfile {
  id: string;
  user_id: string;
  nome: string;
  acesso_kanban: string;
  ver_menu: string[];
  pode_excluir_card: boolean;
  tipo_usuario: string;
  servico_tipo: string | null;
  uf_fixa: string | null;
  instancia_id: string | null;
  socio_key: string | null;
}

interface AuthContextType {
  user: User | null;
  session: Session | null;
  profile: UserProfile | null;
  loading: boolean;
  isAdmin: boolean;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  user: null, session: null, profile: null, loading: true, isAdmin: false,
  signOut: async () => {},
});

const buildFallbackProfile = (userId: string, email: string | undefined): UserProfile => ({
  id: '', user_id: userId, nome: email || '', acesso_kanban: 'todos',
  ver_menu: ['todos'], pode_excluir_card: true, tipo_usuario: 'admin',
  servico_tipo: null, uf_fixa: null, instancia_id: null, socio_key: null,
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const profileFetchedFor = useRef<string | null>(null);

  // Fetch profile separately (NEVER inside onAuthStateChange to avoid deadlock)
  const fetchProfile = async (userId: string, email: string | undefined) => {
    if (profileFetchedFor.current === userId) return;
    profileFetchedFor.current = userId;
    try {
      const { data } = await supabase
        .from('perfis_usuario')
        .select('*')
        .eq('user_id', userId)
        .maybeSingle();
      if (data) {
        setProfile({
          ...data,
          ver_menu: (data.ver_menu as any) || ['todos'],
          pode_excluir_card: (data as any).pode_excluir_card !== false,
          tipo_usuario: (data as any).tipo_usuario || 'admin',
          servico_tipo: (data as any).servico_tipo || null,
          uf_fixa: (data as any).uf_fixa || null,
          instancia_id: (data as any).instancia_id || null,
          socio_key: (data as any).socio_key || null,
        });
      } else {
        setProfile(buildFallbackProfile(userId, email));
      }
    } catch (err) {
      console.error('[useAuth] fetchProfile error:', err);
      setProfile(buildFallbackProfile(userId, email));
    }
  };

  useEffect(() => {
    let mounted = true;

    // 1) Subscribe FIRST — synchronous handler, no awaits
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, newSession) => {
      if (!mounted) return;
      setSession(newSession);
      setUser(newSession?.user ?? null);
      if (newSession?.user) {
        // Defer profile fetch to avoid deadlock
        setTimeout(() => {
          if (mounted) fetchProfile(newSession.user.id, newSession.user.email);
        }, 0);
      } else {
        profileFetchedFor.current = null;
        setProfile(null);
      }
      setLoading(false);
    });

    // 2) THEN check existing session
    supabase.auth.getSession().then(({ data: { session: existingSession } }) => {
      if (!mounted) return;
      setSession(existingSession);
      setUser(existingSession?.user ?? null);
      if (existingSession?.user) {
        fetchProfile(existingSession.user.id, existingSession.user.email);
      }
      setLoading(false);
    }).catch((err) => {
      console.error('[useAuth] getSession error:', err);
      if (mounted) setLoading(false);
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, []);

  const isAdmin = profile?.ver_menu?.includes('todos') ?? false;

  const signOut = async () => {
    profileFetchedFor.current = null;
    await supabase.auth.signOut();
    setUser(null);
    setSession(null);
    setProfile(null);
  };

  return (
    <AuthContext.Provider value={{ user, session, profile, loading, isAdmin, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);

import { useEffect, useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';

export const useIsAdmin = () => {
  const { user, profile } = useAuth();
  const [isAdmin, setIsAdmin] = useState(false);
  
  useEffect(() => {
    if (!user) {
      setIsAdmin(false);
      return;
    }

    if (profile?.tipo_usuario === 'admin') {
      setIsAdmin(true);
      return;
    }

    if (profile?.tipo_usuario === 'representante' || profile?.tipo_usuario === 'servico') {
      setIsAdmin(false);
      return;
    }

    const verMenu = (profile?.ver_menu as string[]) || [];
    setIsAdmin(verMenu.includes('todos'));
  }, [user, profile]);
  
  return isAdmin;
};

/**
 * Helper pra upload no Supabase Storage do bucket 'Ativacao'.
 * Detecta tipo MIME, gera filename único, retorna URL pública.
 */
import { supabase } from '@/integrations/supabase/client';

export type AnexoTipo = 'image' | 'video' | 'audio' | 'document';

export function detectAnexoTipo(file: File): AnexoTipo {
  const m = file.type;
  if (m.startsWith('image/')) return 'image';
  if (m.startsWith('video/')) return 'video';
  if (m.startsWith('audio/')) return 'audio';
  return 'document';
}

export async function uploadAnexo(file: File): Promise<{
  ok: boolean;
  url?: string;
  tipo?: AnexoTipo;
  path?: string;
  error?: string;
}> {
  const tipo = detectAnexoTipo(file);
  const ext = file.name.split('.').pop() || 'bin';
  const path = `${tipo}/${Date.now()}-${crypto.randomUUID().slice(0, 8)}.${ext}`;

  const { error } = await supabase.storage
    .from('Ativacao')
    .upload(path, file, { cacheControl: '3600', upsert: false });

  if (error) return { ok: false, error: error.message };

  const { data: pub } = supabase.storage.from('Ativacao').getPublicUrl(path);
  return { ok: true, url: pub.publicUrl, tipo, path };
}

export async function removeAnexo(url: string): Promise<boolean> {
  // Extrai path da URL pública: .../Ativacao/image/123.png → image/123.png
  const m = url.match(/Ativacao\/(.+)$/);
  if (!m) return false;
  const { error } = await supabase.storage.from('Ativacao').remove([m[1]]);
  return !error;
}

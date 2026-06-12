/**
 * Cliente Evolution API — wraps endpoints usados pela aba Instâncias.
 *
 * Convenção de auth:
 *   - per-instance apikey: para connectionState/connect/restart/sendText
 *   - master apikey (server-level): para create/delete/fetchInstances
 *
 * A master apikey vem de configuracoes.evolution_master_apikey.
 */
import { supabase } from '@/integrations/supabase/client';

const DEFAULT_BASE_URL = 'https://evo.melhorgestao.online';

export interface EvolutionInstance {
  evolution_url: string;
  evolution_instance: string;
  evolution_apikey: string;
}

export type ConnectionState = 'open' | 'close' | 'connecting' | 'unknown';

interface ApiResponse<T = any> {
  ok: boolean;
  status: number;
  data?: T;
  error?: string;
}

async function safeJson(res: Response): Promise<any> {
  try { return await res.json(); } catch { return null; }
}

async function evoFetch<T = any>(
  url: string,
  apikey: string,
  init: RequestInit = {}
): Promise<ApiResponse<T>> {
  try {
    const res = await fetch(url, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        apikey,
        ...(init.headers || {}),
      },
    });
    const data = await safeJson(res);
    if (!res.ok) {
      return { ok: false, status: res.status, error: data?.message || data?.error || `HTTP ${res.status}`, data };
    }
    return { ok: true, status: res.status, data };
  } catch (err: any) {
    return { ok: false, status: 0, error: err?.message || 'network error' };
  }
}

/** Busca master apikey de configuracoes. Retorna '' se não configurada. */
export async function getMasterApiKey(): Promise<string> {
  const { data } = await supabase
    .from('configuracoes')
    .select('valor')
    .eq('chave', 'evolution_master_apikey')
    .maybeSingle();
  return (data?.valor as string) || '';
}

/** GET /instance/connectionState/<name> — usa apikey da instância. */
export async function getConnectionState(inst: EvolutionInstance): Promise<ConnectionState> {
  const url = `${inst.evolution_url || DEFAULT_BASE_URL}/instance/connectionState/${encodeURIComponent(inst.evolution_instance)}`;
  const r = await evoFetch(url, inst.evolution_apikey);
  if (!r.ok) return 'unknown';
  // Evolution variants: {instance:{state:"open"}} | {state:"open"} | {connectionStatus:"open"}
  const state = r.data?.instance?.state || r.data?.state || r.data?.connectionStatus;
  if (state === 'open' || state === 'close' || state === 'connecting') return state;
  return 'unknown';
}

/** GET /instance/connect/<name> — retorna QR code (base64) + estado. */
export async function fetchQrCode(inst: EvolutionInstance): Promise<{ base64?: string; pairingCode?: string; code?: string; error?: string }> {
  const url = `${inst.evolution_url || DEFAULT_BASE_URL}/instance/connect/${encodeURIComponent(inst.evolution_instance)}`;
  const r = await evoFetch(url, inst.evolution_apikey);
  if (!r.ok) return { error: r.error };
  // Evolution variants: {base64: "data:image/png;base64,..."} | {qrcode:{base64}} | {pairingCode}
  const base64 = r.data?.base64 || r.data?.qrcode?.base64;
  const code = r.data?.code || r.data?.qrcode?.code;
  const pairingCode = r.data?.pairingCode;
  return { base64, code, pairingCode };
}

/** POST /instance/restart/<name> — força reconexão. */
export async function restartInstance(inst: EvolutionInstance): Promise<ApiResponse> {
  const url = `${inst.evolution_url || DEFAULT_BASE_URL}/instance/restart/${encodeURIComponent(inst.evolution_instance)}`;
  return evoFetch(url, inst.evolution_apikey, { method: 'POST' });
}

/** DELETE /instance/delete/<name> — remove instância no Evolution. Requer master key. */
export async function deleteInstance(instanceName: string, evolutionUrl: string): Promise<ApiResponse> {
  const master = await getMasterApiKey();
  if (!master) return { ok: false, status: 0, error: 'master apikey não configurada em configuracoes.evolution_master_apikey' };
  const url = `${evolutionUrl || DEFAULT_BASE_URL}/instance/delete/${encodeURIComponent(instanceName)}`;
  return evoFetch(url, master, { method: 'DELETE' });
}

/**
 * POST /instance/create — cria instância no Evolution.
 * Retorna apikey (per-instance) e qrcode base64 quando disponível.
 */
export async function createInstance(params: {
  instanceName: string;
  evolutionUrl?: string;
}): Promise<{ ok: boolean; apikey?: string; qrcode?: string; error?: string; raw?: any }> {
  const master = await getMasterApiKey();
  if (!master) {
    return { ok: false, error: 'Master apikey da Evolution não configurada (configuracoes.evolution_master_apikey)' };
  }

  const url = `${params.evolutionUrl || DEFAULT_BASE_URL}/instance/create`;
  const body = {
    instanceName: params.instanceName,
    qrcode: true,
    integration: 'WHATSAPP-BAILEYS',
  };
  const r = await evoFetch(url, master, { method: 'POST', body: JSON.stringify(body) });
  if (!r.ok) return { ok: false, error: r.error, raw: r.data };

  // Variantes: {hash:{apikey:"..."}, qrcode:{base64}} | {instance:{instanceId,apikey}, qrcode:{base64}}
  const apikey = r.data?.hash?.apikey || r.data?.instance?.apikey || r.data?.apikey;
  const qrcode = r.data?.qrcode?.base64 || r.data?.base64;
  return { ok: true, apikey, qrcode, raw: r.data };
}

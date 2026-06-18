/**
 * Cliente Chatwoot API — lista inboxes, busca config.
 * Usado pra auto-detectar inbox criado pelo Evolution após /chatwoot/set.
 */
import { supabase } from '@/integrations/supabase/client';

export interface ChatwootConfig {
  url: string;
  accountId: string;
  apiToken: string;
}

export interface ChatwootInbox {
  id: number;
  name: string;
  channel_type: string;
  webhook_url?: string;
}

interface ApiResponse<T = any> {
  ok: boolean;
  status: number;
  data?: T;
  error?: string;
}

/** Lê config global Chatwoot de configuracoes. */
export async function getChatwootConfig(): Promise<ChatwootConfig> {
  const { data } = await supabase
    .from('configuracoes')
    .select('chave, valor')
    .in('chave', ['chatwoot_url', 'chatwoot_account_id', 'chatwoot_api_token']);
  const map = Object.fromEntries((data || []).map((c: any) => [c.chave, c.valor]));
  return {
    url: map.chatwoot_url || '',
    accountId: map.chatwoot_account_id || '',
    apiToken: map.chatwoot_api_token || '',
  };
}

async function chatwootFetch<T = any>(
  config: ChatwootConfig,
  path: string,
  init: RequestInit = {}
): Promise<ApiResponse<T>> {
  if (!config.url || !config.accountId || !config.apiToken) {
    return { ok: false, status: 0, error: 'Config Chatwoot incompleta' };
  }
  try {
    const url = `${config.url.replace(/\/$/, '')}/api/v1/accounts/${config.accountId}${path}`;
    const res = await fetch(url, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        api_access_token: config.apiToken,
        ...(init.headers || {}),
      },
    });
    let data: any = null;
    try { data = await res.json(); } catch { /* empty */ }
    if (!res.ok) {
      return { ok: false, status: res.status, error: data?.message || `HTTP ${res.status}`, data };
    }
    return { ok: true, status: res.status, data };
  } catch (err: any) {
    return { ok: false, status: 0, error: err?.message || 'network error' };
  }
}

/** GET /inboxes — lista todos os inboxes da conta. */
export async function listInboxes(config: ChatwootConfig): Promise<ChatwootInbox[]> {
  const r = await chatwootFetch<{ payload: ChatwootInbox[] }>(config, '/inboxes');
  if (!r.ok) return [];
  return r.data?.payload || [];
}

/** Encontra inbox pelo nome (case-sensitive, exato). */
export async function findInboxByName(config: ChatwootConfig, name: string): Promise<ChatwootInbox | null> {
  const all = await listInboxes(config);
  return all.find(i => i.name === name) || null;
}

/**
 * Acha conversa+inbox de um contato pelo telefone.
 * Retorna { conversation_id, inbox_id } ou null se não encontrar.
 * 1) Busca contato via /contacts/search
 * 2) Pega conversas via /contacts/{id}/conversations
 * 3) Pega a primeira (mais recente)
 */
export async function findConversationByPhone(
  config: ChatwootConfig,
  telefone: string
): Promise<{ conversation_id: number; inbox_id: number } | null> {
  const tel = (telefone || '').replace(/\D/g, '');
  if (!tel) return null;

  // 1) Tenta com o prefixo + (formato E.164)
  const candidates = [`+${tel}`, tel];
  let contactId: number | null = null;

  for (const q of candidates) {
    const r = await chatwootFetch<{ payload: Array<{ id: number; phone_number?: string }> }>(
      config,
      `/contacts/search?q=${encodeURIComponent(q)}&include=contact_inboxes`,
    );
    const found = r.data?.payload?.[0];
    if (found?.id) { contactId = found.id; break; }
  }
  if (!contactId) return null;

  // 2) Pega conversas
  const conv = await chatwootFetch<{ payload: Array<{ id: number; inbox_id: number }> }>(
    config,
    `/contacts/${contactId}/conversations`,
  );
  const first = conv.data?.payload?.[0];
  if (!first?.id) return null;
  return { conversation_id: first.id, inbox_id: first.inbox_id };
}

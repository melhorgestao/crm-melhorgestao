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
 * Acha conversa+inbox de um contato pelo telefone Chatwoot.
 *
 * Estratégia (tenta na ordem, retorna na 1ª que achar):
 *   A) /contacts/search com várias variantes do telefone (+55..., 55..., 11..., últimos 10)
 *   B) Pra cada contato candidato: /contacts/{id}/conversations → 1ª (mais recente)
 *
 * Tudo logado em console.log com prefixo [chatwoot] pra facilitar debug.
 * Retorna null se nenhuma combinação achar conversa.
 */
export async function findConversationByPhone(
  config: ChatwootConfig,
  telefone: string
): Promise<{ conversation_id: number; inbox_id: number; contact_id: number } | null> {
  const tel = (telefone || '').replace(/\D/g, '');
  if (!tel) return null;

  // Variantes pra cobrir como o Chatwoot pode ter indexado:
  //  - com + (E.164 oficial)
  //  - só dígitos com 55 na frente
  //  - sem código do país
  //  - últimos 10 (DDD+8 sem 9)
  const variants = Array.from(new Set([
    `+${tel}`,
    tel,
    tel.startsWith('55') ? tel.slice(2) : null,                // sem código do país
    tel.length >= 10 ? tel.slice(-11) : null,                  // últimos 11
    tel.length >= 10 ? tel.slice(-10) : null,                  // últimos 10
  ].filter(Boolean) as string[]));

  console.log('[chatwoot] tentando variantes:', variants);

  for (const q of variants) {
    const r = await chatwootFetch<{ payload: Array<{ id: number; phone_number?: string; name?: string }> }>(
      config,
      `/contacts/search?q=${encodeURIComponent(q)}&include=contact_inboxes`,
    );
    const payload = r.data?.payload || [];
    console.log(`[chatwoot] /contacts/search q="${q}" status=${r.status} matches=${payload.length}`);

    for (const c of payload) {
      console.log(`[chatwoot]   candidato id=${c.id} phone=${c.phone_number} name=${c.name}`);
      const conv = await chatwootFetch<{ payload: Array<{ id: number; inbox_id: number; status?: string }> }>(
        config,
        `/contacts/${c.id}/conversations`,
      );
      const convs = conv.data?.payload || [];
      console.log(`[chatwoot]   /contacts/${c.id}/conversations → ${convs.length} conv(s)`);
      if (convs.length > 0) {
        // prioriza conversa ABERTA; senão pega 1ª
        const open = convs.find(x => x.status === 'open') || convs[0];
        return { conversation_id: open.id, inbox_id: open.inbox_id, contact_id: c.id };
      }
    }
  }

  console.warn('[chatwoot] nenhuma conversa encontrada para', telefone);
  return null;
}

/** Monta URL deep-link pra conversa específica (com inbox_id). */
export function chatwootConversationUrl(config: ChatwootConfig, conversation_id: number, inbox_id?: number): string {
  const base = config.url.replace(/\/$/, '');
  if (inbox_id) {
    return `${base}/app/accounts/${config.accountId}/inbox/${inbox_id}/conversations/${conversation_id}`;
  }
  return `${base}/app/accounts/${config.accountId}/conversations/${conversation_id}`;
}

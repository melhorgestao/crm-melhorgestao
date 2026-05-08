// Edge Function: superfrete-sync
// Sincroniza rastreio + status de pedidos pagos com a SuperFrete.
// Resolução por camadas:
//   1) /order/info status + históricos
//   2) /tracking/{codigo} (JSON ou HTML — extrai texto e JSON embutido)
//   3) Rastreamento público dos Correios (fallback) via linkcorreios.com.br
//   4) Anti-regressão antes de gravar

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SF_BASE = 'https://api.superfrete.com';
const SF_USER_AGENT = 'MelhorGestaoCRM-Sync/1.2 (contato@melhorgestao.online)';
const PUBLIC_UA = 'Mozilla/5.0 (compatible; MelhorGestao-TrackingBot/1.0; +https://crm.melhorgestao.online)';

function normalize(s: any): string {
  if (s == null) return '';
  return String(s).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
}

const DELIVERED_TOKENS = [
  'objeto entregue ao destinatario',
  'objeto entregue',
  'entregue ao destinatario',
  'delivered to recipient',
  'delivered_to_recipient',
  'delivery_completed',
  'delivery completed',
  'object_delivered',
  'objeto_entregue',
  'delivered',
  'entregue',
  'finalizado',
  'finalizada',
];

// POSTED só por evidência REAL de movimento físico nos Correios.
// 'collected' / 'postage_delivered' / 'on_route' são estados pré-postagem da SuperFrete
// (etiqueta paga aguardando coleta) — NÃO devem promover para 'postado'.
const POSTED_TOKENS = [
  'posted', 'postado', 'in_transit', 'in-transit', 'in transit', 'transit',
  'out_for_delivery', 'out-for-delivery', 'out for delivery', 'shipped',
  'em transito', 'objeto postado', 'saiu para entrega', 'em rota',
];

// WAITING inclui estados pós-pagamento mas pré-postagem física.
const WAITING_TOKENS = [
  'waiting', 'pending', 'created', 'paid', 'awaiting_purchase',
  'released', 'generated', 'collected', 'postage_delivered', 'on_route',
];

// Trechos que são "ruído" (chrome/widget) e nunca devem disparar match
const NOISE_PATTERNS = [/huggy/i, /chatbot/i, /\$_huggy/i];

function mapStatus(sf: any): string | null {
  const s = normalize(sf);
  if (!s) return null;
  for (const t of DELIVERED_TOKENS) if (s === t || s.includes(t)) return 'entregue';
  for (const t of POSTED_TOKENS) if (s === t || s.includes(t)) return 'postado';
  for (const t of WAITING_TOKENS) if (s === t) return 'aguardando_rastreio';
  return null;
}

function isNoise(text: string): boolean {
  return NOISE_PATTERNS.some((re) => re.test(text));
}

function compactText(input: string): string {
  return input.replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

function candidateObjects(data: any): any[] {
  if (!data || typeof data !== 'object') return [];
  const seen = new Set<any>();
  const candidates = [data, data?.data, data?.order, data?.shipment, data?.tracking, data?.result, data?.payload];
  return candidates.filter((item) => {
    if (!item || typeof item !== 'object' || seen.has(item)) return false;
    seen.add(item);
    return true;
  });
}

function extractMappedStatus(data: any): string | null {
  if (!data) return null;
  const scalarMatch = mapStatus(data);
  if (scalarMatch) return scalarMatch;

  for (const item of candidateObjects(data)) {
    const fields = [
      item.status, item.current_status, item.situacao, item.situation,
      item.state, item.description, item.descricao, item.message, item.title, item.raw_text,
    ];
    for (const field of fields) {
      const mapped = mapStatus(field);
      if (mapped) return mapped;
    }
  }
  return null;
}

function extractDeliveryFromHistory(data: any): string | null {
  if (!data) return null;
  const direct = extractMappedStatus(data);
  if (direct === 'entregue') return 'entregue';

  for (const item of candidateObjects(data)) {
    const candidateArrays: any[] = [
      item.history, item.tracking_history, item.events, item.timeline,
      item?.tracking?.events, item?.tracking?.history,
      item?.shipment?.history, item?.shipment?.events,
      item?.order?.history, item?.order?.events,
    ].filter(Array.isArray);

    for (const arr of candidateArrays) {
      for (const ev of arr) {
        if (!ev) continue;
        const fields = [
          ev.status, ev.type, ev.event, ev.description, ev.descricao,
          ev.message, ev.title, ev.titulo, ev.situacao, ev.situation,
        ];
        for (const f of fields) {
          const m = mapStatus(f);
          if (m === 'entregue') return 'entregue';
        }
      }
    }

    if (item.delivered_at || item.data_entrega || item.delivered === true) return 'entregue';
  }
  return null;
}

// Procura tokens de entrega em texto livre (HTML compactado), evitando ruído
function extractDeliveryFromText(rawText: string): { matched: string | null; token: string | null } {
  if (!rawText) return { matched: null, token: null };
  const compact = compactText(rawText);
  if (!compact || isNoise(compact) && compact.length < 200) return { matched: null, token: null };
  const norm = normalize(compact);

  for (const t of DELIVERED_TOKENS) {
    if (norm.includes(t)) {
      // Garante que não é só "entregue" dentro de "será entregue"/"para ser entregue"
      if (t === 'entregue') {
        if (/\b(sera|para ser|previsao de|nao entregue|aguardando)\s+entregue\b/.test(norm)) continue;
      }
      return { matched: 'entregue', token: t };
    }
  }
  for (const t of POSTED_TOKENS) {
    if (norm.includes(t)) return { matched: 'postado', token: t };
  }
  return { matched: null, token: null };
}

// Tenta extrair JSON embutido em <script> tags (Next/Nuxt/JSON-LD genérico)
function extractEmbeddedJson(html: string): any[] {
  const out: any[] = [];
  if (!html) return out;
  const reScript = /<script\b[^>]*>([\s\S]*?)<\/script>/gi;
  let m: RegExpExecArray | null;
  while ((m = reScript.exec(html)) !== null) {
    const body = m[1].trim();
    if (!body) continue;
    if (body.length > 200_000) continue;
    // Tenta JSON puro
    if ((body.startsWith('{') && body.endsWith('}')) || (body.startsWith('[') && body.endsWith(']'))) {
      try { out.push(JSON.parse(body)); continue; } catch { /* ignore */ }
    }
    // Tenta extrair objetos JSON em meio ao JS
    const reObj = /\{[^{}]{50,5000}\}/g;
    let mo: RegExpExecArray | null;
    let count = 0;
    while ((mo = reObj.exec(body)) !== null && count < 10) {
      try {
        const parsed = JSON.parse(mo[0]);
        out.push(parsed);
        count++;
      } catch { /* ignore */ }
    }
  }
  return out;
}

function extractTracking(data: any): string | null {
  if (!data) return null;
  for (const item of candidateObjects(data)) {
    const candidates = [
      item.tracking, item.tracking_code, item.self_tracking, item.trackingCode,
      item.tracking_number, item?.shipment?.tracking, item?.shipment?.tracking_code,
      item?.order?.tracking, item?.order?.tracking_code, item?.protocol,
    ];
    for (const c of candidates) {
      if (typeof c === 'string') {
        const t = c.trim();
        if (t && t.length >= 8 && t.length <= 40) return t;
      }
    }
  }
  return null;
}

function shouldUpdateStatus(current: string | null | undefined, next: string): boolean {
  const order: Record<string, number> = { aguardando_rastreio: 1, postado: 2, entregue: 3 };
  const c = order[current || ''] || 0;
  const n = order[next] || 0;
  return n > c;
}

async function createClient(url: string, key: string) {
  const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');
  return createClient(url, key);
}

type FetchResult =
  | { kind: 'json'; data: any; contentType: string }
  | { kind: 'html'; html: string; contentType: string }
  | { kind: 'empty'; contentType: string }
  | { kind: 'error'; message: string };

async function fetchAny(url: string, headers: Record<string, string>): Promise<FetchResult> {
  try {
    const r = await fetch(url, { headers, redirect: 'follow' });
    const ct = (r.headers.get('content-type') || '').toLowerCase();
    if (!r.ok) return { kind: 'error', message: `HTTP ${r.status} em ${url}` };
    const rawText = await r.text();
    if (!rawText || rawText.trim() === '') return { kind: 'empty', contentType: ct };
    const trimmed = rawText.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try { return { kind: 'json', data: JSON.parse(rawText), contentType: ct }; } catch { /* fallthrough */ }
    }
    if (ct.includes('json')) {
      try { return { kind: 'json', data: JSON.parse(rawText), contentType: ct }; } catch { /* fallthrough */ }
    }
    return { kind: 'html', html: rawText, contentType: ct };
  } catch (e) {
    return { kind: 'error', message: e instanceof Error ? e.message : String(e) };
  }
}

// Fallback público — Muambator (primária) + LinkCorreios (secundária)
// Ambas devolvem HTML server-side com histórico real dos Correios.
// Logs incluem tamanho do HTML, sample dos primeiros 200 chars normalizados,
// e todos os tokens encontrados — para auditoria sem suposição.

const BROWSER_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

function extractAllTokens(rawText: string): { delivered: string[]; posted: string[]; sample: string } {
  const compact = compactText(rawText);
  const norm = normalize(compact);
  const sample = compact.substring(0, 200);
  const delivered: string[] = [];
  const posted: string[] = [];

  for (const t of DELIVERED_TOKENS) {
    if (norm.includes(t)) {
      if (t === 'entregue' && /\b(sera|para ser|previsao de|nao entregue|aguardando)\s+entregue\b/.test(norm)) continue;
      delivered.push(t);
    }
  }
  for (const t of POSTED_TOKENS) {
    if (norm.includes(t)) posted.push(t);
  }
  return { delivered, posted, sample };
}

async function checkPublicCorreios(codigo: string): Promise<{ status: string | null; token: string | null; debug: string }> {
  const code = codigo.trim().toUpperCase();
  const debugParts: string[] = [];

  // Fonte 1 (primária): Muambator — HTML SSR completo, sem captcha
  try {
    const url = `https://www.muambator.com.br/pacotes/${encodeURIComponent(code)}/detalhes/`;
    const r = await fetch(url, {
      headers: {
        'User-Agent': BROWSER_UA,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
      },
      redirect: 'follow',
    });
    const html = await r.text();
    debugParts.push(`muambator=html(${html.length})`);
    if (r.ok && html && html.length > 500) {
      const { delivered, posted, sample } = extractAllTokens(html);
      const safeSample = sample.replace(/[;|"]/g, ' ').substring(0, 180);
      debugParts.push(`mb_sample="${safeSample}"`);
      debugParts.push(`mb_delivered=[${delivered.join('|') || '∅'}]`);
      debugParts.push(`mb_posted=[${posted.join('|') || '∅'}]`);
      if (delivered.length > 0) {
        return { status: 'entregue', token: delivered[0], debug: debugParts.join(';') };
      }
      if (posted.length > 0) {
        return { status: 'postado', token: posted[0], debug: debugParts.join(';') };
      }
    } else {
      debugParts.push(`mb_status=${r.status}`);
    }
  } catch (e) {
    debugParts.push(`mb_err=${e instanceof Error ? e.message.substring(0, 60) : 'x'}`);
  }

  // Fonte 2 (secundária): linkcorreios — redundância
  try {
    const url = `https://www.linkcorreios.com.br/?id=${encodeURIComponent(code)}`;
    const r = await fetch(url, {
      headers: {
        'User-Agent': BROWSER_UA,
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'pt-BR,pt;q=0.9',
      },
      redirect: 'follow',
    });
    const html = await r.text();
    debugParts.push(`lc=html(${html.length})`);
    if (r.ok && html && html.length > 500) {
      const { delivered, posted, sample } = extractAllTokens(html);
      const safeSample = sample.replace(/[;|"]/g, ' ').substring(0, 120);
      debugParts.push(`lc_sample="${safeSample}"`);
      debugParts.push(`lc_delivered=[${delivered.join('|') || '∅'}]`);
      debugParts.push(`lc_posted=[${posted.join('|') || '∅'}]`);
      if (delivered.length > 0) {
        return { status: 'entregue', token: delivered[0], debug: debugParts.join(';') };
      }
      if (posted.length > 0) {
        return { status: 'postado', token: posted[0], debug: debugParts.join(';') };
      }
    }
  } catch (e) {
    debugParts.push(`lc_err=${e instanceof Error ? e.message.substring(0, 60) : 'x'}`);
  }

  return { status: null, token: null, debug: debugParts.join(';') };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SUPABASE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = await createClient(SUPABASE_URL, SUPABASE_KEY);

    const { data: cfg } = await supabase.from('configuracoes').select('valor').eq('chave', 'chave_api_superfrete').single();
    const apiKey = cfg?.valor;
    if (!apiKey) {
      return new Response(JSON.stringify({ error: 'API key SuperFrete não configurada.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400,
      });
    }

    const sfHeaders = {
      'Authorization': `Bearer ${apiKey}`,
      'User-Agent': SF_USER_AGENT,
      'Accept': 'application/json',
    };

    const { data: pedidos, error: selErr } = await supabase
      .from('pedidos')
      .select('id, order_number, status_pedido, etiqueta_codigo, etiqueta_paga, etiqueta_url, codigo_rastreio')
      .eq('etiqueta_paga', true)
      .not('etiqueta_codigo', 'is', null)
      .in('status_pedido', ['aguardando_rastreio', 'postado'])
      .order('created_at', { ascending: false })
      .limit(200);

    if (selErr) console.error('[superfrete-sync] erro select pedidos:', selErr);

    const validos = (pedidos || []).filter((p: any) =>
      p.etiqueta_codigo && String(p.etiqueta_codigo).trim() !== ''
    );

    // Auditoria: contagem de pedidos já entregues (manual ou auto) que estão fora do loop por design
    const { count: entreguesCount } = await supabase
      .from('pedidos')
      .select('id', { count: 'exact', head: true })
      .eq('etiqueta_paga', true)
      .eq('status_pedido', 'entregue');

    console.log(`[superfrete-sync] pedidos elegíveis: ${validos.length} | já entregues (skip por filtro): ${entreguesCount ?? 0}`);

    if (validos.length === 0) {
      return new Response(JSON.stringify({
        checked: 0, updated: 0,
        message: 'Nenhum pedido pago com etiqueta_codigo para sincronizar.',
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    let updated = 0;
    const results: any[] = [];

    for (const p of validos) {
      try {
        const sfId = String(p.etiqueta_codigo).trim();

        // 1) /order/info
        const orderInfoRes = await fetchAny(`${SF_BASE}/api/v0/order/info/${sfId}`, sfHeaders);
        const orderInfoData = orderInfoRes.kind === 'json' ? orderInfoRes.data : null;
        if (orderInfoRes.kind === 'error') {
          results.push({ pedido: p.order_number, error: orderInfoRes.message });
          continue;
        }

        const sfStatus =
          orderInfoData?.status ||
          orderInfoData?.current_status ||
          orderInfoData?.data?.status ||
          orderInfoData?.data?.current_status ||
          null;
        const printUrl: string | null = orderInfoData?.print?.url || orderInfoData?.print_url || null;

        let tracking = orderInfoData ? extractTracking(orderInfoData) : null;
        if (tracking && tracking === sfId) tracking = null;
        const codigoRastreio = tracking || p.codigo_rastreio;

        let resolved: string | null = null;
        let evidenceSource: string | null = null;
        let evidenceToken: string | null = null;

        // Camada A: status principal /order/info
        if (orderInfoData) {
          const m = extractMappedStatus(orderInfoData);
          if (m) { resolved = m; evidenceSource = 'order_info_status'; }
        }
        // Camada B: histórico /order/info
        if (resolved !== 'entregue' && orderInfoData) {
          const h = extractDeliveryFromHistory(orderInfoData);
          if (h === 'entregue') { resolved = 'entregue'; evidenceSource = 'order_info_history'; }
        }

        // Camada C: SuperFrete tracking endpoint
        let trackingRespKind: string = 'skipped';
        if (resolved !== 'entregue' && codigoRastreio && String(codigoRastreio).trim() !== '') {
          const tres = await fetchAny(`${SF_BASE}/api/v0/tracking/${String(codigoRastreio).trim()}`, sfHeaders);
          trackingRespKind = tres.kind;

          if (tres.kind === 'json') {
            const td = extractDeliveryFromHistory(tres.data) || extractMappedStatus(tres.data);
            if (td === 'entregue') { resolved = 'entregue'; evidenceSource = 'tracking_json'; }
            else if (!resolved && td) { resolved = td; evidenceSource = 'tracking_json'; }
          } else if (tres.kind === 'html') {
            // C1) JSON embutido em <script>
            const embedded = extractEmbeddedJson(tres.html);
            for (const obj of embedded) {
              const td = extractDeliveryFromHistory(obj) || extractMappedStatus(obj);
              if (td === 'entregue') { resolved = 'entregue'; evidenceSource = 'tracking_html_embedded_json'; break; }
              else if (!resolved && td) { resolved = td; evidenceSource = 'tracking_html_embedded_json'; }
            }
            // C2) texto compactado
            if (resolved !== 'entregue') {
              const found = extractDeliveryFromText(tres.html);
              if (found.matched === 'entregue') {
                resolved = 'entregue'; evidenceSource = 'tracking_html_text'; evidenceToken = found.token;
              } else if (!resolved && found.matched) {
                resolved = found.matched; evidenceSource = 'tracking_html_text'; evidenceToken = found.token;
              }
            }
          }
        }

        // Camada D: fallback público Correios — APENAS LOG, NÃO PROMOVE STATUS
        // Motivo: muambator/linkcorreios devolvem páginas de exemplo quando o código não existe
        // ainda na base deles, gerando falsos positivos. Status só é promovido por evidência
        // estruturada da API SuperFrete (camadas A, B ou C).
        let publicChecked = false;
        let publicDebug = '';
        let publicSeen: string | null = null;
        if (resolved !== 'entregue' && codigoRastreio && /^[A-Z]{2}\d{9}[A-Z]{2}$/i.test(String(codigoRastreio).trim())) {
          publicChecked = true;
          const pub = await checkPublicCorreios(String(codigoRastreio).trim());
          publicDebug = pub.debug;
          publicSeen = pub.status;
          // NÃO atribui resolved/evidenceSource a partir do fallback público.
        }

        const updates: Record<string, any> = {};
        if (tracking && tracking !== p.codigo_rastreio) updates.codigo_rastreio = tracking;
        if (printUrl && !p.etiqueta_url) updates.etiqueta_url = printUrl;
        if (resolved && shouldUpdateStatus(p.status_pedido, resolved)) {
          updates.status_pedido = resolved;
        }

        console.log(
          `[superfrete-sync] #${p.order_number} sf=${sfStatus || '∅'} tracking=${codigoRastreio || '∅'} ` +
          `trackingRespKind=${trackingRespKind} publicChecked=${publicChecked} publicSeen=${publicSeen || '∅'} pubDbg=${publicDebug || '∅'} ` +
          `resolved=${resolved || '∅'} evidence=${evidenceSource || '∅'} token=${evidenceToken || '∅'} ` +
          `updates=${JSON.stringify(updates)}`
        );

        if (Object.keys(updates).length > 0) {
          const { error: updErr } = await supabase.from('pedidos').update(updates).eq('id', p.id);
          if (updErr) {
            console.error(`[superfrete-sync] erro update #${p.order_number}:`, updErr);
            results.push({ pedido: p.order_number, error: updErr.message });
            continue;
          }
          await supabase.from('log_atividades').insert({
            usuario: 'Sistema (SuperFrete Sync)',
            acao: `Sync: ${updates.status_pedido ? 'status -> ' + updates.status_pedido : 'rastreio/url atualizado'}`,
            tabela_afetada: 'pedidos', registro_id: p.id,
            detalhe: `Pedido #${p.order_number} | sfId: ${sfId} | rastreio: ${updates.codigo_rastreio || codigoRastreio || '—'} | resolved: ${resolved || '—'} | evidence: ${evidenceSource || '—'}`,
          });
          updated++;
          results.push({ pedido: p.order_number, sf_status: sfStatus, resolved, evidence: evidenceSource, token: evidenceToken, updates });
        } else {
          results.push({ pedido: p.order_number, sf_status: sfStatus, resolved, evidence: evidenceSource, msg: 'sem mudança' });
        }
      } catch (e) {
        results.push({ pedido: p.order_number, error: e instanceof Error ? e.message : String(e) });
      }
    }

    console.log(`[superfrete-sync] checked=${validos.length} updated=${updated}`);

    return new Response(JSON.stringify({ success: true, checked: validos.length, updated, results }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    const msg = error instanceof Error ? error.message : 'Erro desconhecido';
    console.error('[superfrete-sync] fatal:', msg);
    return new Response(JSON.stringify({ error: msg }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500,
    });
  }
});

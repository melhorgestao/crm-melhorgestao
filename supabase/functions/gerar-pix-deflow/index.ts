// ============================================================================
// gerar-pix-deflow — DeFlow real (POST /v1/deposit/create, mode=exact)
//
// Modo "exact": cliente paga o valor BRUTO do pedido. DeFlow desconta taxa
// do crédito. Recebemos LÍQUIDO (netAmountCents) — esse vai pra caixa.
//
// RESILIÊNCIA (v4): SEMPRE conclusivo, NUNCA background, e RESPEITANDO a
// antifraude da DeFlow.
//
// Changelog DeFlow v1.7 (06/07/2026): janela de velocidade de 30min, bloqueio
// de VALOR REPETIDO e cooldown de 30s são aplicados POR CPF DO PAGADOR.
// Retry rápido (5s/8s) era falha garantida e ainda queimava a janela daquele
// CPF — piorava o problema. Agora: 1 tentativa + no máximo 1 retry após 32s.
// Se falhar, é conclusivo: o agent-closing avisa o cliente e aciona suporte.
//
// v1.8: 'mode' virou opcional e IGNORADO (sempre modo bruto: o pagador paga
// exatamente amountInCents, taxa sai do líquido) — removido do payload.
// v1.5: X-DF-Idempotency-Key é obrigatório (enviamos, novo a cada tentativa —
// chave fixa por pedido fazia a DeFlow repetir o estado de falha pra sempre).
//
// PERMANENTE (sem retry): CPF malformado OU bloqueio antifraude — insistir
// não resolve e só piora.
//
// Linkagem pedido_em_aberto.pix_id = deposit.id (lookup reverso no webhook).
//
// INPUT:  { pedido_em_aberto_id: uuid }
// OUTPUT: { ok, pix_id, pix_copia_cola, ... } | { error, pix_indisponivel }
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const DEFLOW_BASE = 'https://api.deflow.exchange'

type TentativaOk = {
  ok: true; depositId: string; qrCopyPaste: string; qrImageUrl: string;
  feeCents: number | null; netAmountCents: number | null; expiresAt: string
}
type TentativaErr = { ok: false; permanente: boolean; error: string }

/** Uma tentativa de criar o depósito na DeFlow. */
async function tentarDeposito(
  cfg: Record<string, string>, amountCents: number, cpf: string, seed: string,
): Promise<TentativaOk | TentativaErr> {
  // v1.8 da API: 'mode' é opcional e IGNORADO (depósito sempre no modo bruto —
  // o pagador paga exatamente amountInCents e a taxa sai do líquido em DePix).
  // Não enviamos mais pra não induzir erro.
  const body: Record<string, unknown> = {
    amountInCents: amountCents,
    payerTaxNumber: cpf,
  }
  if (cfg['deflow_wallet_id']) body.walletId = cfg['deflow_wallet_id']

  let r: Response
  try {
    r = await fetch(`${DEFLOW_BASE}/v1/deposit/create`, {
      method: 'POST',
      headers: {
        'Authorization':        `Bearer ${cfg['deflow_api_key']}`,
        'X-DF-Secret':          cfg['deflow_secret'],
        'X-DF-Passphrase':      cfg['deflow_passphrase'],
        'X-DF-Idempotency-Key': uuidv4FromSeed(seed),
        'Content-Type':         'application/json',
      },
      body: JSON.stringify(body),
    })
  } catch (e) {
    return { ok: false, permanente: false, error: `rede: ${e instanceof Error ? e.message : String(e)}` }
  }

  if (!r.ok) {
    const errBody = await r.text()
    // ANTIFRAUDE (v1.7): janela de 30min, bloqueio de valor repetido e cooldown
    // de 30s são POR CPF do pagador. Insistir NÃO resolve — só queima mais a
    // janela daquele CPF. Tratamos como permanente pra escalar pro humano.
    const antifraude = /este cpf|valor repetido|velocidade|bloqueio|cooldown|processar pagamentos/i.test(errBody)
    // CPF/CNPJ malformado = permanente também (o agente pede o CPF certo)
    const cpfInvalido = /cpf|cnpj|payerTaxNumber/i.test(errBody) && /inválido|invalido|must be/i.test(errBody)
    return {
      ok: false,
      permanente: antifraude || cpfInvalido,
      error: `DeFlow ${r.status}: ${errBody.slice(0, 400)}`,
    }
  }

  const resp = await r.json()
  const d = resp.data || resp
  if (!d.id || !d.qrCopyPaste) {
    return { ok: false, permanente: false, error: `resposta DeFlow malformada: ${JSON.stringify(d).slice(0, 200)}` }
  }
  return {
    ok: true, depositId: d.id, qrCopyPaste: d.qrCopyPaste,
    qrImageUrl: d.qrImageUrl || '', feeCents: d.feeCents ?? null,
    netAmountCents: d.netAmountCents ?? null,
    expiresAt: d.expiresAt || new Date(Date.now() + 15 * 60 * 1000).toISOString(),
  }
}

/** Persiste o Pix no pedido. */
async function persistirPix(supabase: any, pedidoId: string, amountCents: number, t: TentativaOk) {
  await supabase.from('pedido_em_aberto').update({
    pix_id: t.depositId,
    pix_copia_cola: t.qrCopyPaste,
    pix_qr_image_url: t.qrImageUrl,
    pix_expira_em: t.expiresAt,
    pix_bruto_cents: amountCents,
    pix_taxa_cents: t.feeCents,
    pix_liquido_cents: t.netAmountCents,
    updated_at: new Date().toISOString(),
  }).eq('id', pedidoId)
}


Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { pedido_em_aberto_id } = await req.json()
    if (!pedido_em_aberto_id) return j({ error: 'pedido_em_aberto_id obrigatório' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: pedido, error: pErr } = await supabase
      .from('pedido_em_aberto')
      .select('id, contato_id, instancia_id, total, status, valor_primeira_parcela, is_parcelado, is_cobranca_saldo, pix_id, pix_copia_cola, pix_qr_image_url, pix_expira_em, pix_liquido_cents, pix_taxa_cents')
      .eq('id', pedido_em_aberto_id).single()
    if (pErr || !pedido) return j({ error: 'pedido não encontrado' }, 404)
    if (pedido.status !== 'aguardando_pagamento') {
      return j({ error: `pedido em estado inválido: ${pedido.status}` }, 400)
    }

    // Idempotente: se já tem Pix gerado, devolve o existente
    if (pedido.pix_copia_cola) {
      return j({
        ok: true, idempotente: true,
        pix_id:          pedido.pix_id,
        pix_copia_cola:  pedido.pix_copia_cola,
        pix_qr_image_url: pedido.pix_qr_image_url,
        pix_expira_em:   pedido.pix_expira_em,
        valor_bruto:     Number(pedido.total),
        valor_liquido:   pedido.pix_liquido_cents ? pedido.pix_liquido_cents / 100 : null,
        taxa:            pedido.pix_taxa_cents ? pedido.pix_taxa_cents / 100 : null,
      })
    }

    // VALOR a cobrar: se parcelado, é a 1ª parcela (50%); senão, total
    const valorBruto = Number(pedido.valor_primeira_parcela ?? pedido.total)
    const amountCents = Math.round(valorBruto * 100)
    if (!Number.isFinite(amountCents) || amountCents <= 0) {
      return j({ error: 'valor inválido pra gerar Pix' }, 400)
    }

    // Credenciais DeFlow
    const { data: configs } = await supabase
      .from('configuracoes').select('chave, valor')
      .in('chave', ['deflow_api_key','deflow_secret','deflow_passphrase','deflow_wallet_id'])
    const cfg: Record<string,string> = {}
    for (const c of (configs || []) as any[]) cfg[c.chave] = (c.valor as string || '').trim()

    // STUB se faltar credencial — permite testar fluxo sem DeFlow real
    if (!cfg['deflow_api_key'] || !cfg['deflow_secret'] || !cfg['deflow_passphrase']) {
      const stubId   = `STUB-${pedido.id}`
      const stubCola = `00020126360014BR.GOV.BCB.PIX0114STUB${pedido.id.slice(0,8)}520400005303986540${valorBruto.toFixed(2)}5802BR5910SANTA FLOR6009SAO PAULO62070503***6304STUB`
      const expira   = new Date(Date.now() + 15 * 60 * 1000).toISOString()
      await supabase.from('pedido_em_aberto').update({
        pix_id: stubId, pix_copia_cola: stubCola, pix_qr_base64: '',
        pix_qr_image_url: '', pix_expira_em: expira, pix_bruto_cents: amountCents,
        updated_at: new Date().toISOString(),
      }).eq('id', pedido_em_aberto_id)
      return j({
        ok: true, modo: 'stub',
        aviso: 'credenciais DeFlow não configuradas — Pix retornado é placeholder',
        pix_id: stubId, pix_copia_cola: stubCola, pix_qr_image_url: '',
        pix_expira_em: expira, valor_bruto: valorBruto, valor_liquido: null, taxa: null,
      })
    }

    // CPF do pagador: a API DeFlow EXIGE payerTaxNumber
    const { data: contatoRow } = await supabase
      .from('contatos').select('id, telefone, nome, instancia_id, cpf')
      .eq('id', pedido.contato_id).maybeSingle()
    const cpfPagador = String((contatoRow as any)?.cpf || '').replace(/\D/g, '')
    if (cpfPagador.length !== 11) {
      return j({ error: 'CPF do cliente ausente/inválido — necessário pra gerar o Pix (peça o CPF e salve antes)' }, 400)
    }

    // ── Tentativas SÍNCRONAS e rápidas ──────────────────────────────────────
    // NADA de background: EdgeRuntime.waitUntil NÃO sustenta ~100s de retries
    // (o isolate é derrubado antes) — resultado era silêncio total pro cliente.
    // 3 tentativas curtas cabem no turno do agente (router aguarda 150s), e o
    // retorno é SEMPRE conclusivo: Pix na mão OU erro claro pra escalar.
    // ANTIFRAUDE DeFlow (v1.7): cooldown de 30s POR CPF do pagador. Retry
    // antes disso é falha garantida E queima a janela de velocidade de 30min
    // daquele CPF. Então: 1 tentativa + no máximo 1 retry após o cooldown.
    const startedAt = Date.now()
    const DELAYS = [0, 32000]
    let ultimoErro = ''
    for (let i = 0; i < DELAYS.length; i++) {
      if (DELAYS[i] > 0) await new Promise(res => setTimeout(res, DELAYS[i]))
      // key nova por tentativa: chave fixa por pedido travava o erro pra sempre
      const t = await tentarDeposito(cfg, amountCents, cpfPagador, `${pedido.id}:${startedAt}:${i}`)
      if (t.ok) {
        await persistirPix(supabase, pedido.id, amountCents, t)
        return j({
          ok: true, modo: 'real', tentativas: i + 1,
          pix_id: t.depositId, pix_copia_cola: t.qrCopyPaste,
          pix_qr_image_url: t.qrImageUrl, pix_expira_em: t.expiresAt,
          valor_bruto: valorBruto,
          valor_liquido: t.netAmountCents ? t.netAmountCents / 100 : null,
          taxa: t.feeCents ? t.feeCents / 100 : null,
        })
      }
      ultimoErro = t.error
      if (t.permanente) {
        return j({ error: t.error, pix_indisponivel: true, permanente: true }, 400)
      }
    }
    // Esgotou: erro conclusivo. O agent-closing avisa o cliente e chama suporte
    // de forma determinística (nunca fica mudo).
    return j({ error: ultimoErro, pix_indisponivel: true, tentativas: DELAYS.length }, 502)

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return j({ error: msg }, 500)
  }
})

// UUID v4 determinístico a partir de um seed (pedido:tentativa).
// Tentativas diferentes usam chaves diferentes (a mesma chave numa criação
// que falhou poderia replay o erro); a MESMA tentativa em retry HTTP replay
// a mesma chave (não duplica depósito).
function uuidv4FromSeed(seed: string): string {
  const hash = simpleHash(seed)
  const h = (hash + hash + hash).slice(0, 32)
  return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-8${h.slice(17,20)}-${h.slice(20,32)}`
}
function simpleHash(s: string): string {
  let h = 0n
  for (const c of s) h = (h * 31n + BigInt(c.charCodeAt(0))) & 0xffffffffffffffffn
  return h.toString(16).padStart(16, '0').repeat(2)
}

function j(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

// ═══════════════════════════════════════════════════════════════════
// Supabase Edge Function — receptor de mensagens do WhatsApp Bot
// Deploy: supabase functions deploy webhook-whatsapp
// Secret necessário: WHATSAPP_WEBHOOK_SECRET (opcional mas recomendado)
// ═══════════════════════════════════════════════════════════════════
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')
const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const WEBHOOK_SECRET   = Deno.env.get('WHATSAPP_WEBHOOK_SECRET')

// Fail-closed: sem segredo configurado a função NÃO aceita nada
// (antes, sem o secret, qualquer pessoa gravava histórico em qualquer revenda
// e descobria o nome da revenda dona de um telefone).
if (!SUPABASE_URL || !SUPABASE_SERVICE || !WEBHOOK_SECRET || WEBHOOK_SECRET.length < 32) {
  throw new Error('SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e WHATSAPP_WEBHOOK_SECRET (>= 32 chars) são obrigatórios')
}

// Chamada servidor→servidor: sem CORS liberado pra navegador
const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  'null',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'Content-Type, x-whatsapp-secret',
}

// Comparação em tempo constante (evita descobrir o segredo por timing)
function segredoConfere(recebido: string | null): boolean {
  if (!recebido) return false
  const a = new TextEncoder().encode(recebido)
  const b = new TextEncoder().encode(WEBHOOK_SECRET!)
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}

// Remove tudo que não for dígito para comparação
function normalizarFone(tel: string): string {
  return tel.replace(/\D/g, '')
}

// Compara dois números normalizados tolerando prefixo +55
function foneBate(armazenado: string, recebido: string): boolean {
  if (!armazenado || !recebido) return false
  // Correspondência exata ou um é sufixo do outro (ex: "11999..." vs "5511999...")
  return (
    armazenado === recebido ||
    recebido.endsWith(armazenado) ||
    armazenado.endsWith(recebido)
  )
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS })
  }

  if (req.method !== 'POST') {
    return Response.json({ error: 'Método não permitido' }, { status: 405 })
  }

  // ── Valida secret compartilhado (obrigatório) ────────────────────
  if (!segredoConfere(req.headers.get('x-whatsapp-secret'))) {
    return Response.json({ error: 'Não autorizado' }, { status: 401, headers: CORS_HEADERS })
  }

  // ── Parse do payload ─────────────────────────────────────────────
  let payload: any
  try {
    payload = await req.json()
  } catch {
    return Response.json({ error: 'JSON inválido' }, { status: 400, headers: CORS_HEADERS })
  }

  const phone   = String(payload.phone   || '').trim().slice(0, 40)
  const type    = String(payload.type    || 'whatsapp_received').trim()
  const message = String(payload.message || '').trim().slice(0, 10000)

  if (!phone || !message) {
    return Response.json(
      { error: 'Campos obrigatórios: phone, message' },
      { status: 400, headers: CORS_HEADERS }
    )
  }

  const sb = createClient(SUPABASE_URL!, SUPABASE_SERVICE!)

  // ── Busca revenda pelo número de telefone ────────────────────────
  const { data: revendas, error: errFetch } = await sb
    .from('revendas')
    .select('id, nome, tel, tel2, tel3')

  if (errFetch) {
    console.error('dynamic-processor: erro ao consultar revendas —', errFetch.message)
    return Response.json({ error: 'Erro interno' }, { status: 500, headers: CORS_HEADERS })
  }

  const phoneClean = normalizarFone(phone)

  const revenda = (revendas || []).find((r: any) =>
    [r.tel, r.tel2, r.tel3].some((t: any) =>
      foneBate(normalizarFone(String(t || '')), phoneClean)
    )
  )

  if (!revenda) {
    return Response.json({ error: 'Nenhuma revenda cadastrada com este número' }, { status: 404, headers: CORS_HEADERS })
  }

  // ── Insere no histórico da revenda ───────────────────────────────
  const tipo = type === 'whatsapp_sent' ? '📤 WhatsApp enviado' : '💬 WhatsApp'

  const { error: errInsert } = await sb.from('historico_cards').insert({
    revenda_id:   revenda.id,
    tipo,
    descricao:    message,
    manual:       false,
    usuario_nome: 'WhatsApp Bot',
  })

  if (errInsert) {
    console.error('dynamic-processor: erro ao salvar histórico —', errInsert.message)
    return Response.json({ error: 'Erro interno' }, { status: 500, headers: CORS_HEADERS })
  }

  // Não devolve nome/id da revenda (evita usar o endpoint como "consulta de telefone")
  return Response.json({ success: true, tipo }, { headers: CORS_HEADERS })
})

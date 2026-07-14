// ═══════════════════════════════════════════════════════════════════
// Supabase Edge Function — receptor de mensagens do WhatsApp Bot
// Deploy: supabase functions deploy webhook-whatsapp
// Secret necessário: WHATSAPP_WEBHOOK_SECRET (opcional mas recomendado)
// ═══════════════════════════════════════════════════════════════════
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')
const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const WEBHOOK_SECRET   = Deno.env.get('WHATSAPP_WEBHOOK_SECRET')

if (!SUPABASE_URL || !SUPABASE_SERVICE) {
  throw new Error('SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios')
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, x-whatsapp-secret',
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

  // ── Valida secret compartilhado ──────────────────────────────────
  if (WEBHOOK_SECRET) {
    const secret = req.headers.get('x-whatsapp-secret')
    if (!secret || secret !== WEBHOOK_SECRET) {
      return Response.json({ error: 'Não autorizado' }, { status: 401, headers: CORS_HEADERS })
    }
  }

  // ── Parse do payload ─────────────────────────────────────────────
  let payload: any
  try {
    payload = await req.json()
  } catch {
    return Response.json({ error: 'JSON inválido' }, { status: 400, headers: CORS_HEADERS })
  }

  const phone   = String(payload.phone   || '').trim()
  const type    = String(payload.type    || 'whatsapp_received').trim()
  const message = String(payload.message || '').trim()

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
    return Response.json(
      { error: `Erro ao consultar banco: ${errFetch.message}` },
      { status: 500, headers: CORS_HEADERS }
    )
  }

  const phoneClean = normalizarFone(phone)

  const revenda = (revendas || []).find((r: any) =>
    [r.tel, r.tel2, r.tel3].some((t: any) =>
      foneBate(normalizarFone(String(t || '')), phoneClean)
    )
  )

  if (!revenda) {
    return Response.json(
      { error: 'Nenhuma revenda cadastrada com este número', phone },
      { status: 404, headers: CORS_HEADERS }
    )
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
    return Response.json(
      { error: `Erro ao salvar histórico: ${errInsert.message}` },
      { status: 500, headers: CORS_HEADERS }
    )
  }

  return Response.json(
    { success: true, revenda: { id: revenda.id, nome: revenda.nome }, tipo },
    { headers: CORS_HEADERS }
  )
})

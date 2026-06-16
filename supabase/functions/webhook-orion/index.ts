// ═══════════════════════════════════════════════════════════════════
// Supabase Edge Function — receptor de webhooks da Orion CRM
// Deploy: supabase functions deploy webhook-orion
// ═══════════════════════════════════════════════════════════════════
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL         = Deno.env.get('SUPABASE_URL')
const SUPABASE_SERVICE     = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const ORION_WEBHOOK_SECRET = Deno.env.get('ORION_WEBHOOK_SECRET')
// Origens permitidas (separadas por vírgula no env var ALLOWED_ORIGINS)
// Ex: "https://comercial-lc.github.io,https://meusite.com"
const ALLOWED_ORIGINS_RAW  = Deno.env.get('ALLOWED_ORIGINS') || ''

if (!SUPABASE_URL || !SUPABASE_SERVICE || !ORION_WEBHOOK_SECRET) {
  throw new Error(
    'Variáveis obrigatórias ausentes: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ORION_WEBHOOK_SECRET'
  )
}

const ALLOWED_ORIGINS: string[] = ALLOWED_ORIGINS_RAW
  ? ALLOWED_ORIGINS_RAW.split(',').map(o => o.trim()).filter(Boolean)
  : []

// ── CORS dinâmico — whitelist de origens ────────────────────────────
function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') || ''
  const allowed =
    ALLOWED_ORIGINS.length === 0 ||  // sem configuração = dev mode
    ALLOWED_ORIGINS.includes(origin)
  return {
    'Access-Control-Allow-Origin':  allowed ? origin : 'null',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-orion-signature',
    'Vary': 'Origin',
  }
}

// ── Verificação de assinatura HMAC-SHA256 (timing-safe) ─────────────
async function verificarAssinatura(req: Request, body: string): Promise<boolean> {
  // Aceita apenas o header x-orion-signature com prefixo sha256=
  const sigHeader = req.headers.get('x-orion-signature')
  if (!sigHeader || !sigHeader.startsWith('sha256=')) return false

  const sigHex = sigHeader.slice(7)  // remove "sha256="
  if (sigHex.length === 0 || sigHex.length % 2 !== 0) return false

  try {
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(ORION_WEBHOOK_SECRET),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    )
    const sigBytes  = hexToBytes(sigHex)
    const bodyBytes = new TextEncoder().encode(body)
    return await crypto.subtle.verify('HMAC', key, sigBytes, bodyBytes)
  } catch {
    return false
  }
}

function hexToBytes(hex: string): Uint8Array {
  const arr = new Uint8Array(hex.length / 2)
  for (let i = 0; i < arr.length; i++) {
    const byte = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
    if (isNaN(byte)) throw new Error('Hex inválido')
    arr[i] = byte
  }
  return arr
}

// ── Validação e normalização de lead ────────────────────────────────
function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
}

function normalizarLead(payload: any): any {
  const lead = payload.lead || payload.data || payload.card || payload

  const nome     = String(lead.empresa || lead.company || lead.nome || lead.name || '').trim()
  const id_origem = String(lead.id ?? lead.lead_id ?? '').trim()
  const email    = String(lead.email || '').trim()
  const telefone = String(lead.telefone || lead.phone || lead.tel || '').trim()
  const cidade   = String(lead.cidade || lead.city || '').trim()
  const uf       = String(lead.uf || lead.estado || lead.state || '').trim().toUpperCase().slice(0, 2)
  const cs       = String(lead.responsavel || lead.responsible || lead.vendedor || '').trim()
  const obs      = String(lead.observacao  || lead.observation || lead.notes || '').trim()

  if (!nome)      throw new Error('Campo obrigatório ausente: nome/empresa')
  if (!id_origem) throw new Error('Campo obrigatório ausente: id/lead_id')
  if (email && !isValidEmail(email)) throw new Error(`Email inválido: ${email}`)

  return {
    nome, email, telefone, cidade, uf, cs, obs,
    id_origem,
    status:    'Nova Revenda',
    ingresso:  new Date().toISOString().slice(0, 10),
    criado_em: new Date().toISOString(),
    _orion_raw: JSON.stringify(lead).slice(0, 8000),  // limita tamanho
  }
}

// ── Normalização de meta ─────────────────────────────────────────────
function normalizarMeta(payload: any): any {
  const meta = payload.meta || payload.data || payload

  const nome       = String(meta.nome || meta.name || meta.titulo || '').trim() || 'Meta Comercial'
  const tipo       = String(meta.tipo || meta.type || 'quantidade').trim()
  const valor_meta = Math.max(0, Number(meta.valor_meta || meta.meta || meta.objetivo || meta.target || 0))
  const valor_atual= Math.max(0, Number(meta.valor_atual || meta.atual || meta.current || meta.realizado || 0))
  const mes        = Math.min(12, Math.max(1, Number(meta.mes || meta.month || new Date().getMonth() + 1)))
  const ano        = Number(meta.ano || meta.year || new Date().getFullYear())

  if (isNaN(mes) || isNaN(ano) || isNaN(valor_meta)) throw new Error('Campos numéricos inválidos na meta')

  return { nome, tipo, valor_meta, valor_atual, mes, ano,
    _orion_raw: JSON.stringify(meta).slice(0, 8000) }
}

// ── Handler principal ────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  const corsHeaders = buildCorsHeaders(req)

  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  const sb = createClient(SUPABASE_URL!, SUPABASE_SERVICE!)

  // ── GET — dashboard consulta metas/leads ────────────────────────
  if (req.method === 'GET') {
    const authHeader = req.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return Response.json({ error: 'Autenticação necessária' }, { status: 401, headers: corsHeaders })
    }
    const { data: { user }, error: authErr } = await sb.auth.getUser(authHeader.slice(7))
    if (authErr || !user) {
      return Response.json({ error: 'Token inválido' }, { status: 401, headers: corsHeaders })
    }

    const url  = new URL(req.url)
    const tipo = url.searchParams.get('tipo')
    const mes  = Number(url.searchParams.get('mes'))  || new Date().getMonth() + 1
    const ano  = Number(url.searchParams.get('ano'))  || new Date().getFullYear()

    if (tipo === 'metas') {
      const { data } = await sb.from('orion_metas').select('*')
        .eq('mes', mes).eq('ano', ano).order('criado_em', { ascending: false })
      return Response.json({ success: true, data: data || [] }, { headers: corsHeaders })
    }

    if (tipo === 'leads_vendidos') {
      const { data } = await sb.from('orion_leads_vendidos').select('*')
        .order('criado_em', { ascending: false }).limit(50)
      return Response.json({ success: true, data: data || [] }, { headers: corsHeaders })
    }

    return Response.json({ ok: true, msg: 'Webhook Orion ativo' }, { headers: corsHeaders })
  }

  // ── POST — recebe evento da Orion ────────────────────────────────
  if (req.method !== 'POST') {
    return Response.json({ error: 'Método não permitido' }, { status: 405 })
  }

  const rawBody = await req.text()

  // Valida assinatura antes de processar qualquer coisa
  const autorizado = await verificarAssinatura(req, rawBody)
  if (!autorizado) {
    await sb.from('auditoria').insert({
      acao: 'WEBHOOK_UNAUTHORIZED',
      tabela: 'webhook_orion',
      detalhe: { ip: req.headers.get('x-forwarded-for') || 'unknown' }
    }).catch(() => {})  // não bloqueia em caso de falha no log
    return Response.json({ error: 'Não autorizado' }, { status: 401 })
  }

  let payload: any
  try {
    payload = JSON.parse(rawBody)
  } catch {
    return Response.json({ error: 'JSON inválido' }, { status: 400 })
  }

  const evento = String(payload.evento || payload.event || payload.tipo || payload.type || '')

  const isLead = evento.toLowerCase().includes('vend') ||
                 evento.toLowerCase().includes('lead') ||
                 evento.toLowerCase().includes('card') ||
                 payload.lead !== undefined || payload.card !== undefined

  const isMeta = evento.toLowerCase().includes('meta') ||
                 evento.toLowerCase().includes('goal') ||
                 payload.meta !== undefined

  const resultados: any = { evento, processado: [] }

  // ── Processa Lead ────────────────────────────────────────────────
  if (isLead) {
    let lead: any
    try {
      lead = normalizarLead(payload)
    } catch (err: any) {
      return Response.json({ error: `Lead inválido: ${err.message}` }, { status: 422 })
    }

    const { data: leadSalvo, error: errLead } = await sb
      .from('orion_leads_vendidos')
      .insert(lead)
      .select()
      .single()

    if (!errLead && leadSalvo) {
      const { data: existe } = await sb.from('revendas')
        .select('id').eq('id_origem', lead.id_origem).single()

      if (!existe) {
        const { data: novaRev } = await sb.from('revendas').insert({
          nome: lead.nome, email: lead.email, tel: lead.telefone,
          cidade: lead.cidade, uf: lead.uf, cs: lead.cs, obs: lead.obs,
          id_origem: lead.id_origem, status: 'Nova Revenda', ingresso: lead.ingresso,
        }).select().single()

        if (novaRev) {
          await sb.from('historico_cards').insert({
            revenda_id:   novaRev.id,
            tipo:         'Integração Orion',
            descricao:    `Lead importado do Orion CRM. Evento: ${evento}`,
            manual:       false,
            usuario_nome: 'Sistema / Orion CRM',
          })
          await sb.from('auditoria').insert({
            acao: 'CREATE', tabela: 'revendas', registro_id: novaRev.id,
            usuario_nome: 'Sistema / Orion',
            detalhe: { origem: 'webhook_orion', evento, nome: lead.nome }
          })
        }
      }
      resultados.processado.push({ tipo: 'lead', id: leadSalvo.id, nome: lead.nome })
    } else if (errLead) {
      resultados.erro_lead = errLead.message
    }
  }

  // ── Processa Meta ────────────────────────────────────────────────
  if (isMeta) {
    let meta: any
    try {
      meta = normalizarMeta(payload)
    } catch (err: any) {
      return Response.json({ error: `Meta inválida: ${err.message}` }, { status: 422 })
    }

    const pct = meta.valor_meta > 0
      ? Math.round((meta.valor_atual / meta.valor_meta) * 100)
      : 0

    const { data: metaSalva, error: errMeta } = await sb.from('orion_metas').upsert({
      nome: meta.nome, tipo: meta.tipo,
      valor_meta: meta.valor_meta, valor_atual: meta.valor_atual,
      percentual: pct, mes: meta.mes, ano: meta.ano,
      status: pct >= 100 ? 'atingida' : pct >= 70 ? 'atencao' : 'critica',
      _orion_raw: meta._orion_raw,
      atualizado_em: new Date().toISOString(),
    }, { onConflict: 'nome,mes,ano' }).select().single()

    if (!errMeta) {
      resultados.processado.push({ tipo: 'meta', nome: meta.nome, percentual: pct })
    } else {
      resultados.erro_meta = errMeta.message
    }
  }

  if (!isLead && !isMeta) {
    await sb.from('orion_eventos_raw').insert({
      evento, payload: JSON.stringify(payload).slice(0, 8000),
    })
    resultados.aviso = 'Evento não reconhecido — salvo para análise'
  }

  return Response.json({ success: true, ...resultados }, { headers: corsHeaders })
})

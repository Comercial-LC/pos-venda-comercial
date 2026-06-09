// ═══════════════════════════════════════════════════════════════════
// Supabase Edge Function — receptor de webhooks da Orion CRM
// Deploy: supabase functions deploy webhook-orion
// ═══════════════════════════════════════════════════════════════════
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ORION_WEBHOOK_SECRET = Deno.env.get('ORION_WEBHOOK_SECRET')!  // chave secreta

// ── Chave gerada (SHA-256 HMAC) ──────────────────────────────────
async function verificarAssinatura(req: Request, body: string): Promise<boolean> {
  // Aceita token via header OU via query string (?token=...)
  const url = new URL(req.url)
  const sigHeader = req.headers.get('x-orion-signature') ||
                    req.headers.get('x-webhook-secret')  ||
                    req.headers.get('authorization')?.replace('Bearer ','') ||
                    url.searchParams.get('token')         ||
                    url.searchParams.get('secret')        ||
                    url.searchParams.get('key')
  if (!sigHeader) return false

  // Suporta dois modos:
  // 1. Token simples: header === ORION_WEBHOOK_SECRET
  // 2. HMAC-SHA256: header === HMAC(secret, body)
  if (sigHeader === ORION_WEBHOOK_SECRET) return true

  // Verifica HMAC
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(ORION_WEBHOOK_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false, ['verify']
  )
  const bodyBytes = new TextEncoder().encode(body)
  const sigBytes  = hexToBytes(sigHeader.replace('sha256=',''))
  try {
    return await crypto.subtle.verify('HMAC', key, sigBytes, bodyBytes)
  } catch { return false }
}

function hexToBytes(hex: string): Uint8Array {
  const arr = new Uint8Array(hex.length / 2)
  for (let i = 0; i < arr.length; i++)
    arr[i] = parseInt(hex.slice(i*2, i*2+2), 16)
  return arr
}

// ── Normaliza campos do lead vindos da Orion ─────────────────────
function normalizarLead(payload: any): any {
  // Suporta diferentes formatos que a Orion pode enviar
  const lead = payload.lead || payload.data || payload.card || payload
  return {
    nome:      lead.empresa || lead.company || lead.nome || lead.name || '',
    email:     lead.email   || '',
    telefone:  lead.telefone || lead.phone || lead.tel || '',
    cidade:    lead.cidade  || lead.city   || '',
    uf:        lead.uf      || lead.estado || lead.state || '',
    cs:        lead.responsavel || lead.responsible || lead.vendedor || '',
    obs:       lead.observacao  || lead.observation || lead.notes || '',
    id_origem: lead.id?.toString() || lead.lead_id?.toString() || '',
    status:    'Nova Revenda',
    ingresso:  new Date().toISOString().slice(0,10),
    criado_em: new Date().toISOString(),
    // Campos extras preservados para rastreabilidade
    _orion_raw: lead,
  }
}

// ── Normaliza meta vinda da Orion ────────────────────────────────
function normalizarMeta(payload: any): any {
  const meta = payload.meta || payload.data || payload
  return {
    nome:       meta.nome        || meta.name  || meta.titulo || 'Meta Comercial',
    tipo:       meta.tipo        || meta.type  || 'quantidade',
    valor_meta: meta.valor_meta  || meta.meta  || meta.objetivo || meta.target || 0,
    valor_atual:meta.valor_atual || meta.atual || meta.current  || meta.realizado || 0,
    mes:        meta.mes         || meta.month || new Date().getMonth() + 1,
    ano:        meta.ano         || meta.year  || new Date().getFullYear(),
    status:     meta.status      || meta.situacao || '',
    percentual: meta.percentual  || meta.percent  || null,
    _orion_raw: meta,
  }
}

// ── Handler principal ────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  // CORS para o dashboard poder consultar
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-orion-signature, x-webhook-secret',
      }
    })
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE)

  // ── GET /webhook-orion?tipo=metas — dashboard busca metas ───────
  if (req.method === 'GET') {
    const url    = new URL(req.url)
    const tipo   = url.searchParams.get('tipo')
    const mes    = url.searchParams.get('mes')    || new Date().getMonth() + 1
    const ano    = url.searchParams.get('ano')    || new Date().getFullYear()

    if (tipo === 'metas') {
      const { data, error } = await sb
        .from('orion_metas')
        .select('*')
        .eq('mes', mes)
        .eq('ano', ano)
        .order('criado_em', { ascending: false })
      return Response.json({ success: true, data: data || [] }, {
        headers: { 'Access-Control-Allow-Origin': '*' }
      })
    }

    if (tipo === 'leads_vendidos') {
      const { data, error } = await sb
        .from('orion_leads_vendidos')
        .select('*')
        .order('criado_em', { ascending: false })
        .limit(50)
      return Response.json({ success: true, data: data || [] }, {
        headers: { 'Access-Control-Allow-Origin': '*' }
      })
    }

    return Response.json({ ok: true, msg: 'Webhook Orion ativo' }, {
      headers: { 'Access-Control-Allow-Origin': '*' }
    })
  }

  // ── POST — recebe evento da Orion ────────────────────────────────
  if (req.method !== 'POST') {
    return Response.json({ error: 'Método não permitido' }, { status: 405 })
  }

  const rawBody = await req.text()

  // ── Valida assinatura ────────────────────────────────────────────
  const autorizado = await verificarAssinatura(req, rawBody)
  if (!autorizado) {
    // Log da tentativa não autorizada
    await sb.from('auditoria').insert({
      acao: 'WEBHOOK_UNAUTHORIZED',
      tabela: 'webhook_orion',
      detalhe: {
        ip: req.headers.get('x-forwarded-for') || 'unknown',
        headers: Object.fromEntries(req.headers.entries()),
      }
    })
    return Response.json({ error: 'Não autorizado' }, { status: 401 })
  }

  let payload: any
  try {
    payload = JSON.parse(rawBody)
  } catch {
    return Response.json({ error: 'JSON inválido' }, { status: 400 })
  }

  // ── Detecta tipo de evento ───────────────────────────────────────
  const evento = payload.evento   || payload.event   ||
                 payload.tipo     || payload.type     || ''

  const isLead = evento.toLowerCase().includes('vend') ||
                 evento.toLowerCase().includes('lead') ||
                 evento.toLowerCase().includes('card') ||
                 payload.lead !== undefined ||
                 payload.card !== undefined

  const isMeta = evento.toLowerCase().includes('meta') ||
                 evento.toLowerCase().includes('goal') ||
                 payload.meta !== undefined

  const resultados: any = { evento, processado: [] }

  // ── Processa Lead Vendido ────────────────────────────────────────
  if (isLead) {
    const lead = normalizarLead(payload)

    // Salva na tabela de leads vindos da Orion
    const { data: leadSalvo, error: errLead } = await sb
      .from('orion_leads_vendidos')
      .insert({ ...lead, _orion_raw: JSON.stringify(lead._orion_raw) })
      .select()
      .single()

    if (!errLead && leadSalvo) {
      // Cria automaticamente na tabela de revendas se não existir
      const { data: existe } = await sb
        .from('revendas')
        .select('id')
        .eq('id_origem', lead.id_origem)
        .single()

      if (!existe && lead.nome) {
        const { data: novaRev } = await sb
          .from('revendas')
          .insert({
            nome:      lead.nome,
            email:     lead.email,
            tel:       lead.telefone,
            cidade:    lead.cidade,
            uf:        lead.uf,
            cs:        lead.cs,
            obs:       lead.obs,
            id_origem: lead.id_origem,
            status:    'Nova Revenda',
            ingresso:  lead.ingresso,
          })
          .select()
          .single()

        // Log no histórico
        if (novaRev) {
          await sb.from('historico_cards').insert({
            revenda_id:   novaRev.id,
            tipo:         'Integração Orion',
            descricao:    `Lead importado automaticamente do Orion CRM. Evento: ${evento}`,
            manual:       false,
            usuario_nome: 'Sistema / Orion CRM',
          })
          // Log de auditoria
          await sb.from('auditoria').insert({
            acao: 'CREATE',
            tabela: 'revendas',
            registro_id: novaRev.id,
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
    const meta = normalizarMeta(payload)
    const pct  = meta.percentual ??
                 (meta.valor_meta > 0
                   ? Math.round((meta.valor_atual / meta.valor_meta) * 100)
                   : 0)

    // Upsert: atualiza se já existe meta do mesmo mês/ano/nome
    const { data: metaSalva, error: errMeta } = await sb
      .from('orion_metas')
      .upsert({
        nome:        meta.nome,
        tipo:        meta.tipo,
        valor_meta:  meta.valor_meta,
        valor_atual: meta.valor_atual,
        percentual:  pct,
        mes:         meta.mes,
        ano:         meta.ano,
        status:      pct >= 100 ? 'atingida' : pct >= 70 ? 'atencao' : 'critica',
        _orion_raw:  JSON.stringify(meta._orion_raw),
        atualizado_em: new Date().toISOString(),
      }, { onConflict: 'nome,mes,ano' })
      .select()
      .single()

    if (!errMeta) {
      resultados.processado.push({ tipo: 'meta', nome: meta.nome, percentual: pct })
    } else {
      resultados.erro_meta = errMeta.message
    }
  }

  if (!isLead && !isMeta) {
    // Salva evento desconhecido para análise
    await sb.from('orion_eventos_raw').insert({
      evento,
      payload: JSON.stringify(payload),
      criado_em: new Date().toISOString()
    })
    resultados.aviso = 'Evento não reconhecido — salvo para análise'
  }

  return Response.json({ success: true, ...resultados }, {
    headers: { 'Access-Control-Allow-Origin': '*' }
  })
})

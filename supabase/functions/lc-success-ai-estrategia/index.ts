// ═══════════════════════════════════════════════════════════════════
// Supabase Edge Function — LC Success AI: Estratégia do Mês
// Recebe o resumo do portfólio (já agregado no frontend, a partir do
// mesmo motor de classificação da Análise do Mês) + a meta comercial
// do mês, e devolve um plano estratégico pra bater a meta.
// Deploy: supabase functions deploy lc-success-ai-estrategia
// ═══════════════════════════════════════════════════════════════════
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL        = Deno.env.get('SUPABASE_URL')
const SUPABASE_SERVICE    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const GEMINI_API_KEY      = Deno.env.get('GEMINI_API_KEY')
const GEMINI_MODEL        = Deno.env.get('GEMINI_MODEL') || 'gemini-3.6-flash'
const ALLOWED_ORIGINS_RAW = Deno.env.get('ALLOWED_ORIGINS') || ''

if (!SUPABASE_URL || !SUPABASE_SERVICE || !GEMINI_API_KEY) {
  throw new Error(
    'Variáveis obrigatórias ausentes: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY'
  )
}

const ALLOWED_ORIGINS: string[] = ALLOWED_ORIGINS_RAW
  ? ALLOWED_ORIGINS_RAW.split(',').map(o => o.trim()).filter(Boolean)
  : []

function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') || ''
  const allowed = ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin)
  return {
    'Access-Control-Allow-Origin':  allowed ? origin : 'null',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Vary': 'Origin',
  }
}

const SYSTEM_PROMPT = `Você é o LC Success AI, especialista em sucesso de parceiros, gestão comercial, crescimento de revendas e desenvolvimento de canais de distribuição da LC Sistemas.

Agora sua função é olhar o PORTFÓLIO INTEIRO de revendas (não uma revenda isolada) e propor a melhor estratégia para o time de pós-venda bater a meta comercial do mês.

Você recebe um resumo já agregado: a meta do mês, a distribuição das revendas por prioridade comercial (P1 Quente, P2 Em desenvolvimento, P3 Acompanhamento, P4 Risco), a lista de revendas com cliente previsto ou em negociação, e a lista de revendas mais críticas (P1 e P4) com seus sinais mais recentes.

Você deve utilizar exclusivamente os dados fornecidos. Nunca invente nomes de revendas, números ou resultados que não estejam no resumo recebido. Quando os dados forem insuficientes para alguma conclusão, declare isso claramente.

Priorize uma estratégia prática e acionável para ESTE MÊS especificamente: onde concentrar esforço agora, quais revendas atacar primeiro, o que fazer com o grupo de risco (P4) para não perder ainda mais terreno, e como usar as oportunidades já identificadas (cliente previsto/em negociação) pra fechar o gap até a meta.

Sua resposta deve ser objetiva, estruturada e voltada para decisão da equipe comercial e de pós-venda.`

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    resumo_executivo:        { type: 'STRING' },
    probabilidade_meta:      { type: 'STRING', enum: ['BAIXA', 'MÉDIA', 'ALTA'] },
    justificativa_probabilidade: { type: 'STRING' },
    focos_prioritarios:      { type: 'ARRAY', items: { type: 'STRING' } },
    revendas_para_agir_agora: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          revenda: { type: 'STRING' },
          motivo:  { type: 'STRING' },
          acao:    { type: 'STRING' },
        },
        required: ['revenda', 'motivo', 'acao'],
      },
    },
    alavancas_rapidas:       { type: 'ARRAY', items: { type: 'STRING' } },
    riscos:                  { type: 'ARRAY', items: { type: 'STRING' } },
    plano_de_acao: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          prioridade:           { type: 'STRING', enum: ['ALTA', 'MÉDIA', 'BAIXA'] },
          acao:                 { type: 'STRING' },
          responsavel_sugerido: { type: 'STRING' },
          prazo:                { type: 'STRING' },
          objetivo:             { type: 'STRING' },
        },
        required: ['prioridade', 'acao', 'objetivo'],
      },
    },
    confianca_da_analise:    { type: 'STRING', enum: ['BAIXA', 'MÉDIA', 'ALTA'] },
    dados_insuficientes:     { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: [
    'resumo_executivo', 'probabilidade_meta', 'justificativa_probabilidade',
    'focos_prioritarios', 'revendas_para_agir_agora', 'alavancas_rapidas',
    'riscos', 'plano_de_acao', 'confianca_da_analise', 'dados_insuficientes',
  ],
}

async function chamarGemini(contexto: string): Promise<any> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`

  const body = {
    system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [{ role: 'user', parts: [{ text: `Resumo do portfólio para gerar a estratégia do mês:\n\n${contexto}` }] }],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: RESPONSE_SCHEMA,
      temperature: 0.4,
      thinkingConfig: { thinkingBudget: 0 }, // sem raciocínio estendido — tarefa é síntese estruturada, não precisa
    },
  }

  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), 55000)

  let resp: Response
  try {
    resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    })
  } catch (err: any) {
    if (err.name === 'AbortError') throw new Error('TIMEOUT: Gemini não respondeu em 30s')
    throw new Error(`Falha de rede ao chamar Gemini: ${err.message}`)
  } finally {
    clearTimeout(timeoutId)
  }

  if (!resp.ok) {
    const errText = await resp.text().catch(() => '')
    throw new Error(`Gemini retornou erro ${resp.status}: ${errText.slice(0, 300)}`)
  }

  const json = await resp.json()
  const textoResposta = json.candidates?.[0]?.content?.parts?.[0]?.text
  if (!textoResposta) throw new Error('Gemini não retornou conteúdo utilizável (resposta vazia ou bloqueada)')

  let analise: any
  try {
    analise = JSON.parse(textoResposta)
  } catch {
    throw new Error('Resposta do Gemini não é um JSON válido')
  }

  for (const campo of RESPONSE_SCHEMA.required) {
    if (!(campo in analise)) throw new Error(`Resposta do Gemini sem o campo obrigatório: ${campo}`)
  }

  return analise
}

Deno.serve(async (req: Request) => {
  const corsHeaders = buildCorsHeaders(req)

  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return Response.json({ error: 'Método não permitido' }, { status: 405, headers: corsHeaders })
  }

  const sb = createClient(SUPABASE_URL!, SUPABASE_SERVICE!)

  const authHeader = req.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return Response.json({ error: 'Autenticação necessária' }, { status: 401, headers: corsHeaders })
  }
  const { data: { user }, error: authErr } = await sb.auth.getUser(authHeader.slice(7))
  if (authErr || !user) {
    return Response.json({ error: 'Token inválido' }, { status: 401, headers: corsHeaders })
  }

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return Response.json({ error: 'JSON inválido' }, { status: 400, headers: corsHeaders })
  }

  const mes    = Number(payload.mes)
  const ano    = Number(payload.ano)
  const resumo = payload.resumo // string já pronta, montada no frontend a partir da Análise do Mês

  if (!mes || !ano || !resumo || typeof resumo !== 'string') {
    return Response.json({ error: 'mes, ano e resumo são obrigatórios' }, { status: 400, headers: corsHeaders })
  }
  if (resumo.length > 20000) {
    return Response.json({ error: 'Resumo excede o tamanho máximo permitido' }, { status: 400, headers: corsHeaders })
  }

  const { data: perfil } = await sb.from('perfis').select('nome').eq('id', user.id).maybeSingle()

  let analise: any = null
  let status = 'sucesso'
  let erroMsg: string | null = null

  try {
    analise = await chamarGemini(resumo)
  } catch (err: any) {
    status = 'erro'
    erroMsg = err.message
    console.error('lc-success-ai-estrategia: falha ao chamar Gemini —', err.message)
  }

  const { data: registro, error: errInsert } = await sb.from('analises_estrategia_mes').insert({
    mes, ano,
    modelo: GEMINI_MODEL,
    resultado_completo: analise,
    dados_utilizados: { resumo },
    status,
    erro_mensagem: erroMsg,
    usuario_id: user.id,
    usuario_nome: perfil?.nome || user.email || 'Desconhecido',
  }).select().single()

  if (errInsert) {
    console.error('lc-success-ai-estrategia: falha ao gravar —', errInsert.message)
    return Response.json({ error: 'Erro ao salvar estratégia' }, { status: 500, headers: corsHeaders })
  }

  if (status === 'erro') {
    return Response.json({ error: 'Não foi possível gerar a estratégia. Tente novamente em instantes.', analise_id: registro.id }, { status: 502, headers: corsHeaders })
  }

  return Response.json({ success: true, analise_id: registro.id, analise }, { headers: corsHeaders })
})

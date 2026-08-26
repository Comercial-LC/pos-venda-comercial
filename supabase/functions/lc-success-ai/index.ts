// ═══════════════════════════════════════════════════════════════════
// Supabase Edge Function — LC Success AI
// Analisa uma revenda com dados reais e retorna diagnóstico estruturado.
// Deploy: supabase functions deploy lc-success-ai
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

// ── Rótulos das tags comerciais (Análise do Mês) para o contexto ────
const TAGS_LABEL: Record<string, string> = {
  TREINAMENTO: 'Treinamento', PROSPECCAO: 'Prospecção', DEMONSTRACAO: 'Demonstração',
  CLIENTE_EM_NEGOCIACAO: 'Cliente em negociação', CLIENTE_PREVISTO: 'Cliente previsto',
  CLIENTE_SUBIDO: 'Cliente subido/ativado', INSTALACAO: 'Instalação', SEM_RETORNO: 'Sem retorno',
  SEM_PREVISAO: 'Sem previsão', PAUSADO: 'Pausado', DIFICULDADE: 'Dificuldade comercial',
  DOENCA_AUSENCIA: 'Doença/Ausência', PROMESSA_SEM_EVOLUCAO: 'Promessa sem evolução',
  NAO_RESPONDE: 'Não responde', OUTROS: 'Outros',
}

function diasEntre(a: Date, b: Date): number {
  return Math.round((b.getTime() - a.getTime()) / 86400000)
}

// ── Monta o contexto textual só com dados reais — nunca inventa ─────
function montarContexto(revenda: any, historico: any[]): { texto: string; dadosFaltando: string[] } {
  const hoje = new Date()
  const linhas: string[] = []
  const dadosFaltando: string[] = []

  linhas.push(`ID: ${revenda.id}`)
  linhas.push(`Nome: ${revenda.nome || 'não informado'}`)
  linhas.push(`Cidade/UF: ${revenda.cidade || 'não informado'}/${revenda.uf || '—'}`)
  linhas.push(`Status atual (etapa do pipeline): ${revenda.status || 'não informado'}`)

  if (revenda.ingresso) {
    const dias = diasEntre(new Date(revenda.ingresso), hoje)
    linhas.push(`Data de início da parceria: ${revenda.ingresso} (${dias} dias de parceria)`)
  } else {
    linhas.push(`Data de início da parceria: não informado`)
    dadosFaltando.push('data de início da parceria')
  }

  linhas.push(`Contratos ativos: ${revenda.contratos ?? 'não informado'}`)
  if (revenda.contratos == null) dadosFaltando.push('quantidade de contratos')

  linhas.push(`Curva ABC: ${revenda.curva || 'não informado'}`)

  if (Array.isArray(revenda.produtos) && revenda.produtos.length) {
    linhas.push(`Produtos: ${revenda.produtos.join(', ')}`)
  } else {
    linhas.push(`Produtos: nenhum produto registrado`)
    dadosFaltando.push('produtos ativos/vendidos')
  }

  if (historico.length) {
    const ultimo = historico[0]
    const diasSemInteracao = diasEntre(new Date(ultimo.criado_em), hoje)
    linhas.push(`\nÚltima interação registrada: ${ultimo.criado_em} (${diasSemInteracao} dia(s) atrás)`)
    linhas.push(`Tipo da última interação: ${ultimo.tipo || 'não classificado'}`)

    linhas.push(`\nHistórico recente (mais novo primeiro, até 20 registros de ${historico.length} totais):`)
    historico.slice(0, 20).forEach((h: any) => {
      const tagLabel = h.tag ? (TAGS_LABEL[h.tag] || h.tag) : null
      const data = String(h.criado_em || '').slice(0, 10)
      linhas.push(`- [${data}] ${h.tipo || ''}${tagLabel ? ` (sinal comercial: ${tagLabel})` : ''}: ${h.descricao || '(sem descrição)'}`)
    })

    const contagemTag: Record<string, number> = {}
    historico.forEach((h: any) => { if (h.tag) contagemTag[h.tag] = (contagemTag[h.tag] || 0) + 1 })
    if (Object.keys(contagemTag).length) {
      linhas.push(`\nResumo de sinais comerciais em todo o histórico:`)
      Object.entries(contagemTag).forEach(([tag, n]) => linhas.push(`- ${TAGS_LABEL[tag] || tag}: ${n} registro(s)`))
    }
  } else {
    linhas.push(`\nHistórico: nenhum registro encontrado para esta revenda.`)
    dadosFaltando.push('histórico de interações/contatos')
  }

  linhas.push(
    `\nOBSERVAÇÃO DO SISTEMA: este portal não possui campo dedicado para "quantidade de clientes ativos", ` +
    `"novos clientes por mês", "resultados anteriores/metas por revenda" nem "trilhas de treinamento vinculadas à revenda". ` +
    `Use apenas os sinais do histórico acima como proxy para essas informações, e liste-as em dados_insuficientes quando relevante — não estime nem invente números para elas.`
  )

  if (dadosFaltando.length) {
    linhas.push(`\nDados que NÃO estão disponíveis no sistema para esta revenda: ${dadosFaltando.join(', ')}.`)
  }

  return { texto: linhas.join('\n'), dadosFaltando }
}

const SYSTEM_PROMPT = `Você é o LC Success AI, especialista em sucesso de parceiros, gestão comercial, crescimento de revendas e desenvolvimento de canais de distribuição da LC Sistemas.

Sua função é analisar dados reais das revendas e identificar o estágio atual da parceria, riscos, gargalos, oportunidades e as melhores ações para aumentar o engajamento, a ativação de clientes e o crescimento da revenda.

Você deve utilizar exclusivamente os dados fornecidos. Nunca invente informações, resultados, vendas ou comportamentos que não estejam presentes nos dados. Quando os dados forem insuficientes, declare claramente quais informações estão faltando.

Priorize análises práticas e acionáveis.

Considere como objetivos estratégicos:
- Ativação do primeiro cliente.
- Aumento da quantidade de clientes ativos.
- Crescimento de vendas.
- Engajamento da revenda.
- Conclusão de treinamentos.
- Aumento da recorrência.
- Identificação de oportunidades dos produtos da LC.
- Redução do risco de inatividade.
- Definição da próxima melhor ação.

Sua resposta deve ser objetiva, estruturada e voltada para a tomada de decisão da equipe comercial e de pós-venda.`

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    score_saude:            { type: 'INTEGER' },
    nivel_risco:            { type: 'STRING', enum: ['BAIXO', 'MÉDIO', 'ALTO', 'CRÍTICO'] },
    resumo_executivo:       { type: 'STRING' },
    estagio_revenda:        { type: 'STRING' },
    principais_gargalos:    { type: 'ARRAY', items: { type: 'STRING' } },
    oportunidades:          { type: 'ARRAY', items: { type: 'STRING' } },
    pontos_positivos:       { type: 'ARRAY', items: { type: 'STRING' } },
    sinais_de_alerta:       { type: 'ARRAY', items: { type: 'STRING' } },
    proxima_melhor_acao:    { type: 'STRING' },
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
    produtos_com_oportunidade: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          produto:       { type: 'STRING' },
          justificativa: { type: 'STRING' },
        },
        required: ['produto', 'justificativa'],
      },
    },
    abordagem_sugerida:     { type: 'STRING' },
    confianca_da_analise:   { type: 'STRING', enum: ['BAIXA', 'MÉDIA', 'ALTA'] },
    dados_insuficientes:    { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: [
    'score_saude', 'nivel_risco', 'resumo_executivo', 'estagio_revenda',
    'principais_gargalos', 'oportunidades', 'pontos_positivos', 'sinais_de_alerta',
    'proxima_melhor_acao', 'plano_de_acao', 'abordagem_sugerida',
    'confianca_da_analise', 'dados_insuficientes',
  ],
}

// ── Chamada ao Gemini via REST (evita depender de compatibilidade de
// SDK npm no runtime Deno — mesmo contrato de dados, menos peças móveis) ──
async function chamarGemini(contexto: string): Promise<any> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`

  const body = {
    system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [{ role: 'user', parts: [{ text: `Analise os dados reais abaixo desta revenda parceira e gere a análise estruturada conforme o schema.\n\n${contexto}` }] }],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: RESPONSE_SCHEMA,
      temperature: 0.4,
    },
  }

  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), 55000) // 55s

  let resp: Response
  try {
    resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    })
  } catch (err: any) {
    if (err.name === 'AbortError') throw new Error('TIMEOUT: Gemini não respondeu em 55s')
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
  if (typeof analise.score_saude !== 'number' || analise.score_saude < 0 || analise.score_saude > 100) {
    throw new Error('score_saude inválido na resposta do Gemini')
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

  // ── Autenticação: só usuário logado no portal pode chamar ──────────
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

  const revendaId     = String(payload.revenda_id || '').trim()
  const triggerOrigem = String(payload.trigger || 'manual')
  if (!revendaId) {
    return Response.json({ error: 'revenda_id é obrigatório' }, { status: 400, headers: corsHeaders })
  }

  const { data: perfil } = await sb.from('perfis').select('nome').eq('id', user.id).maybeSingle()

  const { data: revenda, error: errRevenda } = await sb.from('revendas').select('*').eq('id', revendaId).single()
  if (errRevenda || !revenda) {
    return Response.json({ error: 'Revenda não encontrada' }, { status: 404, headers: corsHeaders })
  }

  const { data: historicoData } = await sb.from('historico_cards')
    .select('tipo,tag,descricao,criado_em,manual')
    .eq('revenda_id', revendaId)
    .order('criado_em', { ascending: false })
    .limit(50)
  const historico = historicoData || []

  const { texto: contexto, dadosFaltando } = montarContexto(revenda, historico)

  let analise: any = null
  let status = 'sucesso'
  let erroMsg: string | null = null

  try {
    analise = await chamarGemini(contexto)
  } catch (err: any) {
    status = 'erro'
    erroMsg = err.message
    console.error('lc-success-ai: falha ao chamar Gemini —', err.message) // log técnico, sem dados sensíveis
  }

  const { data: registro, error: errInsert } = await sb.from('analises_ia').insert({
    revenda_id: revendaId,
    modelo: GEMINI_MODEL,
    score_saude: analise?.score_saude ?? null,
    nivel_risco: analise?.nivel_risco ?? null,
    resultado_completo: analise,
    dados_utilizados: { contexto, dados_faltando_detectados: dadosFaltando },
    status,
    erro_mensagem: erroMsg,
    trigger_origem: triggerOrigem,
    usuario_id: user.id,
    usuario_nome: perfil?.nome || user.email || 'Desconhecido',
  }).select().single()

  if (errInsert) {
    console.error('lc-success-ai: falha ao gravar análise —', errInsert.message)
    return Response.json({ error: 'Erro ao salvar análise' }, { status: 500, headers: corsHeaders })
  }

  if (status === 'erro') {
    return Response.json({ error: 'Não foi possível gerar a análise. Tente novamente em instantes.', analise_id: registro.id }, { status: 502, headers: corsHeaders })
  }

  // ── Referência resumida no histórico geral (tipo, não tag comercial —
  // não interfere no motor P1-P4 da Análise do Mês) ───────────────────
  await sb.from('historico_cards').insert({
    revenda_id: revendaId,
    tipo: '🤖 LC Success AI',
    descricao: `Análise automática realizada. Score: ${analise.score_saude}/100. Risco: ${analise.nivel_risco}. Principal ação: ${analise.proxima_melhor_acao}`,
    manual: false,
    usuario_id: user.id,
    usuario_nome: perfil?.nome || user.email || 'Sistema',
  }).then(({ error }) => { if (error) console.error('lc-success-ai: falha ao registrar no histórico —', error.message) })

  return Response.json({ success: true, analise_id: registro.id, analise }, { headers: corsHeaders })
})

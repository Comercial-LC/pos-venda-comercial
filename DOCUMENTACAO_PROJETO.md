# Portal Revenda LC — Documentação Técnica Completa

> Sistema de gestão de onboarding e pós-venda de revendas, integrado ao Orion CRM.  
> Última atualização: junho/2026

---

## Sumário

1. [Estrutura Completa do Sistema](#1-estrutura-completa-do-sistema)
2. [Fluxo de Autenticação](#2-fluxo-de-autenticação)
3. [Tabelas do Supabase](#3-tabelas-do-supabase)
4. [Relacionamentos](#4-relacionamentos)
5. [Edge Functions](#5-edge-functions)
6. [Como Executar Localmente](#6-como-executar-localmente)
7. [Melhorias Recomendadas](#7-melhorias-recomendadas)

---

## 1. Estrutura Completa do Sistema

### 1.1 Visão Geral da Stack

| Camada | Tecnologia |
|--------|-----------|
| Frontend | HTML5 + CSS3 + Vanilla JavaScript (SPA monolítica) |
| Autenticação | Supabase Auth (email/password) |
| Banco de Dados | PostgreSQL via Supabase |
| Backend lógico | RLS (Row Level Security) + Triggers + Views |
| Serverless | Supabase Edge Functions (Deno/TypeScript) |
| Integração CRM | Orion (webhook receptor) |
| Gráficos | Canvas API (implementação própria) |
| Export/Import | SheetJS (XLSX) via CDN |

**Não há build system, bundler ou framework frontend.** Todo o código é entregue diretamente pelos arquivos `.html` com JavaScript inline.

---

### 1.2 Arquivos do Projeto

```
c:/pos-venda-comercial/
│
├── index.html                          # Tela de login/registro/recuperação de senha
├── app.html                            # SPA principal (~280 KB, JS+CSS+HTML inline)
│
├── supabase_setup.sql                  # Setup inicial do banco (tabelas, RLS, triggers, views)
├── rls_e_tabelas_orion.sql             # Extensão: tabelas Orion + RLS revisado + índices
│
└── supabase/
    └── functions/
        └── webhook-orion/
            └── index.ts               # Edge Function: receptor de webhooks do Orion CRM
```

---

### 1.3 Frontend — index.html (Autenticação)

Arquivo leve (~13 KB) com três telas em um único HTML:

| Tela | Disparada por |
|------|--------------|
| Login | Estado padrão |
| Registro | Clique em "Criar conta" |
| Recuperação de senha | Clique em "Esqueci minha senha" |

**Funções JavaScript principais:**

| Função | Responsabilidade |
|--------|-----------------|
| `doLogin()` | Autenticação email/senha via `supabase.auth.signInWithPassword` |
| `doRegister()` | Criação de conta via `supabase.auth.signUp` + metadados de nome |
| `doForgot()` | Envio de e-mail de reset via `supabase.auth.resetPasswordForEmail` |
| `checkStrength()` | Validação visual de força de senha (4 critérios) |
| `togglePass()` | Alternância de visibilidade do campo senha |

Ao carregar, verifica sessão ativa (`supabase.auth.getSession`) e redireciona automaticamente para `app.html` se já autenticado.

---

### 1.4 Frontend — app.html (SPA Principal)

Aplicação de página única com sidebar + topbar + área de conteúdo. Cada seção é um `<div id="p-*">` alternado via JavaScript.

#### Painéis da aplicação

| ID do Painel | Seção | Funcionalidades |
|---|---|---|
| `p-dashboard` | Dashboard | KPIs, gráficos Canvas, metas Orion, TPC, revendas recentes |
| `p-revendas` | Revendas | CRUD completo, busca, filtros por status/UF/CS, paginação |
| `p-pipeline` | Pipeline Kanban | Drag-and-drop por status, batch actions, filtros avançados |
| `p-tarefas` | Tarefas | CRUD, urgentes/atrasadas, prioridades, vencimento |
| `p-metas` | Metas | Metas manuais + integração Orion, seletor mês/ano |
| `p-timeline` | Timeline | Histórico de atividades em linha do tempo |
| `p-treinamentos` | Treinamentos | Trilhas, taxa de conclusão, progresso por revenda |
| `p-handover` | Handover | Checklist de transferência, progresso por etapa |
| `p-relatorios` | Relatórios | Analytics, performance por CS, exportação Excel |
| `p-importacao` | Importação | Upload .xlsx/.xls/.csv, controle de duplicatas |
| `p-usuarios` | Usuários | Gestão de usuários, perfis, permissões granulares |
| `p-configuracoes` | Configurações | Ajustes gerais, configuração de integrações |

#### Status do Pipeline (em ordem)

```
Nova Revenda → Implantação → Liberação Web → Academy →
Decola Instalação → Decola Produtos → Primeiro Cliente → Handover
```

#### Design System

- **Tema**: Dark mode padrão, com toggle para Light mode
- **Paleta principal**:
  - Fundo escuro: `#0A0A0F`
  - Accent: `#F5C518` (amarelo)
  - Destaque: `#6B2FA0` (roxo)
- **Breakpoint responsivo**: 900px
- **Componentes**: Cards, badges de status, toasts, modais, tabelas com sticky header, paginação

---

### 1.5 Configuração do Supabase

| Parâmetro | Valor |
|-----------|-------|
| URL do projeto | `https://vykhskaayukmodnglujc.supabase.co` |
| Anon Key | Definida inline em `index.html` e `app.html` |
| Service Role Key | Variável de ambiente `SUPABASE_SERVICE_ROLE_KEY` (apenas na Edge Function) |
| Webhook Secret | Variável de ambiente `ORION_WEBHOOK_SECRET` (apenas na Edge Function) |

**Bibliotecas carregadas via CDN:**
- `@supabase/supabase-js@2` — jsDelivr
- `xlsx@0.18.5` — cdnjs (SheetJS para Excel)

---

## 2. Fluxo de Autenticação

### 2.1 Registro de Novo Usuário

```
Usuário preenche nome + email + senha
          ↓
Validação local (força de senha, campos obrigatórios)
          ↓
supabase.auth.signUp({ email, password, options: { data: { nome } } })
          ↓
Supabase cria registro em auth.users
          ↓
Trigger: on_auth_user_created → handle_new_user()
          ↓
Cria perfil em public.perfis
  - Primeiro usuário do sistema → perfil = 'Administrador'
  - Demais usuários → perfil = 'CS Analyst'
          ↓
E-mail de confirmação enviado ao usuário
          ↓
Usuário confirma e-mail → sessão ativa → redireciona para app.html
```

### 2.2 Login

```
Usuário informa email + senha
          ↓
supabase.auth.signInWithPassword({ email, password })
          ↓
Supabase valida credenciais em auth.users
          ↓
RLS verifica: perfis.ativo = true
  - Inativo → acesso negado (erro de permissão)
          ↓
Log em auditoria: { acao: 'LOGIN', usuario_id, ip, user_agent }
          ↓
Sessão JWT armazenada no browser (localStorage)
          ↓
Redirecionamento para app.html
```

### 2.3 Recuperação de Senha

```
Usuário informa e-mail
          ↓
supabase.auth.resetPasswordForEmail(email, { redirectTo })
          ↓
Supabase envia e-mail com link de reset
          ↓
Usuário clica no link → redirecionado de volta para index.html
          ↓
app detecta hash #access_token → exibe formulário de nova senha
          ↓
supabase.auth.updateUser({ password: novaSenha })
```

### 2.4 Autorização (RLS + Permissões Granulares)

Cada query ao banco passa automaticamente pelo RLS do PostgreSQL:

```
Request com JWT do usuário
          ↓
PostgreSQL: auth.uid() extrai o UUID do usuário
          ↓
Função helper: estou_ativo()
  → SELECT ativo FROM perfis WHERE id = auth.uid()
          ↓
Função helper: meu_perfil()
  → SELECT perfil FROM perfis WHERE id = auth.uid()
          ↓
RLS Policy avaliada por tabela e operação (SELECT/INSERT/UPDATE/DELETE)
          ↓
Permissões granulares verificadas para ações sensíveis:
  pode_criar_revenda, pode_editar_revenda, pode_excluir_revenda,
  pode_ver_cnpj, pode_exportar, pode_importar,
  pode_gerenciar_usuarios, pode_ver_relatorios, pode_handover
```

---

## 3. Tabelas do Supabase

### 3.1 Tabelas do setup principal (`supabase_setup.sql`)

#### `public.perfis`
Estende `auth.users` com dados de perfil e permissões.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | Referência para `auth.users(id)` |
| `nome` | text | Nome exibido |
| `email` | text | E-mail do usuário |
| `perfil` | text | `Administrador` / `CS Manager` / `CS Analyst` / `Diretoria` |
| `ativo` | boolean | Acesso ao sistema habilitado |
| `avatar_iniciais` | text | Iniciais para avatar visual |
| `criado_em` | timestamptz | Data de criação |
| `atualizado_em` | timestamptz | Atualizado via trigger |
| `pode_criar_revenda` | boolean | Permissão granular |
| `pode_editar_revenda` | boolean | Permissão granular |
| `pode_excluir_revenda` | boolean | Permissão granular |
| `pode_ver_cnpj` | boolean | LGPD — dado sensível |
| `pode_exportar` | boolean | Permissão granular |
| `pode_importar` | boolean | Permissão granular |
| `pode_gerenciar_usuarios` | boolean | Permissão granular |
| `pode_ver_relatorios` | boolean | Permissão granular |
| `pode_handover` | boolean | Permissão granular |

---

#### `public.revendas`
Entidade central do sistema.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | Identificador único |
| `nome` | text | Razão social / nome fantasia |
| `cnpj` | text | Dado sensível (LGPD) — controlado por RLS |
| `cidade` | text | Cidade |
| `uf` | text | Estado (2 letras) |
| `email` | text | E-mail principal |
| `tel` / `tel2` / `tel3` | text | Telefones |
| `cs` | text | Nome do responsável CS (campo livre) |
| `cs_id` | uuid FK | Referência para `perfis(id)` |
| `status` | text | Status no pipeline (ver lista abaixo) |
| `segmento` | text | Segmento de mercado |
| `porte` | text | Tamanho da empresa |
| `contratos` | integer | Quantidade de contratos ativos |
| `curva` | text | Curva ABC do cliente |
| `pct_contratos` | numeric | % de contratos |
| `pct_cumulativo` | numeric | % cumulativo |
| `tpc` | integer | Tempo para Primeiro Cliente (dias) |
| `ingresso` | date | Data de entrada no pipeline |
| `obs` | text | Observações livres |
| `produtos` | text[] | Array de produtos |
| `id_origem` | text | ID externo (Orion CRM) |

**Valores de `status`:** `Nova Revenda`, `Implantação`, `Liberação Web`, `Academy`, `Decola Instalação`, `Decola Produtos`, `Primeiro Cliente`, `Handover`

---

#### `public.historico_cards`
Histórico de mudanças em revendas (auditoria de negócio).

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `revenda_id` | uuid FK | Referência para `revendas(id)` |
| `tipo` | text | Tipo do evento (status_change, nota, etc.) |
| `descricao` | text | Descrição do evento |
| `manual` | boolean | `true` se inserido manualmente pelo usuário |
| `usuario_id` | uuid FK | Quem registrou |
| `usuario_nome` | text | Nome desnormalizado |
| `criado_em` | timestamptz | |

---

#### `public.tarefas`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `titulo` | text | |
| `descricao` | text | |
| `revenda_id` | uuid FK | Revenda associada (opcional) |
| `revenda_nome` | text | Nome desnormalizado |
| `responsavel_id` | uuid FK | Perfil responsável |
| `responsavel` | text | Nome desnormalizado |
| `prioridade` | text | `Alta` / `Média` / `Baixa` |
| `tipo` | text | Categoria da tarefa |
| `status` | text | `Pendente` / `Em andamento` / `Concluída` |
| `vencimento` | date | Data limite |
| `criado_em` | timestamptz | |
| `atualizado_em` | timestamptz | Atualizado via trigger |
| `criado_por` | uuid FK | |

---

#### `public.atividades`
Timeline imutável de eventos do sistema.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `tipo` | text | Tipo do evento |
| `revenda_id` | uuid FK | |
| `revenda_nome` | text | Desnormalizado |
| `descricao` | text | Descrição do evento |
| `usuario_id` | uuid FK | |
| `usuario_nome` | text | Desnormalizado |
| `criado_em` | timestamptz | |

---

#### `public.treinamentos`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `nome` | text | Nome da trilha |
| `modulos` | integer | Quantidade de módulos |
| `duracao` | text | Duração estimada |
| `descricao` | text | |
| `criado_em` | timestamptz | |
| `criado_por` | uuid FK | |

---

#### `public.handovers`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `revenda_id` | uuid FK | |
| `revenda_nome` | text | Desnormalizado |
| `cs_id` | uuid FK | CS responsável |
| `cs_nome` | text | Desnormalizado |
| `inicio` | date | Data de início |
| `prazo` | date | Data prevista |
| `progresso` | integer | % concluído (0–100) |
| `status` | text | Status do handover |
| `obs` | text | |
| `checklist` | jsonb | Etapas: contrato, docs, credenciais, treinamento, NPS |
| `criado_em` | timestamptz | |

---

#### `public.auditoria`
Log imutável para conformidade LGPD. **Nenhum usuário pode excluir registros.**

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `usuario_id` | uuid | |
| `usuario_nome` | text | |
| `usuario_email` | text | |
| `acao` | text | `CREATE`, `UPDATE`, `DELETE`, `LOGIN`, `LOGOUT`, `EXPORT`, `VIEW_CNPJ` |
| `tabela` | text | Tabela afetada |
| `registro_id` | uuid | ID do registro afetado |
| `detalhe` | jsonb | Dados antes/depois da mudança |
| `ip` | text | IP do cliente |
| `user_agent` | text | |
| `criado_em` | timestamptz | |

---

#### `public.importacoes`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `arquivo` | text | Nome do arquivo importado |
| `total` | integer | Total de linhas |
| `importados` | integer | Linhas importadas com sucesso |
| `erros` | integer | Linhas com erro |
| `detalhes` | jsonb | Log detalhado por linha |
| `usuario_id` | uuid FK | Quem importou |
| `criado_em` | timestamptz | |

---

### 3.2 Tabelas da integração Orion (`rls_e_tabelas_orion.sql`)

#### `public.orion_leads_vendidos`
Leads recebidos via webhook do Orion CRM.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `nome` | text | Nome da empresa/lead |
| `email` | text | |
| `telefone` | text | |
| `cidade` | text | |
| `uf` | text | |
| `cs` | text | CS na Orion |
| `obs` | text | |
| `id_origem` | text UNIQUE | ID do card na Orion |
| `status` | text | Status atual |
| `ingresso` | date | Data de entrada |
| `_orion_raw` | jsonb | Payload original (rastreabilidade) |
| `processado` | boolean | `true` se já criou revenda |
| `criado_em` | timestamptz | |

---

#### `public.orion_metas`
Metas mensais recebidas via webhook.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `nome` | text | Nome da meta |
| `tipo` | text | Categoria |
| `valor_meta` | numeric | Meta estabelecida |
| `valor_atual` | numeric | Valor atingido |
| `percentual` | numeric | % calculado |
| `mes` | integer | Mês (1–12) |
| `ano` | integer | Ano |
| `status` | text | `critica` (<70%) / `atencao` (70–99%) / `atingida` (≥100%) |
| `_orion_raw` | jsonb | Payload original |
| `criado_em` | timestamptz | |
| `atualizado_em` | timestamptz | |

Constraint UNIQUE: `(nome, mes, ano)` — garante upsert correto.

---

#### `public.orion_eventos_raw`
Eventos não reconhecidos pela Edge Function (debug/troubleshooting).

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | uuid PK | |
| `evento` | text | Tipo do evento recebido |
| `payload` | jsonb | Payload completo |
| `criado_em` | timestamptz | |

---

### 3.3 Views

#### `revendas_seguras`
Máscara o CNPJ para usuários sem a permissão `pode_ver_cnpj`:

```sql
-- Usuários com pode_ver_cnpj = true → veem o CNPJ real
-- Demais → veem '**.***.***/****.** '
```

---

### 3.4 Triggers e Funções do Banco

| Objeto | Tipo | Descrição |
|--------|------|-----------|
| `set_updated_at()` | Trigger function | Atualiza `atualizado_em` em UPDATE |
| `handle_new_user()` | Trigger function | Cria perfil automático ao registrar; primeiro usuário = Administrador |
| `on_auth_user_created` | Trigger | Chama `handle_new_user()` após INSERT em `auth.users` |
| `meu_perfil()` | SQL function | Retorna perfil do usuário logado (`auth.uid()`) |
| `estou_ativo()` | SQL function | Verifica se o usuário logado está ativo |
| `meta_mes_atual()` | SQL function | Retorna metas do mês corrente para o dashboard |

---

### 3.5 Índices de Performance

```sql
idx_revendas_status       -- revendas(status)
idx_revendas_cs           -- revendas(cs_id)
idx_historico_revenda     -- historico_cards(revenda_id)
idx_atividades_revenda    -- atividades(revenda_id)
idx_auditoria_usuario     -- auditoria(usuario_id)
idx_auditoria_data        -- auditoria(criado_em)
idx_orion_metas_mes       -- orion_metas(mes, ano)
idx_orion_leads_origem    -- orion_leads_vendidos(id_origem)
```

---

## 4. Relacionamentos

```
auth.users (Supabase)
    │
    └─── perfis (1:1, cascade delete)
              │
              ├─── revendas.cs_id (N:1) — CS responsável
              ├─── tarefas.responsavel_id (N:1)
              ├─── tarefas.criado_por (N:1)
              ├─── historico_cards.usuario_id (N:1)
              ├─── atividades.usuario_id (N:1)
              ├─── handovers.cs_id (N:1)
              └─── importacoes.usuario_id (N:1)

revendas
    │
    ├─── historico_cards.revenda_id (1:N)
    ├─── tarefas.revenda_id (1:N, opcional)
    ├─── atividades.revenda_id (1:N)
    └─── handovers.revenda_id (1:N)

orion_leads_vendidos.id_origem ──── revendas.id_origem (correlação por texto)
```

**Campos desnormalizados** (para evitar JOINs frequentes):
- `revenda_nome` em tarefas, atividades, historico_cards, handovers, orion_leads_vendidos
- `usuario_nome` em historico_cards, atividades, auditoria
- `cs_nome` em handovers
- `responsavel` em tarefas

---

## 5. Edge Functions

### 5.1 `webhook-orion`

**Localização:** `supabase/functions/webhook-orion/index.ts`  
**Runtime:** Deno + TypeScript  
**URL de produção:** `https://vykhskaayukmodnglujc.supabase.co/functions/v1/webhook-orion`

#### Endpoints

| Método | Parâmetros | Descrição |
|--------|-----------|-----------|
| `GET` | `?tipo=metas&mes=N&ano=N` | Retorna metas do mês para o dashboard |
| `GET` | `?tipo=leads_vendidos` | Retorna os últimos 50 leads recebidos |
| `POST` | Body JSON (evento Orion) | Processa evento recebido do Orion CRM |
| `OPTIONS` | — | CORS preflight |

#### Autenticação do Webhook (POST)

A Edge Function suporta múltiplos formatos para flexibilidade:

```
1. Header x-orion-signature: <token>
2. Header x-webhook-secret: <token>
3. Header authorization: Bearer <token>
4. Query param: ?token=<token>
5. Query param: ?secret=<token>
6. Query param: ?key=<token>
7. HMAC-SHA256: x-orion-signature com verificação de assinatura
```

O segredo é configurado em `ORION_WEBHOOK_SECRET` (Supabase Project Settings → Edge Functions → Secrets).

#### Fluxo de Processamento (POST)

```
Recebe POST com evento Orion
          ↓
Valida assinatura/token
  - Falha → log em auditoria + HTTP 401
          ↓
Detecta tipo de evento pelo campo "evento":
  ┌─────────────────────────────────────────────────────┐
  │  "vend*" ou "lead*"          → Processamento de Lead │
  │  "meta*" ou "goal*"          → Processamento de Meta │
  │  Desconhecido                → orion_eventos_raw     │
  └─────────────────────────────────────────────────────┘
          ↓
LEAD:
  Normaliza campos (suporta nomes alternativos: empresa/company/nome, telefone/phone/tel, etc.)
  INSERT em orion_leads_vendidos (ignorar se id_origem já existe)
  Se não existe revenda com id_origem → INSERT em revendas (status = 'Nova Revenda')
  INSERT em historico_cards
  INSERT em auditoria (acao: 'CREATE')
          ↓
META:
  Normaliza campos
  Calcula percentual = (valor_atual / valor_meta) * 100
  Define status: <70% = critica, 70-99% = atencao, ≥100% = atingida
  UPSERT em orion_metas ON CONFLICT (nome, mes, ano)
  INSERT em auditoria (acao: 'UPDATE')
          ↓
HTTP 200 com resumo do processamento
```

#### Deploy da Edge Function

```bash
# Instalar Supabase CLI
npm install -g supabase

# Autenticar
supabase login

# Linkar ao projeto
supabase link --project-ref vykhskaayukmodnglujc

# Deploy da função
supabase functions deploy webhook-orion

# Configurar segredo
supabase secrets set ORION_WEBHOOK_SECRET=seu_token_secreto_aqui
```

---

## 6. Como Executar Localmente

### 6.1 Pré-requisitos

- Conta no [Supabase](https://supabase.com) com o projeto já configurado
- Navegador moderno (Chrome, Firefox, Edge)
- (Opcional) [Live Server](https://marketplace.visualstudio.com/items?itemName=ritwickdey.LiveServer) para VS Code

### 6.2 Setup do Banco de Dados

Execute os scripts SQL na ordem correta no SQL Editor do Supabase (`supabase.com → projeto → SQL Editor`):

```
Passo 1: Execute supabase_setup.sql
  → Cria extensões, tabelas base, triggers, views, RLS

Passo 2: Execute rls_e_tabelas_orion.sql
  → Cria tabelas Orion, revisão de RLS, índices de performance
```

> **Atenção:** O script é idempotente (`CREATE TABLE IF NOT EXISTS`, `CREATE POLICY IF NOT EXISTS`), mas recomenda-se executar em banco vazio na primeira vez.

### 6.3 Abrir a Aplicação

Como não há servidor Node.js nem build step, basta abrir os arquivos diretamente:

**Opção A — Abrir direto no navegador:**
```
Navegue até: c:\pos-venda-comercial\index.html
Abra com duplo clique ou arraste para o navegador
```

**Opção B — Usar Live Server (recomendado para desenvolvimento):**
```
1. Abra a pasta no VS Code
2. Clique com botão direito em index.html
3. Selecione "Open with Live Server"
4. Acesse: http://localhost:5500/index.html
```

**Opção C — Qualquer servidor HTTP estático:**
```bash
# Python
python -m http.server 8080

# Node.js (se instalado)
npx serve .

# Acesse: http://localhost:8080/index.html
```

### 6.4 Primeiro Acesso

1. Acesse `index.html`
2. Clique em **Criar conta**
3. Informe nome, e-mail e senha
4. Confirme o e-mail recebido
5. O primeiro usuário registrado recebe automaticamente o perfil **Administrador**
6. Faça login — será redirecionado para `app.html`

### 6.5 Configurar Integração Orion (Opcional)

1. No painel Supabase, vá em **Project Settings → Edge Functions → Secrets**
2. Adicione: `ORION_WEBHOOK_SECRET = <token_combinado_com_a_orion>`
3. Deploy da função (ver seção 5.1)
4. Configure na Orion CRM o webhook apontando para:
   ```
   https://vykhskaayukmodnglujc.supabase.co/functions/v1/webhook-orion
   ```

### 6.6 Executar Edge Functions Localmente (Desenvolvimento)

```bash
# Instalar Deno (runtime da Edge Function)
# https://deno.land/manual/getting_started/installation

# Instalar Supabase CLI
npm install -g supabase

# Iniciar servidor local de Edge Functions
supabase functions serve webhook-orion --env-file .env.local

# A função ficará disponível em:
# http://localhost:54321/functions/v1/webhook-orion
```

Crie `.env.local` com:
```env
SUPABASE_URL=https://vykhskaayukmodnglujc.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<sua_service_role_key>
ORION_WEBHOOK_SECRET=<seu_token_secreto>
```

---

## 7. Melhorias Recomendadas

### 7.1 Alta Prioridade

#### Separar as credenciais do código-fonte
As chaves do Supabase (`SUPABASE_URL` e `SUPABASE_ANON_KEY`) estão hardcoded em `index.html` e `app.html`. Embora a Anon Key seja pública por design, é boa prática centralizá-las:

```javascript
// Antes (hardcoded em dois arquivos)
const SUPABASE_URL = 'https://vykhskaayukmodnglujc.supabase.co'

// Depois (um único ponto de configuração)
// config.js carregado por ambos os HTMLs
const SUPABASE_URL = window.ENV?.SUPABASE_URL || 'https://...'
```

#### Extrair o JavaScript inline para arquivos `.js`
`app.html` com ~280 KB é difícil de manter e impossível de testar unitariamente. Separar em módulos permitiria melhor organização:

```
src/
  auth.js         — autenticação
  revendas.js     — CRUD revendas
  pipeline.js     — kanban
  dashboard.js    — gráficos e KPIs
  utils.js        — helpers compartilhados
```

#### Adicionar `.env.example` e `.gitignore`
Para evitar vazamento acidental de credenciais no futuro:

```
# .gitignore
.env
.env.local
*.env
```

---

### 7.2 Média Prioridade

#### Migrar para um framework de componentes
Com o crescimento do sistema, Vanilla JS em arquivo único se torna difícil de manter. Opções adequadas ao contexto:

| Opção | Vantagem | Esforço |
|-------|----------|---------|
| **Vite + Vanilla JS** | Mínima mudança, resolve imports e bundling | Baixo |
| **React + Vite** | Componentização, ecossistema amplo | Médio |
| **Svelte** | Bundle pequeno, sintaxe próxima ao HTML atual | Médio |

#### Adicionar sistema de roteamento
Atualmente a navegação é feita via show/hide de `<div>`. Um router simples como `navigo` ou o hash-router nativo (`window.location.hash`) melhoraria o comportamento do botão Voltar e permitiria links diretos para seções.

#### Implementar cache local para dados frequentes
KPIs e listas do dashboard são refetchados a cada visita. Um cache com TTL curto (ex: 60s) no `sessionStorage` reduziria chamadas ao Supabase e aceleraria a navegação.

---

### 7.3 Longo Prazo

#### Adicionar testes
O projeto não possui nenhum tipo de teste. Recomendação por ordem de impacto:

1. **Testes de integração para a Edge Function** — Deno tem suporte nativo a testes (`Deno.test`)
2. **Testes de RLS** — `pgTAP` ou queries SQL manuais validando que as políticas bloqueiam o acesso correto
3. **Testes E2E** — Playwright para os fluxos críticos (login, criar revenda, mover no pipeline)

#### Implementar real-time com Supabase Realtime
O sistema atualmente exige refresh manual para ver mudanças de outros usuários. O Supabase oferece subscriptions via WebSocket:

```javascript
supabase
  .channel('revendas')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'revendas' }, 
    payload => atualizarUI(payload))
  .subscribe()
```

Isso seria especialmente valioso no Pipeline Kanban, onde múltiplos CS trabalham simultaneamente.

#### Webhooks de saída (notificações)
Atualmente o sistema recebe dados da Orion, mas não envia notificações de volta. Considerar:
- Notificação quando revenda atinge status "Handover" (e-mail/Slack para equipe comercial)
- Alerta de tarefas vencidas (cron via Supabase pg_cron)
- Notificação de NPS pós-handover

#### Dashboard TV em tela separada
Existe uma visão de TV no sistema. Considerar transformá-la em uma URL pública (com token read-only) que pode ser exibida em monitores sem autenticação completa.

---

## Referências Rápidas

| Recurso | Localização |
|---------|-------------|
| SQL do banco (setup base) | `supabase_setup.sql` |
| SQL da integração Orion | `rls_e_tabelas_orion.sql` |
| Edge Function webhook | `supabase/functions/webhook-orion/index.ts` |
| Tela de login | `index.html` |
| Aplicação principal | `app.html` |
| Painel Supabase | https://supabase.com/dashboard/project/vykhskaayukmodnglujc |
| SQL Editor Supabase | https://supabase.com/dashboard/project/vykhskaayukmodnglujc/editor |

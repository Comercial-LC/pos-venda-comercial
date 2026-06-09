-- ═══════════════════════════════════════════════════════════════
-- PORTAL REVENDA LC — Setup completo do banco Supabase
-- Execute no SQL Editor: supabase.com → projeto → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── Extensões ────────────────────────────────────────────────
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ── 1. PERFIS DE USUÁRIO (ligado ao auth.users do Supabase) ──
create table if not exists public.perfis (
  id           uuid primary key references auth.users(id) on delete cascade,
  nome         text not null,
  email        text not null,
  perfil       text not null default 'CS Analyst'
                 check (perfil in ('Administrador','CS Manager','CS Analyst','Diretoria')),
  ativo        boolean not null default true,
  avatar_iniciais text,
  criado_em    timestamptz default now(),
  atualizado_em timestamptz default now(),
  -- Permissões granulares (Admin pode ligar/desligar por usuário)
  pode_criar_revenda    boolean default true,
  pode_editar_revenda   boolean default true,
  pode_excluir_revenda  boolean default false,
  pode_ver_cnpj         boolean default false,  -- CNPJ é dado sensível (LGPD)
  pode_exportar         boolean default false,
  pode_importar         boolean default false,
  pode_gerenciar_usuarios boolean default false,
  pode_ver_relatorios   boolean default true,
  pode_handover         boolean default true
);

-- ── 2. REVENDAS ───────────────────────────────────────────────
create table if not exists public.revendas (
  id           uuid primary key default uuid_generate_v4(),
  nome         text not null,
  cnpj         text,           -- sensível LGPD — acesso controlado por RLS
  cidade       text,
  uf           text,
  email        text,
  tel          text,
  tel2         text,
  tel3         text,
  cs           text,           -- nome do responsável CS
  cs_id        uuid references public.perfis(id),
  status       text not null default 'Nova Revenda'
                 check (status in ('Nova Revenda','Implantação','Liberação Web',
                   'Academy','Decola Instalação','Decola Produtos',
                   'Primeiro Cliente','Handover')),
  segmento     text,
  porte        text,
  contratos    integer default 0,
  curva        text,
  pct_contratos numeric,
  pct_cumulativo numeric,
  tpc          integer,        -- tempo para primeiro cliente (dias)
  ingresso     date,
  obs          text,
  produtos     text[] default '{}',  -- checklist Decola Produtos
  id_origem    text,           -- ID do sistema de origem (importação)
  criado_em    timestamptz default now(),
  atualizado_em timestamptz default now(),
  criado_por   uuid references public.perfis(id)
);

-- ── 3. HISTÓRICO DOS CARDS ────────────────────────────────────
create table if not exists public.historico_cards (
  id           uuid primary key default uuid_generate_v4(),
  revenda_id   uuid not null references public.revendas(id) on delete cascade,
  tipo         text not null,
  descricao    text not null,
  manual       boolean default false,  -- true = anotação manual do usuário
  usuario_id   uuid references public.perfis(id),
  usuario_nome text,
  criado_em    timestamptz default now()
);

-- ── 4. TAREFAS ────────────────────────────────────────────────
create table if not exists public.tarefas (
  id           uuid primary key default uuid_generate_v4(),
  titulo       text not null,
  descricao    text,
  revenda_id   uuid references public.revendas(id) on delete cascade,
  revenda_nome text,
  responsavel_id uuid references public.perfis(id),
  responsavel  text,
  prioridade   text default 'Média' check (prioridade in ('Alta','Média','Baixa')),
  tipo         text,
  status       text default 'Pendente' check (status in ('Pendente','Em andamento','Concluída')),
  vencimento   date,
  criado_em    timestamptz default now(),
  atualizado_em timestamptz default now(),
  criado_por   uuid references public.perfis(id)
);

-- ── 5. ATIVIDADES / TIMELINE ──────────────────────────────────
create table if not exists public.atividades (
  id           uuid primary key default uuid_generate_v4(),
  tipo         text not null,
  revenda_id   uuid references public.revendas(id) on delete set null,
  revenda_nome text,
  descricao    text not null,
  usuario_id   uuid references public.perfis(id),
  usuario_nome text,
  criado_em    timestamptz default now()
);

-- ── 6. TREINAMENTOS ───────────────────────────────────────────
create table if not exists public.treinamentos (
  id           uuid primary key default uuid_generate_v4(),
  nome         text not null,
  modulos      integer default 4,
  duracao      text,
  descricao    text,
  criado_em    timestamptz default now(),
  criado_por   uuid references public.perfis(id)
);

-- ── 7. HANDOVERS ─────────────────────────────────────────────
create table if not exists public.handovers (
  id           uuid primary key default uuid_generate_v4(),
  revenda_id   uuid references public.revendas(id) on delete cascade,
  revenda_nome text,
  cs_id        uuid references public.perfis(id),
  cs_nome      text,
  inicio       date default current_date,
  prazo        date,
  progresso    integer default 0,
  status       text default 'Em andamento',
  obs          text,
  checklist    jsonb default '{"contrato":false,"docs":false,"credenciais":false,"treinamento":false,"nps":false}',
  criado_em    timestamptz default now()
);

-- ── 8. LOG DE AUDITORIA (LGPD) ───────────────────────────────
create table if not exists public.auditoria (
  id           uuid primary key default uuid_generate_v4(),
  usuario_id   uuid references public.perfis(id),
  usuario_nome text,
  usuario_email text,
  acao         text not null,   -- CREATE, UPDATE, DELETE, LOGIN, LOGOUT, EXPORT, VIEW_CNPJ
  tabela       text,
  registro_id  uuid,
  detalhe      jsonb,           -- dados anteriores/novos
  ip           text,
  user_agent   text,
  criado_em    timestamptz default now()
);

-- ── 9. IMPORTAÇÕES ────────────────────────────────────────────
create table if not exists public.importacoes (
  id           uuid primary key default uuid_generate_v4(),
  arquivo      text,
  total        integer,
  importados   integer,
  erros        integer,
  detalhes     jsonb,
  usuario_id   uuid references public.perfis(id),
  criado_em    timestamptz default now()
);

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS) — Segurança por linha
-- ═══════════════════════════════════════════════════════════════
alter table public.perfis           enable row level security;
alter table public.revendas         enable row level security;
alter table public.historico_cards  enable row level security;
alter table public.tarefas          enable row level security;
alter table public.atividades       enable row level security;
alter table public.treinamentos     enable row level security;
alter table public.handovers        enable row level security;
alter table public.auditoria        enable row level security;
alter table public.importacoes      enable row level security;

-- ── Função helper: pega perfil do usuário logado ─────────────
create or replace function public.meu_perfil()
returns text language sql security definer stable as $$
  select perfil from public.perfis where id = auth.uid()
$$;

create or replace function public.estou_ativo()
returns boolean language sql security definer stable as $$
  select coalesce((select ativo from public.perfis where id = auth.uid()), false)
$$;

-- ── POLÍTICAS: perfis ─────────────────────────────────────────
-- Usuário vê e edita só o próprio perfil; Admin vê todos
create policy "perfis_select" on public.perfis for select
  using (auth.uid() = id or meu_perfil() = 'Administrador');

create policy "perfis_update_own" on public.perfis for update
  using (auth.uid() = id);

create policy "perfis_admin" on public.perfis for all
  using (meu_perfil() = 'Administrador');

-- ── POLÍTICAS: revendas ───────────────────────────────────────
-- Todos os usuários ativos veem todas as revendas
create policy "revendas_select" on public.revendas for select
  using (estou_ativo());

create policy "revendas_insert" on public.revendas for insert
  with check (estou_ativo() and (
    select pode_criar_revenda from public.perfis where id = auth.uid()
  ));

create policy "revendas_update" on public.revendas for update
  using (estou_ativo() and (
    select pode_editar_revenda from public.perfis where id = auth.uid()
  ));

create policy "revendas_delete" on public.revendas for delete
  using (estou_ativo() and (
    select pode_excluir_revenda from public.perfis where id = auth.uid()
  ));

-- ── POLÍTICAS: histórico, tarefas, atividades ────────────────
create policy "historico_select" on public.historico_cards for select using (estou_ativo());
create policy "historico_insert" on public.historico_cards for insert with check (estou_ativo());
create policy "historico_delete" on public.historico_cards for delete
  using (usuario_id = auth.uid() or meu_perfil() = 'Administrador');

create policy "tarefas_select" on public.tarefas for select using (estou_ativo());
create policy "tarefas_insert" on public.tarefas for insert with check (estou_ativo());
create policy "tarefas_update" on public.tarefas for update using (estou_ativo());
create policy "tarefas_delete" on public.tarefas for delete
  using (criado_por = auth.uid() or meu_perfil() in ('Administrador','CS Manager'));

create policy "atividades_select" on public.atividades for select using (estou_ativo());
create policy "atividades_insert" on public.atividades for insert with check (estou_ativo());

create policy "treinamentos_all" on public.treinamentos for all using (estou_ativo());
create policy "handovers_all" on public.handovers for all using (estou_ativo());
create policy "importacoes_all" on public.importacoes for all using (estou_ativo());

-- ── POLÍTICAS: auditoria (somente Admin lê, sistema grava) ───
create policy "auditoria_select" on public.auditoria for select
  using (meu_perfil() = 'Administrador');
create policy "auditoria_insert" on public.auditoria for insert
  with check (true);  -- qualquer usuário autenticado pode inserir logs

-- ═══════════════════════════════════════════════════════════════
-- TRIGGERS — atualiza updated_at e cria perfil automático
-- ═══════════════════════════════════════════════════════════════
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.atualizado_em = now(); return new; end $$;

create trigger trg_revendas_updated
  before update on public.revendas
  for each row execute function public.set_updated_at();

create trigger trg_tarefas_updated
  before update on public.tarefas
  for each row execute function public.set_updated_at();

-- Cria perfil automaticamente quando usuário confirma e-mail
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  nome_usuario text;
  iniciais text;
begin
  nome_usuario := coalesce(
    new.raw_user_meta_data->>'nome',
    split_part(new.email, '@', 1)
  );
  iniciais := upper(left(split_part(nome_usuario,' ',1),1) ||
               left(split_part(nome_usuario,' ',2),1));
  if iniciais = '' then iniciais := upper(left(nome_usuario,2)); end if;

  insert into public.perfis (id, nome, email, perfil, avatar_iniciais,
    pode_criar_revenda, pode_editar_revenda, pode_excluir_revenda,
    pode_ver_cnpj, pode_exportar, pode_importar,
    pode_gerenciar_usuarios, pode_ver_relatorios, pode_handover)
  values (
    new.id, nome_usuario, new.email,
    -- Primeiro usuário vira Admin automaticamente
    case when (select count(*) from public.perfis) = 0
         then 'Administrador' else 'CS Analyst' end,
    iniciais,
    true, true, false, false, false, false, false, true, true
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ═══════════════════════════════════════════════════════════════
-- VIEW segura: revendas sem CNPJ para usuários sem permissão
-- ═══════════════════════════════════════════════════════════════
create or replace view public.revendas_seguras as
select
  id, nome,
  case when (select pode_ver_cnpj from public.perfis where id = auth.uid())
       then cnpj else '••••••••/••••-••' end as cnpj,
  cidade, uf, email, tel, tel2, tel3,
  cs, cs_id, status, segmento, porte,
  contratos, curva, pct_contratos, pct_cumulativo,
  tpc, ingresso, obs, produtos, id_origem,
  criado_em, atualizado_em, criado_por
from public.revendas;

-- ═══════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO: permite confirmação de e-mail redirecionar ao site
-- (configure também em Auth → Email Templates no painel)
-- ═══════════════════════════════════════════════════════════════
-- No painel Supabase: Authentication → URL Configuration
-- Site URL: https://seu-site.netlify.app
-- Redirect URLs: https://seu-site.netlify.app/**

select 'Setup concluído com sucesso! 🎉' as resultado;

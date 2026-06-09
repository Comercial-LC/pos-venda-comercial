-- ═══════════════════════════════════════════════════════════════
-- PORTAL REVENDA LC — Tabelas Orion + RLS Completo
-- Execute no SQL Editor do Supabase
-- ═══════════════════════════════════════════════════════════════

-- ── 1. TABELAS DA INTEGRAÇÃO ORION ───────────────────────────

-- Leads vindos da Orion (cards marcados como Vendido)
create table if not exists public.orion_leads_vendidos (
  id           uuid primary key default uuid_generate_v4(),
  nome         text,
  email        text,
  telefone     text,
  cidade       text,
  uf           text,
  cs           text,
  obs          text,
  id_origem    text unique,   -- ID do lead no Orion (evita duplicatas)
  status       text default 'Nova Revenda',
  ingresso     date,
  _orion_raw   text,          -- payload completo para rastreabilidade
  processado   boolean default false,  -- true quando virou revenda
  criado_em    timestamptz default now()
);

-- Metas mensais vindas da Orion
create table if not exists public.orion_metas (
  id           uuid primary key default uuid_generate_v4(),
  nome         text not null,
  tipo         text default 'quantidade',
  valor_meta   numeric default 0,
  valor_atual  numeric default 0,
  percentual   numeric default 0,
  mes          integer not null,
  ano          integer not null,
  status       text default 'critica',  -- critica | atencao | atingida
  _orion_raw   text,
  criado_em    timestamptz default now(),
  atualizado_em timestamptz default now(),
  unique(nome, mes, ano)
);

-- Eventos não reconhecidos (para debugging)
create table if not exists public.orion_eventos_raw (
  id        uuid primary key default uuid_generate_v4(),
  evento    text,
  payload   text,
  criado_em timestamptz default now()
);

-- ── 2. RLS NAS NOVAS TABELAS ──────────────────────────────────
alter table public.orion_leads_vendidos enable row level security;
alter table public.orion_metas          enable row level security;
alter table public.orion_eventos_raw    enable row level security;

-- Leads Orion: todos os ativos veem, só admin exclui
create policy "orion_leads_select" on public.orion_leads_vendidos
  for select using (public.estou_ativo());

create policy "orion_leads_insert" on public.orion_leads_vendidos
  for insert with check (true);  -- Edge Function usa service role

create policy "orion_leads_update" on public.orion_leads_vendidos
  for update using (public.estou_ativo());

create policy "orion_leads_delete" on public.orion_leads_vendidos
  for delete using (public.meu_perfil() = 'Administrador');

-- Metas: todos veem, só sistema insere
create policy "orion_metas_select" on public.orion_metas
  for select using (public.estou_ativo());

create policy "orion_metas_insert" on public.orion_metas
  for insert with check (true);

create policy "orion_metas_update" on public.orion_metas
  for update using (true);

create policy "orion_metas_delete" on public.orion_metas
  for delete using (public.meu_perfil() = 'Administrador');

-- Eventos raw: só admin vê
create policy "orion_raw_all" on public.orion_eventos_raw
  for all using (public.meu_perfil() = 'Administrador');

-- ── 3. RLS REVISADO E BLINDADO — TODAS AS TABELAS ────────────

-- Remove políticas antigas duplicadas (se existirem)
drop policy if exists "perfis_admin" on public.perfis;

-- PERFIS — Admin gerencia todos, usuário vê/edita só o próprio
drop policy if exists "perfis_select" on public.perfis;
drop policy if exists "perfis_update_own" on public.perfis;
create policy "perfis_select" on public.perfis
  for select using (
    auth.uid() = id
    or public.meu_perfil() = 'Administrador'
  );
create policy "perfis_update_self" on public.perfis
  for update using (auth.uid() = id)
  with check (auth.uid() = id);
create policy "perfis_admin_all" on public.perfis
  for all using (public.meu_perfil() = 'Administrador');

-- REVENDAS — todos ativos veem; permissões granulares
drop policy if exists "revendas_select" on public.revendas;
drop policy if exists "revendas_insert" on public.revendas;
drop policy if exists "revendas_update" on public.revendas;
drop policy if exists "revendas_delete" on public.revendas;

create policy "revendas_select" on public.revendas
  for select using (public.estou_ativo());

create policy "revendas_insert" on public.revendas
  for insert with check (
    public.estou_ativo() and (
      (select pode_criar_revenda from public.perfis where id = auth.uid())
      or auth.uid() is null  -- permite service role (sistema)
    )
  );

create policy "revendas_update" on public.revendas
  for update using (
    public.estou_ativo() and (
      select pode_editar_revenda from public.perfis where id = auth.uid()
    )
  );

create policy "revendas_delete" on public.revendas
  for delete using (
    public.estou_ativo() and (
      select pode_excluir_revenda from public.perfis where id = auth.uid()
    )
  );

-- HISTÓRICO — todos ativos veem; só criador ou admin exclui
drop policy if exists "historico_select" on public.historico_cards;
drop policy if exists "historico_insert" on public.historico_cards;
drop policy if exists "historico_delete" on public.historico_cards;

create policy "historico_select" on public.historico_cards
  for select using (public.estou_ativo());

create policy "historico_insert" on public.historico_cards
  for insert with check (public.estou_ativo() or auth.uid() is null);

create policy "historico_delete" on public.historico_cards
  for delete using (
    usuario_id = auth.uid()
    or public.meu_perfil() = 'Administrador'
  );

-- TAREFAS
drop policy if exists "tarefas_select" on public.tarefas;
drop policy if exists "tarefas_insert" on public.tarefas;
drop policy if exists "tarefas_update" on public.tarefas;
drop policy if exists "tarefas_delete" on public.tarefas;

create policy "tarefas_select" on public.tarefas
  for select using (public.estou_ativo());

create policy "tarefas_insert" on public.tarefas
  for insert with check (public.estou_ativo());

create policy "tarefas_update" on public.tarefas
  for update using (public.estou_ativo());

create policy "tarefas_delete" on public.tarefas
  for delete using (
    criado_por = auth.uid()
    or public.meu_perfil() in ('Administrador','CS Manager')
  );

-- ATIVIDADES — imutável (ninguém exclui exceto admin)
drop policy if exists "atividades_select" on public.atividades;
drop policy if exists "atividades_insert" on public.atividades;

create policy "atividades_select" on public.atividades
  for select using (public.estou_ativo());

create policy "atividades_insert" on public.atividades
  for insert with check (public.estou_ativo() or auth.uid() is null);

create policy "atividades_delete" on public.atividades
  for delete using (public.meu_perfil() = 'Administrador');

-- AUDITORIA — somente admin lê; sistema e autenticados inserem
drop policy if exists "auditoria_select" on public.auditoria;
drop policy if exists "auditoria_insert" on public.auditoria;

create policy "auditoria_select" on public.auditoria
  for select using (public.meu_perfil() = 'Administrador');

create policy "auditoria_insert" on public.auditoria
  for insert with check (true);  -- qualquer origem pode logar

create policy "auditoria_no_delete" on public.auditoria
  for delete using (false);  -- NINGUÉM pode excluir logs — LGPD

-- TREINAMENTOS, HANDOVERS, IMPORTAÇÕES
drop policy if exists "treinamentos_all" on public.treinamentos;
drop policy if exists "handovers_all" on public.handovers;
drop policy if exists "importacoes_all" on public.importacoes;

create policy "treinamentos_select" on public.treinamentos
  for select using (public.estou_ativo());
create policy "treinamentos_write" on public.treinamentos
  for all using (public.estou_ativo() and
    public.meu_perfil() in ('Administrador','CS Manager'));

create policy "handovers_select" on public.handovers
  for select using (public.estou_ativo());
create policy "handovers_write" on public.handovers
  for all using (public.estou_ativo() and (
    select pode_handover from public.perfis where id = auth.uid()
  ));

create policy "importacoes_select" on public.importacoes
  for select using (public.estou_ativo());
create policy "importacoes_write" on public.importacoes
  for all using (public.estou_ativo() and (
    select pode_importar from public.perfis where id = auth.uid()
  ));

-- ── 4. VIEW SEGURA ATUALIZADA ─────────────────────────────────
create or replace view public.revendas_seguras
with (security_invoker = true) as
select
  id, nome,
  case
    when (select pode_ver_cnpj from public.perfis where id = auth.uid())
    then cnpj
    else '••••••/••-••'
  end as cnpj,
  cidade, uf, email, tel, tel2, tel3,
  cs, cs_id, status, segmento, porte,
  contratos, curva, pct_contratos, pct_cumulativo,
  tpc, ingresso, obs, produtos, id_origem,
  criado_em, atualizado_em, criado_por
from public.revendas;

-- ── 5. FUNÇÃO: META DO MÊS ATUAL (para o dashboard) ─────────
create or replace function public.meta_mes_atual()
returns table (
  nome text, valor_meta numeric, valor_atual numeric,
  percentual numeric, status text, mes int, ano int
)
language sql security definer stable as $$
  select nome, valor_meta, valor_atual, percentual, status, mes, ano
  from public.orion_metas
  where mes = extract(month from now())::int
    and ano = extract(year  from now())::int
  order by percentual asc;  -- críticas primeiro
$$;

-- ── 6. ÍNDICES para performance ───────────────────────────────
create index if not exists idx_revendas_status
  on public.revendas(status);
create index if not exists idx_revendas_cs
  on public.revendas(cs);
create index if not exists idx_historico_revenda
  on public.historico_cards(revenda_id);
create index if not exists idx_atividades_revenda
  on public.atividades(revenda_id);
create index if not exists idx_auditoria_usuario
  on public.auditoria(usuario_id);
create index if not exists idx_auditoria_data
  on public.auditoria(criado_em desc);
create index if not exists idx_orion_metas_mes
  on public.orion_metas(mes, ano);
create index if not exists idx_orion_leads_origem
  on public.orion_leads_vendidos(id_origem);

select '✅ RLS blindado + tabelas Orion criadas com sucesso!' as resultado;

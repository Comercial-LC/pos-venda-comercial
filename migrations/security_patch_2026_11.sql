-- ══════════════════════════════════════════════════════════════════════
-- SECURITY PATCH — Novembro/2026
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah (pode rodar
-- mais de uma vez — é idempotente). Roda numa transação só: se algo
-- falhar, nada é aplicado.
--
-- Corrige:
--  1. [CRÍTICO] Auto-ativação: qualquer pessoa se cadastrava pelo site
--     público e fazia PATCH perfis {ativo:true} no próprio perfil — o
--     trigger só protegia `perfil` e `pode_*`. Virava usuário ativo com
--     acesso a todas as revendas.
--  2. [ALTO] Tabelas criadas depois de jun/2026 liberavam qualquer
--     usuário autenticado (inclusive inativo recém-cadastrado):
--     configuracoes (leitura/escrita/exclusão), analises_ia,
--     analises_estrategia_mes, participantes, convites (update) e as
--     tabelas do WhatsApp (QR code de login, envio de mensagens,
--     comando de desconectar).
--  3. [ALTO] convites listável por anônimo (todos os links de Meet /
--     títulos). Agora só via RPC obter_convite(code) — 1 convite por vez.
--  4. [MÉDIO] Tabelas novas herdavam GRANT pro anon por padrão.
--  5. [PERDA DE DADOS] Excluir revenda apagava em cascata histórico,
--     tarefas e handovers sem volta → agora vai pra lixeira
--     (revendas_excluidas). Config global (configuracoes) era
--     sobrescrita sem histórico → agora guarda versão anterior.
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ── 0. Helpers com search_path fixo (evita sequestro de função) ──────
create or replace function public.meu_perfil()
returns text language sql security definer stable
set search_path = public as $$
  select perfil from public.perfis where id = auth.uid()
$$;

create or replace function public.estou_ativo()
returns boolean language sql security definer stable
set search_path = public as $$
  select coalesce((select ativo from public.perfis where id = auth.uid()), false)
$$;

create or replace function public.sou_admin()
returns boolean language sql security definer stable
set search_path = public as $$
  select coalesce((select ativo and perfil = 'Administrador'
                   from public.perfis where id = auth.uid()), false)
$$;

-- ── 1. [CRÍTICO] Bloqueia auto-ativação / auto-promoção ──────────────
-- Lista branca: usuário comum só pode mudar estes campos do próprio
-- perfil. Qualquer outro (ativo, perfil, email, pode_*, colunas futuras)
-- exige Administrador. service_role / SQL Editor (auth.uid() nulo) passa.
create or replace function public.check_perfil_self_update()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  livres text[] := array['nome','avatar_iniciais','atualizado_em','updated_at'];
begin
  if auth.uid() is null or public.sou_admin() then
    return new;
  end if;
  if (to_jsonb(new) - livres) is distinct from (to_jsonb(old) - livres) then
    raise exception 'Sem permissão para alterar estes campos do perfil'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_perfis_self_update_check on public.perfis;
create trigger trg_perfis_self_update_check
  before update on public.perfis
  for each row execute function public.check_perfil_self_update();

-- ── Utilitário: remove TODAS as policies de uma tabela (nomes variam
-- entre os scripts antigos) antes de recriar ─────────────────────────
create or replace function pg_temp.drop_policies(tbl text)
returns void language plpgsql as $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = tbl loop
    execute format('drop policy %I on public.%I', p.policyname, tbl);
  end loop;
end $$;

-- ── 2a. configuracoes: só ativos; excluir só admin ───────────────────
select pg_temp.drop_policies('configuracoes');
create policy cfg_select on public.configuracoes for select to authenticated
  using (public.estou_ativo());
create policy cfg_insert on public.configuracoes for insert to authenticated
  with check (public.estou_ativo());
create policy cfg_update on public.configuracoes for update to authenticated
  using (public.estou_ativo()) with check (public.estou_ativo());
create policy cfg_delete on public.configuracoes for delete to authenticated
  using (public.sou_admin());

-- Histórico de versões da config (recupera config sobrescrita/apagada)
create table if not exists public.configuracoes_historico (
  id            bigint generated always as identity primary key,
  chave         text not null,
  valor_anterior text,
  operacao      text not null,
  alterado_por  uuid,
  alterado_em   timestamptz not null default now()
);
alter table public.configuracoes_historico enable row level security;
select pg_temp.drop_policies('configuracoes_historico');
create policy cfg_hist_select on public.configuracoes_historico for select to authenticated
  using (public.sou_admin());

create or replace function public.guardar_config_anterior()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if tg_op = 'DELETE' or old.valor is distinct from new.valor then
    insert into public.configuracoes_historico (chave, valor_anterior, operacao, alterado_por)
    values (old.chave, old.valor, tg_op, auth.uid());
    -- mantém só as 50 versões mais recentes por chave (controle de espaço)
    delete from public.configuracoes_historico
     where chave = old.chave
       and id not in (select id from public.configuracoes_historico
                       where chave = old.chave order by id desc limit 50);
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists trg_config_historico on public.configuracoes;
create trigger trg_config_historico
  before update or delete on public.configuracoes
  for each row execute function public.guardar_config_anterior();

-- ── 2b. Análises de IA: leitura só para ativos ──────────────────────
select pg_temp.drop_policies('analises_ia');
create policy analises_ia_read on public.analises_ia for select to authenticated
  using (public.estou_ativo());

select pg_temp.drop_policies('analises_estrategia_mes');
create policy estrategia_mes_read on public.analises_estrategia_mes for select to authenticated
  using (public.estou_ativo());

-- ── 2c. participantes: anônimo só insere (página de confirmação) ─────
select pg_temp.drop_policies('participantes');
create policy participantes_select on public.participantes for select to authenticated
  using (public.estou_ativo());
create policy participantes_insert_publico on public.participantes for insert to anon, authenticated
  with check (true);
create policy participantes_delete on public.participantes for delete to authenticated
  using (public.sou_admin());
-- limite de tamanho contra spam/abuso (not valid = não checa linhas antigas)
alter table public.participantes drop constraint if exists participantes_tamanho_chk;
alter table public.participantes add constraint participantes_tamanho_chk check (
  char_length(nome_completo) <= 200 and char_length(empresa) <= 200 and
  char_length(cargo_funcao) <= 200 and char_length(coalesce(origem,'')) <= 400
) not valid;

-- ── 3. convites: sem listagem pública; leitura anônima só por código ─
select pg_temp.drop_policies('convites');
create policy convites_select on public.convites for select to authenticated
  using (public.estou_ativo());
create policy convites_insert on public.convites for insert to authenticated
  with check (public.estou_ativo());
create policy convites_update on public.convites for update to authenticated
  using (public.estou_ativo()) with check (public.estou_ativo());

create or replace function public.obter_convite(p_code text default null, p_task uuid default null)
returns table (meet_url text, titulo text, task_id uuid)
language sql security definer stable
set search_path = public as $$
  select c.meet_url, c.titulo, c.task_id
    from public.convites c
   where ((p_code is not null and c.code = p_code)
       or (p_code is null and p_task is not null and c.task_id = p_task))
     and c.meet_url like 'https://meet.google.com/%'
   limit 1
$$;
revoke all on function public.obter_convite(text, uuid) from public;
grant execute on function public.obter_convite(text, uuid) to anon, authenticated;

-- ── 2d. WhatsApp (só se as tabelas existirem no banco) ───────────────
do $$
begin
  -- QR code de login do WhatsApp: SÓ administrador (quem lê o QR
  -- conecta o próprio celular no número da empresa)
  if to_regclass('public.whatsapp_status') is not null then
    perform pg_temp.drop_policies('whatsapp_status');
    execute 'create policy wa_status_read on public.whatsapp_status for select to authenticated using (public.sou_admin())';
  end if;
  if to_regclass('public.whatsapp_commands') is not null then
    perform pg_temp.drop_policies('whatsapp_commands');
    execute 'create policy wa_cmd_insert on public.whatsapp_commands for insert to authenticated with check (public.sou_admin())';
  end if;
  if to_regclass('public.mensagens_pendentes') is not null then
    perform pg_temp.drop_policies('mensagens_pendentes');
    execute 'create policy mp_read on public.mensagens_pendentes for select to authenticated using (public.estou_ativo())';
    execute 'create policy mp_insert on public.mensagens_pendentes for insert to authenticated with check (public.estou_ativo())';
  end if;
  if to_regclass('public.whatsapp_messages') is not null then
    perform pg_temp.drop_policies('whatsapp_messages');
    execute 'create policy wa_msgs_read on public.whatsapp_messages for select to authenticated using (public.estou_ativo())';
  end if;
end $$;

-- ── 5. Lixeira de revendas (excluir não perde mais histórico) ────────
create table if not exists public.revendas_excluidas (
  id           bigint generated always as identity primary key,
  revenda_id   uuid not null,
  nome         text,
  excluido_em  timestamptz not null default now(),
  excluido_por uuid,
  snapshot     jsonb not null
);
alter table public.revendas_excluidas enable row level security;
select pg_temp.drop_policies('revendas_excluidas');
create policy lixeira_select on public.revendas_excluidas for select to authenticated
  using (public.sou_admin());

create or replace function public.arquivar_revenda_excluida()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.revendas_excluidas (revenda_id, nome, excluido_por, snapshot)
  values (old.id, old.nome, auth.uid(), jsonb_build_object(
    'revenda',   to_jsonb(old),
    'historico', (select coalesce(jsonb_agg(to_jsonb(h)), '[]') from public.historico_cards h where h.revenda_id = old.id),
    'tarefas',   (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.tarefas t where t.revenda_id = old.id),
    'handovers', case when to_regclass('public.handovers') is not null
                      then (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.handovers x where x.revenda_id = old.id)
                      else '[]'::jsonb end
  ));
  return old;
end $$;
drop trigger if exists trg_arquivar_revenda on public.revendas;
create trigger trg_arquivar_revenda
  before delete on public.revendas
  for each row execute function public.arquivar_revenda_excluida();

-- ── 4. Anônimo fora de todas as tabelas (inclusive futuras) ──────────
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('revoke all on public.%I from anon', t);
  end loop;
  for t in select viewname from pg_views where schemaname = 'public' loop
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;
grant insert on public.participantes to anon;   -- confirmacao.html

alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon;

-- meta_mes_atual() hoje responde para ANÔNIMO (metas comerciais do mês vazando)
do $$ begin
  if to_regprocedure('public.meta_mes_atual()') is not null then
    revoke execute on function public.meta_mes_atual() from public, anon;
    grant  execute on function public.meta_mes_atual() to authenticated;
  end if;
end $$;

-- View: garante que respeita o RLS de quem consulta
do $$ begin
  if to_regclass('public.revendas_seguras') is not null then
    execute 'alter view public.revendas_seguras set (security_invoker = true)';
  end if;
end $$;

commit;

-- ══════════════════════════════════════════════════════════════════════
-- VERIFICAÇÃO (rode depois)
-- ══════════════════════════════════════════════════════════════════════
-- Policies que ainda liberam geral (deve voltar só participantes_insert_publico):
-- select tablename, policyname, cmd, roles, qual, with_check from pg_policies
--  where schemaname='public' and (qual = 'true' or with_check = 'true');
--
-- Tabelas sem RLS (deve voltar vazio):
-- select tablename from pg_tables where schemaname='public' and not rowsecurity;
--
-- Usuários ativos — confira se todos são conhecidos (alguém pode ter se
-- auto-ativado antes deste patch!):
-- select p.nome, p.email, p.perfil, p.ativo, u.created_at, u.last_sign_in_at
--   from public.perfis p join auth.users u on u.id = p.id
--  order by u.created_at desc;

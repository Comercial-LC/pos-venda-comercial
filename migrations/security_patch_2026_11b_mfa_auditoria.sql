-- ══════════════════════════════════════════════════════════════════════
-- SECURITY PATCH 2026-11 (b) — 2FA obrigatório para Administrador +
-- auditoria gravada pelo banco
--
-- ⚠️ ORDEM: rode SÓ DEPOIS que o app.html novo (com a tela de 2FA)
-- estiver publicado no GitHub Pages. Se rodar antes, os Administradores
-- perdem acesso aos dados até o deploy terminar.
--
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah. Idempotente,
-- numa transação só.
--
-- O que muda:
--  1. Administrador sem 2FA confirmado na sessão (aal1) passa a valer
--     como "sem acesso" no banco: senha de Admin vazada sozinha não lê
--     nem altera nada. Os demais perfis não mudam.
--  2. Exclusão de revenda, exclusão de usuário e mudança de
--     ativo/perfil/permissões passam a ser registradas na auditoria pelo
--     próprio banco (não dá para pular nem forjar pelo navegador).
--
-- RECUPERAÇÃO — Admin perdeu o celular do autenticador:
--   delete from auth.mfa_factors
--    where user_id = (select id from auth.users where email = 'EMAIL_DO_ADMIN');
--   No próximo login ele cadastra um autenticador novo.
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ── 1. 2FA para Administrador ────────────────────────────────────────
create or replace function public.tenho_2fa()
returns boolean language sql stable
set search_path = public as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;

-- Admin sem 2FA recebe um perfil que não casa com nenhuma policy
-- (nem com "= 'Administrador'", nem com "in (...)"), e "<> 'Administrador'"
-- continua restringindo. Nunca devolve nulo de propósito.
create or replace function public.meu_perfil()
returns text language sql security definer stable
set search_path = public as $$
  select case when perfil = 'Administrador' and not public.tenho_2fa()
              then 'Administrador (2FA pendente)'
              else perfil end
    from public.perfis where id = auth.uid()
$$;

create or replace function public.estou_ativo()
returns boolean language sql security definer stable
set search_path = public as $$
  select coalesce((select ativo and (perfil <> 'Administrador' or public.tenho_2fa())
                     from public.perfis where id = auth.uid()), false)
$$;

create or replace function public.sou_admin()
returns boolean language sql security definer stable
set search_path = public as $$
  select coalesce((select ativo and perfil = 'Administrador' and public.tenho_2fa()
                     from public.perfis where id = auth.uid()), false)
$$;

-- ── 2. Auditoria gravada pelo banco ──────────────────────────────────
create or replace function public.auditar_evento()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  livres  text[] := array['nome','avatar_iniciais','atualizado_em','updated_at'];
  v_nome  text;
  v_email text;
  v_acao  text;
  v_id    uuid;
  v_det   jsonb;
begin
  select nome, email into v_nome, v_email from public.perfis where id = auth.uid();

  if tg_table_name = 'revendas' then          -- só DELETE
    v_acao := 'DELETE';
    v_id   := old.id;
    v_det  := jsonb_build_object('nome', old.nome);

  elsif tg_op = 'DELETE' then                 -- perfis
    v_acao := 'DELETE';
    v_id   := old.id;
    v_det  := jsonb_build_object('nome', old.nome, 'email', old.email, 'perfil', old.perfil);

  else                                        -- perfis UPDATE
    select jsonb_object_agg(o.key, jsonb_build_object('de', o.value, 'para', n.value))
      into v_det
      from jsonb_each(to_jsonb(old)) o
      join jsonb_each(to_jsonb(new)) n using (key)
     where o.value is distinct from n.value
       and not (o.key = any(livres));
    if v_det is null then
      return new;                             -- só nome/avatar: não audita
    end if;
    v_acao := case
      when new.ativo is distinct from old.ativo then
        case when new.ativo then 'USER_ACTIVATED' else 'USER_DEACTIVATED' end
      else 'PERMISSOES_ALTERADAS' end;
    v_id  := new.id;
    v_det := jsonb_build_object('nome', new.nome, 'alteracoes', v_det);
  end if;

  insert into public.auditoria (usuario_id, usuario_nome, usuario_email, acao, tabela, registro_id, detalhe)
  values (auth.uid(), coalesce(v_nome, 'sistema'), v_email, v_acao, tg_table_name, v_id,
          v_det || jsonb_build_object('origem', 'banco'));

  return coalesce(new, old);
end $$;

drop trigger if exists trg_auditar_revenda_delete on public.revendas;
create trigger trg_auditar_revenda_delete
  after delete on public.revendas
  for each row execute function public.auditar_evento();

drop trigger if exists trg_auditar_perfis on public.perfis;
create trigger trg_auditar_perfis
  after update or delete on public.perfis
  for each row execute function public.auditar_evento();

-- Funções novas não ficam expostas ao anônimo
revoke execute on function public.tenho_2fa()      from public, anon;
revoke execute on function public.auditar_evento() from public, anon;
grant  execute on function public.tenho_2fa()      to authenticated;

commit;

-- ══════════════════════════════════════════════════════════════════════
-- VERIFICAÇÃO (rode depois)
-- ══════════════════════════════════════════════════════════════════════
-- Policies que olham perfis.perfil direto (sem meu_perfil/sou_admin) e
-- por isso NÃO exigem 2FA — deve voltar vazio:
-- select tablename, policyname, qual, with_check from pg_policies
--  where schemaname = 'public'
--    and (qual ilike '%perfis%' or with_check ilike '%perfis%');
--
-- Admins que já cadastraram 2FA:
-- select u.email, f.status, f.created_at from auth.mfa_factors f
--   join auth.users u on u.id = f.user_id order by f.created_at desc;

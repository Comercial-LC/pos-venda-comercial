-- ══════════════════════════════════════════════════════════════════════
-- Pipeline: Academy + Decola Instalação + Decola Produtos → "Qualificação"
-- Handover: avaliação (nota 0–10, comentário e imagem opcionais)
-- Execute no SQL Editor do Supabase. Idempotente: pode rodar mais de uma vez.
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ── 1. Constraint de status: troca as 3 etapas por Qualificação ───────
-- Reaproveita a definição atual (preserva etapas customizadas que já
-- estejam liberadas). Se não houver constraint, só migra os dados.
do $$
declare
  r   record;
  def text;
begin
  for r in
    select conname, pg_get_constraintdef(oid) as d
    from pg_constraint
    where conrelid = 'public.revendas'::regclass
      and contype  = 'c'
      and pg_get_constraintdef(oid) like '%status%'
  loop
    execute format('alter table public.revendas drop constraint %I', r.conname);
    def := r.d;
    if def like '%''Academy''%' or def like '%''Decola Produtos''%' then
      def := regexp_replace(def, '''Academy''(::text)?',            '''Qualificação''\1');
      def := regexp_replace(def, ',\s*''Decola Instalação''(::text)?', '');
      def := regexp_replace(def, ',\s*''Decola Produtos''(::text)?',   '');
      -- Se Qualificação ainda não entrou (Academy ausente), acrescenta ao lado de Handover
      if def not like '%''Qualificação''%' then
        def := regexp_replace(def, '''Handover''(::text)?', '''Qualificação''\1, ''Handover''\1');
      end if;
    end if;
    -- guarda pra recriar depois do UPDATE
    create temp table if not exists _status_constraints(nome text, def text) on commit drop;
    insert into _status_constraints values (r.conname, def);
  end loop;
end $$;

update public.revendas
   set status = 'Qualificação', atualizado_em = now()
 where status in ('Academy', 'Decola Instalação', 'Decola Produtos');

do $$
declare r record;
begin
  if to_regclass('pg_temp._status_constraints') is null then return; end if;
  for r in select * from _status_constraints loop
    execute format('alter table public.revendas add constraint %I %s', r.nome, r.def);
  end loop;
end $$;

-- ── 2. Config compartilhada (lc_cfg): substitui as 3 etapas por uma ───
-- A primeira das três (na ordem configurada) vira Qualificação; as outras saem.
with c as (
  select valor::jsonb as v from public.configuracoes where chave = 'lc_cfg'
), e as (
  select elem, ord
  from c, jsonb_array_elements(c.v->'etapas') with ordinality as t(elem, ord)
), primeira as (
  select min(ord) as m from e
  where elem->>'id' in ('Academy','Decola Instalação','Decola Produtos')
), novo as (
  select jsonb_agg(
           case when e.ord = p.m
                then '{"id":"Qualificação","icon":"🎯","cor":"#ec4899"}'::jsonb
                else e.elem end
           order by e.ord) as arr
  from e, primeira p
  where p.m is not null
    and (e.elem->>'id' not in ('Academy','Decola Instalação','Decola Produtos') or e.ord = p.m)
)
update public.configuracoes cfg
   set valor = jsonb_set(cfg.valor::jsonb, '{etapas}', novo.arr)::text,
       atualizado_em = now()
  from novo
 where cfg.chave = 'lc_cfg' and novo.arr is not null;

-- ── 3. Tabela de avaliações do Handover ──────────────────────────────
create table if not exists public.avaliacoes_handover (
  id             uuid primary key default gen_random_uuid(),
  revenda_id     uuid not null references public.revendas(id) on delete cascade,
  nota           smallint not null check (nota between 0 and 10),
  comentario     text check (comentario is null or char_length(comentario) <= 2000),
  imagem_path    text check (imagem_path is null or char_length(imagem_path) <= 300),
  etapa_origem   text,
  avaliador_id   uuid default auth.uid() references public.perfis(id),
  avaliador_nome text,
  criado_em      timestamptz not null default now()
);
create index if not exists idx_aval_handover_revenda on public.avaliacoes_handover(revenda_id, criado_em desc);

alter table public.avaliacoes_handover enable row level security;

drop policy if exists aval_handover_select on public.avaliacoes_handover;
drop policy if exists aval_handover_insert on public.avaliacoes_handover;
drop policy if exists aval_handover_update on public.avaliacoes_handover;
drop policy if exists aval_handover_delete on public.avaliacoes_handover;

create policy aval_handover_select on public.avaliacoes_handover for select to authenticated
  using (public.estou_ativo());
-- Só grava em nome próprio
create policy aval_handover_insert on public.avaliacoes_handover for insert to authenticated
  with check (public.estou_ativo() and avaliador_id = auth.uid());
-- Avaliação é registro: só Admin corrige/apaga
create policy aval_handover_update on public.avaliacoes_handover for update to authenticated
  using (public.sou_admin()) with check (public.sou_admin());
create policy aval_handover_delete on public.avaliacoes_handover for delete to authenticated
  using (public.sou_admin());

-- ── 4. Bucket privado para a imagem (máx. 2 MB; o app já comprime) ────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avaliacoes-handover', 'avaliacoes-handover', false, 2097152,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists aval_handover_img_select on storage.objects;
drop policy if exists aval_handover_img_insert on storage.objects;
drop policy if exists aval_handover_img_delete on storage.objects;

create policy aval_handover_img_select on storage.objects for select to authenticated
  using (bucket_id = 'avaliacoes-handover' and public.estou_ativo());
create policy aval_handover_img_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avaliacoes-handover' and public.estou_ativo());
create policy aval_handover_img_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avaliacoes-handover' and public.sou_admin());

commit;

-- Verificação
select status, count(*) from public.revendas group by status order by status;
select jsonb_path_query_array(valor::jsonb, '$.etapas[*].id') as etapas
  from public.configuracoes where chave = 'lc_cfg';

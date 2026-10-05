-- Tabela para registrar participantes das confirmações de acesso
create table if not exists public.participantes (
  id            uuid primary key default gen_random_uuid(),
  nome_completo text not null,
  empresa       text not null,
  cargo_funcao  text not null,
  data_hora     timestamptz not null,
  origem        text,
  criado_em     timestamptz default now()
);

-- Permite leitura apenas para usuários autenticados do portal
alter table public.participantes enable row level security;

create policy "Leitura apenas autenticados"
  on public.participantes for select
  using (auth.role() = 'authenticated');

-- Permite inserção pública (anon) — necessário para a página de confirmação funcionar sem login
create policy "Inserção pública permitida"
  on public.participantes for insert
  with check (true);

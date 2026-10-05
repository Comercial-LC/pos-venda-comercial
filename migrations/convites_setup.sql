-- Tabela para encurtador de links de convite
-- Permite gerar URLs curtas como: /r.html?t=TASK_UUID
create table if not exists public.convites (
  task_id   uuid primary key,
  meet_url  text not null,
  titulo    text,
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now()
);

alter table public.convites enable row level security;

-- Qualquer pessoa com o link pode ler o convite (necessário para o redirect anônimo)
create policy "Leitura pública de convites"
  on public.convites for select
  using (true);

-- Apenas usuários autenticados do portal criam/atualizam convites
create policy "Inserção por autenticados"
  on public.convites for insert
  with check (auth.role() = 'authenticated');

create policy "Atualização por autenticados"
  on public.convites for update
  using (auth.role() = 'authenticated');

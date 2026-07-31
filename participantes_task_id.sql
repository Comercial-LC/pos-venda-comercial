-- Vincula participantes à tarefa do portal
alter table public.participantes
  add column if not exists task_id uuid;

create index if not exists idx_participantes_task_id
  on public.participantes(task_id);

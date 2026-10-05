-- ── Migração: CS Manager também pode lançar/editar Metas Comerciais ──
-- Execute no Supabase SQL Editor (apenas uma vez).
-- Hoje só o perfil Administrador tem permissão de INSERT/UPDATE na
-- tabela orion_metas (RLS) — qualquer outro perfil clica em Salvar e
-- recebe erro silencioso de permissão. Isso abre INSERT/UPDATE também
-- para CS Manager. Exclusão de meta continua restrita a Administrador.
-- ─────────────────────────────────────────────────────────────────────

drop policy if exists "orion_metas_insert" on public.orion_metas;
create policy "orion_metas_insert" on public.orion_metas
  for insert with check (public.meu_perfil() in ('Administrador','CS Manager'));

drop policy if exists "orion_metas_update" on public.orion_metas;
create policy "orion_metas_update" on public.orion_metas
  for update using (public.meu_perfil() in ('Administrador','CS Manager'));

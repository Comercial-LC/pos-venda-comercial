-- ═══════════════════════════════════════════════════════════════════
-- PATCH DE SEGURANÇA — Portal Revenda LC
-- Execute INTEIRO no SQL Editor do Supabase (supabase.com → SQL Editor)
-- Corrige: C4 C5 G4 M3 + anon role bloqueado
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. BLOQUEAR role anon em todas as tabelas ─────────────────────
-- A ANON key é pública no código. Garantimos que ela não lê nada.
do $$
declare
  t text;
begin
  for t in
    select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- ── 2. METAS: apenas Administrador insere via app ─────────────────
-- (service_role do webhook bypassa RLS — continua funcionando)
drop policy if exists "orion_metas_insert" on public.orion_metas;
create policy "orion_metas_insert" on public.orion_metas
  for insert with check (
    public.meu_perfil() = 'Administrador'
  );

-- ── 3. LEADS: apenas webhook (service_role) insere ────────────────
-- service_role bypassa RLS automaticamente — usuários ficam bloqueados
drop policy if exists "orion_leads_insert" on public.orion_leads_vendidos;
create policy "orion_leads_insert" on public.orion_leads_vendidos
  for insert with check (false);

-- ── 4. AUDITORIA: insert vinculado ao usuário autenticado ─────────
-- service_role do webhook bypassa essa policy e continua inserindo
drop policy if exists "auditoria_insert" on public.auditoria;
create policy "auditoria_insert" on public.auditoria
  for insert with check (
    usuario_id = auth.uid()
    or usuario_id is null  -- operações do sistema sem usuário associado
  );

-- ── 5. REMOVE auto-promoção para Administrador ────────────────────
-- Antes: primeiro usuário virava Admin automaticamente (risco em resets)
-- Agora: todos nascem como CS Analyst inativo — Admin ativa manualmente
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  nome_usuario text;
  iniciais     text;
begin
  nome_usuario := coalesce(
    new.raw_user_meta_data->>'nome',
    split_part(new.email, '@', 1)
  );
  iniciais := upper(left(split_part(nome_usuario,' ',1),1) ||
               left(split_part(nome_usuario,' ',2),1));
  if iniciais = '' then iniciais := upper(left(nome_usuario,2)); end if;

  insert into public.perfis (
    id, nome, email, perfil, avatar_iniciais, ativo,
    pode_criar_revenda, pode_editar_revenda, pode_excluir_revenda,
    pode_ver_cnpj, pode_exportar, pode_importar,
    pode_gerenciar_usuarios, pode_ver_relatorios, pode_handover
  ) values (
    new.id,
    nome_usuario,
    new.email,
    'CS Analyst',   -- Nunca auto-promove. Admin deve promover manualmente.
    iniciais,
    false,          -- Inativo até Admin ativar (evita acesso indevido em reset de BD)
    true, true, false, false, false, false, false, true, true
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- ── 6. GARANTE que a view segura não é acessível por anon ─────────
revoke all on public.revendas_seguras from anon;

-- ── 7. ADICIONA índice composto para otimizar queries de CS ───────
create index if not exists idx_revendas_cs_status
  on public.revendas(cs_id, status);
create index if not exists idx_historico_descricao_motivo
  on public.historico_cards(descricao text_pattern_ops)
  where descricao like '%Motivo:%';

-- ── 8. CONFIRMA que RLS está ativo em todas as tabelas ────────────
do $$
declare
  t text;
  resultado text := '';
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public'
    order by tablename
  loop
    if not exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = t and c.relrowsecurity = true
    ) then
      execute format('alter table public.%I enable row level security', t);
      resultado := resultado || t || ' (RLS ativado agora), ';
    end if;
  end loop;
  if resultado = '' then
    raise notice 'RLS já ativo em todas as tabelas ✅';
  else
    raise notice 'RLS ativado em: %', resultado;
  end if;
end $$;

select '✅ Patch de segurança aplicado com sucesso!' as resultado;

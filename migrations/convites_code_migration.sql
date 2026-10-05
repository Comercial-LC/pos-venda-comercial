-- Adiciona coluna de código curto à tabela convites
-- Execute no Supabase SQL Editor após o convites_setup.sql

alter table public.convites
  add column if not exists code text;

create unique index if not exists convites_code_idx
  on public.convites(code);

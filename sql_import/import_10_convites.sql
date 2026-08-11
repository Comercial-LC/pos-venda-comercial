-- ══════════════════════════════════════════════════════════════════
-- IMPORT 10 — Criar tabela convites (links curtos para Google Meet)
-- Gera URLs como: /r.html?c=AbC123  →  confirmacao.html?meet=...
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.convites (
  code          text        PRIMARY KEY,          -- código de 6 chars (ex: AbC123)
  task_id       uuid        UNIQUE NOT NULL,       -- 1 convite por tarefa
  meet_url      text        NOT NULL,
  titulo        text        NOT NULL DEFAULT '',
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

-- Índice para busca por task_id (usado no fallback ?t=UUID)
CREATE INDEX IF NOT EXISTS convites_task_id_idx ON public.convites(task_id);

-- RLS: leitura pública (r.html roda sem login), escrita só autenticado
ALTER TABLE public.convites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "convites_select_public"
  ON public.convites FOR SELECT
  USING (true);

CREATE POLICY "convites_insert_auth"
  ON public.convites FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "convites_update_auth"
  ON public.convites FOR UPDATE
  USING (auth.uid() IS NOT NULL);

-- Verificação
SELECT count(*) AS total_convites FROM public.convites;

-- ── Tabela: whatsapp_commands ───────────────────────────────────────
-- Fila de comandos do portal para o serviço Node.js (ex: disconnect).
-- Execute no Supabase SQL Editor.
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.whatsapp_commands (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action      text NOT NULL,
  executed_at timestamptz,
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE public.whatsapp_commands ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wc_insert" ON public.whatsapp_commands
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "wc_service" ON public.whatsapp_commands
  FOR ALL TO service_role USING (true);

ALTER PUBLICATION supabase_realtime ADD TABLE public.whatsapp_commands;

-- ── Tabela: whatsapp_messages ───────────────────────────────────────
-- Histórico completo de mensagens trocadas via WhatsApp por revenda.
-- Execute no Supabase SQL Editor.
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.whatsapp_messages (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revenda_id uuid NOT NULL REFERENCES public.revendas(id) ON DELETE CASCADE,
  direction  text NOT NULL CHECK (direction IN ('inbound','outbound')),
  body       text NOT NULL DEFAULT '',
  phone      text,
  status     text DEFAULT 'delivered',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_msgs_revenda
  ON public.whatsapp_messages (revenda_id, created_at DESC);

ALTER TABLE public.whatsapp_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wa_msgs_read" ON public.whatsapp_messages
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "wa_msgs_write" ON public.whatsapp_messages
  FOR ALL TO service_role USING (true);

ALTER PUBLICATION supabase_realtime ADD TABLE public.whatsapp_messages;


-- ── Tabela: mensagens_pendentes ──────────────────────────────────────
-- Fila de envio: portal insere aqui, serviço Node.js envia e marca como sent.

CREATE TABLE IF NOT EXISTS public.mensagens_pendentes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revenda_id uuid NOT NULL,
  phone      text NOT NULL,
  body       text NOT NULL,
  status     text DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.mensagens_pendentes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mp_read" ON public.mensagens_pendentes
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "mp_insert" ON public.mensagens_pendentes
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "mp_service" ON public.mensagens_pendentes
  FOR ALL TO service_role USING (true);

ALTER PUBLICATION supabase_realtime ADD TABLE public.mensagens_pendentes;

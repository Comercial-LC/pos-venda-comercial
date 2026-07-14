-- ── Tabela: whatsapp_status ─────────────────────────────────────────
-- Armazena estado da conexão WhatsApp (singleton — sempre id = 1).
-- Execute no Supabase SQL Editor antes de iniciar o serviço.
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.whatsapp_status (
  id         integer PRIMARY KEY DEFAULT 1,
  status     text NOT NULL DEFAULT 'desconectado',
  qr_code    text,
  numero     text,
  updated_at timestamptz DEFAULT now()
);

-- Garante que só existe 1 linha
CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_status_singleton
  ON public.whatsapp_status (id);

-- Linha inicial
INSERT INTO public.whatsapp_status (id, status)
VALUES (1, 'desconectado')
ON CONFLICT (id) DO NOTHING;

-- RLS
ALTER TABLE public.whatsapp_status ENABLE ROW LEVEL SECURITY;

CREATE POLICY "whatsapp_status_read" ON public.whatsapp_status
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "whatsapp_status_write" ON public.whatsapp_status
  FOR ALL TO service_role USING (true);

-- Habilita Realtime para esta tabela
ALTER PUBLICATION supabase_realtime ADD TABLE public.whatsapp_status;

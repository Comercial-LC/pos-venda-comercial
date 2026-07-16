-- ── Migração: colunas de mídia no WhatsApp ───────────────────────────
-- Execute no Supabase SQL Editor (apenas uma vez).
-- Adiciona suporte a imagem, áudio, vídeo e figurinha no chat.
-- ─────────────────────────────────────────────────────────────────────

-- 1. whatsapp_messages: adiciona colunas de mídia + torna revenda_id nullable
ALTER TABLE public.whatsapp_messages
  ALTER COLUMN revenda_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS media_base64   text,
  ADD COLUMN IF NOT EXISTS media_mimetype text,
  ADD COLUMN IF NOT EXISTS media_filename text;

-- 2. mensagens_pendentes: torna revenda_id nullable + adiciona colunas de mídia
ALTER TABLE public.mensagens_pendentes
  ALTER COLUMN revenda_id DROP NOT NULL,
  ALTER COLUMN body SET DEFAULT '',
  ADD COLUMN IF NOT EXISTS media_base64    text,
  ADD COLUMN IF NOT EXISTS media_mimetype  text,
  ADD COLUMN IF NOT EXISTS media_filename  text,
  ADD COLUMN IF NOT EXISTS media_as_sticker boolean DEFAULT false;

-- Índice para buscas por status (polling de pendentes)
CREATE INDEX IF NOT EXISTS idx_mp_status
  ON public.mensagens_pendentes (status, created_at);

-- Migração: adiciona contact_name em whatsapp_messages
-- Execute no Supabase SQL Editor (apenas uma vez).
-- Armazena o nome do contato (pushname do WhatsApp) para mensagens de IDs @lid ou desconhecidos.

ALTER TABLE public.whatsapp_messages
  ADD COLUMN IF NOT EXISTS contact_name text;

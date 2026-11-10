-- ══════════════════════════════════════════════════════════════════════
-- Remove do banco as tabelas do serviço WhatsApp (desativado em 10/11/2026)
--
-- Elas guardavam QR code de login, comandos e conteúdo de mensagens —
-- dados pessoais sem uso (LGPD: não manter o que não se usa). O portal
-- não lê nenhuma delas e o backup diário não as inclui.
--
-- ⚠️ IRREVERSÍVEL. Se quiser guardar uma cópia antes, exporte pelo
-- Table Editor (botão "Export to CSV") de cada tabela.
--
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah.
-- ══════════════════════════════════════════════════════════════════════

-- Quantas linhas cada uma tem (rode antes, se quiser conferir):
-- select 'whatsapp_status' t, count(*) from public.whatsapp_status union all
-- select 'whatsapp_commands', count(*) from public.whatsapp_commands union all
-- select 'whatsapp_messages', count(*) from public.whatsapp_messages union all
-- select 'mensagens_pendentes', count(*) from public.mensagens_pendentes;

begin;
drop table if exists public.whatsapp_status     cascade;
drop table if exists public.whatsapp_commands   cascade;
drop table if exists public.whatsapp_messages   cascade;
drop table if exists public.mensagens_pendentes cascade;
commit;

-- Depois, apague também as Edge Functions e o segredo (PowerShell):
--   $env:SUPABASE_ACCESS_TOKEN = "sbp_..."
--   supabase functions delete dynamic-processor --project-ref xuymxedyuywahcfcdcah
--   supabase secrets unset WHATSAPP_WEBHOOK_SECRET --project-ref xuymxedyuywahcfcdcah

-- Corrige phone em whatsapp_messages: dígitos puros de @lid (> 13 dígitos)
-- foram armazenados sem sufixo @lid por bug anterior. Adiciona o sufixo.
UPDATE public.whatsapp_messages
SET phone = phone || '@lid'
WHERE phone IS NOT NULL
  AND phone NOT LIKE '%@%'
  AND phone ~ '^\d+$'
  AND length(phone) > 13;

-- Mesmo para mensagens_pendentes com phone inválido na fila
UPDATE public.mensagens_pendentes
SET phone = phone || '@lid'
WHERE phone IS NOT NULL
  AND phone NOT LIKE '%@%'
  AND phone ~ '^\d+$'
  AND length(phone) > 13;

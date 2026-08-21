-- ── Migração: Análise do Mês — tags de progresso comercial ──────────
-- Execute no Supabase SQL Editor (apenas uma vez).
-- Adiciona os campos que o algoritmo de classificação da aba
-- "Análise do Mês" usa para ler o histórico dos cards.
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.historico_cards
  ADD COLUMN IF NOT EXISTS tag           text,
  ADD COLUMN IF NOT EXISTS data_prevista date,
  ADD COLUMN IF NOT EXISTS quantidade    integer;

-- Restringe aos 15 valores oficiais (nulo continua permitido — registros
-- automáticos do sistema, como mudança de etapa ou mensagens de WhatsApp,
-- não usam tag).
ALTER TABLE public.historico_cards DROP CONSTRAINT IF EXISTS historico_cards_tag_check;
ALTER TABLE public.historico_cards ADD CONSTRAINT historico_cards_tag_check
  CHECK (tag IS NULL OR tag IN (
    'TREINAMENTO','PROSPECCAO','CLIENTE_PREVISTO','CLIENTE_EM_NEGOCIACAO',
    'DEMONSTRACAO','CLIENTE_SUBIDO','INSTALACAO','SEM_RETORNO','SEM_PREVISAO',
    'PAUSADO','DIFICULDADE','DOENCA_AUSENCIA','PROMESSA_SEM_EVOLUCAO',
    'NAO_RESPONDE','OUTROS'
  ));

-- Índice para a leitura em lote que a Análise do Mês faz (só linhas com tag)
CREATE INDEX IF NOT EXISTS idx_historico_tag
  ON public.historico_cards (revenda_id, criado_em)
  WHERE tag IS NOT NULL;

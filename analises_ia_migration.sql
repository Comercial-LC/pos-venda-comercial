-- ── Migração: LC Success AI — análises de IA por revenda ─────────────
-- Execute no Supabase SQL Editor (apenas uma vez).
-- Tabela separada do histórico operacional (historico_cards) — guarda
-- o resultado completo de cada análise gerada pelo Gemini.
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.analises_ia (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revenda_id          uuid NOT NULL REFERENCES public.revendas(id) ON DELETE CASCADE,
  criado_em           timestamptz NOT NULL DEFAULT now(),
  modelo              text NOT NULL,
  score_saude         integer,
  nivel_risco         text CHECK (nivel_risco IS NULL OR nivel_risco IN ('BAIXO','MÉDIO','ALTO','CRÍTICO')),
  resultado_completo  jsonb,
  dados_utilizados    jsonb,
  status              text NOT NULL DEFAULT 'sucesso' CHECK (status IN ('sucesso','erro','processando')),
  erro_mensagem       text,
  trigger_origem      text NOT NULL DEFAULT 'manual',
  usuario_id          uuid,
  usuario_nome        text
);

CREATE INDEX IF NOT EXISTS idx_analises_ia_revenda
  ON public.analises_ia (revenda_id, criado_em DESC);

ALTER TABLE public.analises_ia ENABLE ROW LEVEL SECURITY;

-- Qualquer usuário autenticado do portal pode ver as análises
CREATE POLICY "analises_ia_read" ON public.analises_ia
  FOR SELECT TO authenticated USING (true);

-- Só a Edge Function (service_role) grava — nunca o navegador direto
CREATE POLICY "analises_ia_service_write" ON public.analises_ia
  FOR ALL TO service_role USING (true);

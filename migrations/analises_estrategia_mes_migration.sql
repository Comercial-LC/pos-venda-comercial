-- ── Migração: LC Success AI — Estratégia do Mês (nível portfólio) ────
-- Execute no Supabase SQL Editor (apenas uma vez).
-- Separada de analises_ia (que é por revenda) — aqui é uma análise
-- agregada de todas as revendas em relação à meta comercial do mês.
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.analises_estrategia_mes (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mes                 integer NOT NULL,
  ano                 integer NOT NULL,
  criado_em           timestamptz NOT NULL DEFAULT now(),
  modelo              text NOT NULL,
  resultado_completo  jsonb,
  dados_utilizados    jsonb,
  status              text NOT NULL DEFAULT 'sucesso' CHECK (status IN ('sucesso','erro')),
  erro_mensagem       text,
  usuario_id          uuid,
  usuario_nome        text
);

CREATE INDEX IF NOT EXISTS idx_estrategia_mes_periodo
  ON public.analises_estrategia_mes (ano, mes, criado_em DESC);

ALTER TABLE public.analises_estrategia_mes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "estrategia_mes_read" ON public.analises_estrategia_mes
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "estrategia_mes_service_write" ON public.analises_estrategia_mes
  FOR ALL TO service_role USING (true);

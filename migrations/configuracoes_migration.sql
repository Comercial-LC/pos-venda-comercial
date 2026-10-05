-- ── Migração: tabela configuracoes (nunca foi criada!) ───────────────
-- Execute no Supabase SQL Editor (apenas uma vez).
-- saveCfg()/carregarCfgDoSupabase() em app.html já esperavam essa
-- tabela desde sempre — sem ela, toda alteração em Configurações
-- (TV, cores, identidade, etapas, produtos, campos) só ficava salva
-- no localStorage do navegador que fez a mudança, nunca sincronizava
-- para outros dispositivos/sessões (ex: a TV).
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.configuracoes (
  chave         text PRIMARY KEY,
  valor         text NOT NULL,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;

-- Qualquer usuário autenticado do portal pode ler e gravar — é
-- configuração compartilhada do sistema, não dado por usuário.
CREATE POLICY "configuracoes_authenticated_all" ON public.configuracoes
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

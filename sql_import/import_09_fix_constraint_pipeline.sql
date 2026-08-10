-- ══════════════════════════════════════════════════════════════════
-- IMPORT 09 — Corrigir constraint do pipeline
-- O app usa 'Decola 1 Cliente' mas o constraint tinha 'Primeiro Cliente'
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah
-- ══════════════════════════════════════════════════════════════════

-- Passo 1: migrar quaisquer registros que tenham o valor antigo
UPDATE public.revendas
SET status = 'Decola 1 Cliente'
WHERE status = 'Primeiro Cliente';

-- Passo 2: dropar o constraint antigo e recriar com o valor correto
ALTER TABLE public.revendas
  DROP CONSTRAINT IF EXISTS revendas_status_check;

ALTER TABLE public.revendas
  ADD CONSTRAINT revendas_status_check
    CHECK (status IN (
      'Nova Revenda',
      'Implantação',
      'Liberação Web',
      'Academy',
      'Decola Instalação',
      'Decola Produtos',
      'Decola 1 Cliente',
      'Handover',
      'Inativo',
      'Pausados',
      'Sem Retorno'
    ));

-- Verificação
SELECT constraint_name, check_clause
FROM information_schema.check_constraints
WHERE constraint_name = 'revendas_status_check';

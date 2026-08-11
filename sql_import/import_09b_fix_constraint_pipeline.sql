-- ══════════════════════════════════════════════════════════════════
-- IMPORT 09b — Corrigir constraint do pipeline (ordem correta)
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah
-- ══════════════════════════════════════════════════════════════════

-- Passo 1: Dropar TODOS os constraints de check sobre status
-- (pode existir constraint com nome diferente do esperado)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.revendas'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.revendas DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;
END $$;

-- Passo 2: Migrar 'Primeiro Cliente' → 'Decola 1 Cliente'
-- (agora sem constraint ativo, não vai falhar)
UPDATE public.revendas
SET status = 'Decola 1 Cliente'
WHERE status = 'Primeiro Cliente';

-- Passo 3: Recriar constraint correto
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

-- Verificação: deve listar só valores válidos
SELECT status, count(*) AS total
FROM public.revendas
GROUP BY status
ORDER BY status;

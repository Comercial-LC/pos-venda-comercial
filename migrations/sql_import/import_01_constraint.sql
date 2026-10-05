-- ═══════════════════════════════════════════════════════════════════
-- IMPORTAÇÃO DE DADOS HISTÓRICOS — Portal Revenda LC
-- Execute no SQL Editor do Supabase (projeto xuymxedyuywahcfcdcah)
-- Papel: postgres  |  Execute cada bloco separadamente
-- ═══════════════════════════════════════════════════════════════════

-- ── PASSO 1: Ampliar constraint de status (inclui Inativo/Pausados/Sem Retorno) ──
ALTER TABLE public.revendas DROP CONSTRAINT IF EXISTS revendas_status_check;
ALTER TABLE public.revendas ADD CONSTRAINT revendas_status_check
  CHECK (status IN (
    'Nova Revenda','Implantação','Liberação Web','Academy',
    'Decola Instalação','Decola Produtos','Primeiro Cliente','Handover',
    'Inativo','Pausados','Sem Retorno'
  ));

SELECT 'Constraint atualizado. Pode continuar com os próximos passos.' AS ok;

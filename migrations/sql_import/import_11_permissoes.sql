-- ══════════════════════════════════════════════════════════════════
-- IMPORT 11 — Corrigir permissões dos perfis de usuário
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah
-- ══════════════════════════════════════════════════════════════════

-- Administrador: acesso total
UPDATE public.perfis SET
  pode_criar_revenda    = true,
  pode_editar_revenda   = true,
  pode_excluir_revenda  = true,
  pode_ver_cnpj         = true,
  pode_exportar         = true,
  pode_importar         = true,
  pode_gerenciar_usuarios = true,
  pode_ver_relatorios   = true,
  pode_handover         = true,
  atualizado_em         = now()
WHERE perfil = 'Administrador';

-- CS Manager: sem excluir, sem gerenciar usuários, sem importar
UPDATE public.perfis SET
  pode_criar_revenda    = true,
  pode_editar_revenda   = true,
  pode_excluir_revenda  = false,
  pode_ver_cnpj         = true,
  pode_exportar         = true,
  pode_importar         = false,
  pode_gerenciar_usuarios = false,
  pode_ver_relatorios   = true,
  pode_handover         = true,
  atualizado_em         = now()
WHERE perfil = 'CS Manager';

-- Verificação: mostra todas as permissões por usuário
SELECT nome, perfil, pode_importar, pode_gerenciar_usuarios, pode_exportar, pode_ver_cnpj
FROM public.perfis
WHERE ativo = true
ORDER BY perfil, nome;

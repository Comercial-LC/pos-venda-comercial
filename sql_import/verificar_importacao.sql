-- ═══════════════════════════════════════════════════════════════
-- VERIFICAÇÃO DA IMPORTAÇÃO — Portal Revenda LC
-- Execute no SQL Editor (papel: postgres)
-- Valores esperados baseados no backup.json
-- ═══════════════════════════════════════════════════════════════

SELECT
  'revendas'   AS tabela,
  count(*)     AS no_banco,
  650        AS esperado,
  CASE WHEN count(*) = 650 THEN '✓ OK' ELSE '✗ DIFERENTE' END AS status
FROM public.revendas

UNION ALL

SELECT
  'tarefas',
  count(*),
  15,
  CASE WHEN count(*) = 15 THEN '✓ OK' ELSE '✗ DIFERENTE' END
FROM public.tarefas

UNION ALL

SELECT
  'atividades',
  count(*),
  62,
  CASE WHEN count(*) = 62 THEN '✓ OK' ELSE '✗ DIFERENTE' END
FROM public.atividades

UNION ALL

SELECT
  'perfis',
  count(*),
  5,
  CASE WHEN count(*) = 5 THEN '✓ OK' ELSE '✗ DIFERENTE' END
FROM public.perfis;

-- ── Distribuição de status (esperado do backup) ──────────────────
  -- 436x Handover
  -- 80x Inativo
  -- 39x Sem Retorno
  -- 32x Academy
  -- 31x Decola Produtos
  -- 11x Pausados
  -- 11x Implantação
  -- 6x Decola Instalação
  -- 4x Primeiro Cliente

SELECT status, count(*) AS qtd
FROM public.revendas
GROUP BY status
ORDER BY qtd DESC;

-- ── Checagem de FKs quebradas ────────────────────────────────────
SELECT 'revendas sem criado_por válido' AS check,
       count(*) AS qtd
FROM public.revendas r
WHERE r.criado_por IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.perfis p WHERE p.id = r.criado_por)

UNION ALL

SELECT 'tarefas com revenda_id inválido',
       count(*)
FROM public.tarefas t
WHERE t.revenda_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.revendas r WHERE r.id = t.revenda_id)

UNION ALL

SELECT 'atividades com usuario_id inválido',
       count(*)
FROM public.atividades a
WHERE a.usuario_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.perfis p WHERE p.id = a.usuario_id);

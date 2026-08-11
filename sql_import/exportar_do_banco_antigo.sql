-- ═══════════════════════════════════════════════════════════════════
-- EXPORTAÇÃO DO BANCO ANTIGO — Portal Revenda LC
-- Execute no SQL Editor do PROJETO ANTIGO (não no novo!)
-- Copie o resultado JSON e envie para gerar o script de importação
-- ═══════════════════════════════════════════════════════════════════

SELECT json_build_object(

  -- Histórico dos cards (anotações manuais e automáticas por revenda)
  'historico_cards',
  (SELECT json_agg(h ORDER BY h.criado_em)
   FROM public.historico_cards h),

  -- Metas comerciais (junho, julho, agosto e anteriores)
  'orion_metas',
  (SELECT json_agg(m ORDER BY m.ano, m.mes)
   FROM public.orion_metas m),

  -- Trilhas de treinamento
  'treinamentos',
  (SELECT json_agg(t ORDER BY t.criado_em)
   FROM public.treinamentos t),

  -- Participantes confirmados nos treinamentos
  'participantes',
  (SELECT json_agg(p ORDER BY p.criado_em)
   FROM public.participantes p)

) AS backup_complementar;

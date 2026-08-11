-- ══════════════════════════════════════════════════════
-- IMPORT 06 — orion_metas (5 registros)
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah
-- ══════════════════════════════════════════════════════

INSERT INTO public.orion_metas
  (id, nome, tipo, valor_meta, valor_atual, percentual, mes, ano, status, _orion_raw, criado_em, atualizado_em)
VALUES
  ('3d9cfa1b-11d8-4227-824c-c656621ac3c4','Contrato de Novas Revendas','quantidade',35,10,29,6,2026,'critica',NULL,'2026-06-09T19:01:30.303868+00:00','2026-06-29T11:02:02.399+00:00'),
  ('90cb39ec-35db-4001-9e73-56c4b66edc84','LC ERP','quantidade',250,209,84,6,2026,'atencao',NULL,'2026-06-09T19:01:30.303868+00:00','2026-06-30T20:01:12.062+00:00'),
  ('07116fe5-8de2-497b-90c0-0645be9c0f0c','Contratos','quantidade',35,16,46,7,2026,'critica',NULL,'2026-07-01T11:16:41.064583+00:00','2026-07-31T17:02:43.125+00:00'),
  ('ddcdec6c-5315-4ab8-a588-c47517b86aac','LC ERP','quantidade',250,265,106,7,2026,'atingida',NULL,'2026-07-01T11:17:07.289595+00:00','2026-08-03T11:14:00.399+00:00'),
  ('02463a27-696f-4c48-bb0b-b2a532a33515','LC ERP','quantidade',250,30,12,8,2026,'critica',NULL,'2026-08-03T11:18:48.054693+00:00','2026-08-04T20:34:34.316+00:00')
ON CONFLICT (id) DO NOTHING;

SELECT nome, mes, ano, valor_meta, valor_atual, percentual, status FROM public.orion_metas ORDER BY ano, mes;

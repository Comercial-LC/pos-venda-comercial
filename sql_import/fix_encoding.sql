-- ═══════════════════════════════════════════════════
-- CORREÇÃO DE ENCODING — Execute no SQL Editor
-- ═══════════════════════════════════════════════════

-- ── TAREFAS (4 títulos com Ç/Ã maiúsculos) ────────
UPDATE public.tarefas SET titulo = 'DECOLA REVENDA  - BALCÃO/GOURMET' WHERE id = 'c0721a5f-77f1-44bf-8d0e-1caa333aee0f';
UPDATE public.tarefas SET titulo = 'Entenda como a Reforma Tributária vai impactar sua revenda.' WHERE id = '648ffaa0-93b1-42ec-9971-b7ce11c78ef1';
UPDATE public.tarefas SET titulo = 'TREINAMENTO DECOLA REVENDA - INSTALAÇÃO' WHERE id = 'b8af0226-b180-4e3e-a768-37e853fb29d4';
UPDATE public.tarefas SET titulo = 'TREINAMENTO DECOLA REVENDA - ORDEM DE SERVIÇO' WHERE id = '1f99e4d0-f79b-4741-a41a-cfe8db381837';

-- ── REVENDAS (nomes com Ç/Ã maiúsculos) ───────────
UPDATE public.revendas SET nome = 'LÚCIO HENRIQUE GONDIM GONÇALVES' WHERE id = '6e1d9044-9c3f-46c6-b3f4-91781ce26080';
UPDATE public.revendas SET nome = 'JALVES PRODUTOS E SERVIÇOS' WHERE id = '1de73bc8-2eb4-4b1d-b0ef-1d62d5efbec9';
UPDATE public.revendas SET nome = 'URAIM INFORMÁTICA' WHERE id = 'dbd7884b-f722-4d1c-b7aa-50c01c667a93';
UPDATE public.revendas SET nome = 'ATLAS SOLUTION AUTOMAÇÃO COMERCIAL' WHERE id = '70848fb7-7f78-4837-b73e-0143f9ee6c47';
UPDATE public.revendas SET nome = 'SUPORTE INFO/SOLUÇÕES EM INFORMATICA' WHERE id = '388128e3-29a7-43b5-b0b4-6c06dc7dd927';
UPDATE public.revendas SET nome = 'PROEASY SOLUÇOES TECNOLOGICAS' WHERE id = 'd5376c0b-5a09-4eb7-ac19-a098cd9fdac9';
UPDATE public.revendas SET nome = 'LÓGICA TECNOLOGIA' WHERE id = '972b71ef-af5a-4a1d-8601-9263cf0d582f';
UPDATE public.revendas SET nome = 'IF REPRESENTAÇÕES E INFORMÁTICA' WHERE id = 'e9c8ab76-ce5e-400a-999c-93f60440204a';
UPDATE public.revendas SET nome = 'TARDIVO AUTOMAÇÃO' WHERE id = '954bc141-5f44-46f4-85c2-871415eb5cea';
UPDATE public.revendas SET nome = 'TECH PLACE SISTEMAS DE AUTOMAÇÃO COMERCIAL' WHERE id = 'b7ead48f-4f52-4996-9161-2cb542e473df';
UPDATE public.revendas SET nome = 'SMART GRÁFICA E AUTOMAÇÃO COMERCIAL' WHERE id = 'dbcd6e3e-8309-4bf5-8538-e72162f0feb8';
UPDATE public.revendas SET nome = 'LC INFORMÁTICA' WHERE id = '415fe704-a560-441b-8df9-13b022ed29d3';
UPDATE public.revendas SET nome = 'LOJÃO DOS COMPUTADORES' WHERE id = '418d6737-0248-4ab7-87d6-5012ad03fb1c';
UPDATE public.revendas SET nome = 'AE SERVIÇOS' WHERE id = '9a5846e0-9e46-4d4d-bd61-68cd297c0c2d';
UPDATE public.revendas SET nome = 'ATX SOLUÇÕES EM INFORMÁTICA' WHERE id = '2ed1f70c-d339-4acc-824d-23da2caf9e3c';
UPDATE public.revendas SET nome = 'NEW LÍDER AUTOMAÇÃO' WHERE id = 'b1c3fc20-660b-493e-b3c9-7ace5e56117d';
UPDATE public.revendas SET nome = 'EVANDRO CANTÃO' WHERE id = '9b936b99-cb25-4f82-afd2-47d42415f69c';
UPDATE public.revendas SET nome = 'DIGITAL SOLUTIOS ARAXÁ' WHERE id = 'c8b818c6-745e-490a-afe0-2f76ee382f6b';
UPDATE public.revendas SET nome = 'J A SOLUÇÕES TECNOLOGICAS' WHERE id = 'bfc9825e-393c-43d1-b52d-12eaac229dc9';
UPDATE public.revendas SET nome = 'SIS GESTÃO FACIL' WHERE id = '9bdfaca6-6b10-464d-b71d-dff63df5599e';
UPDATE public.revendas SET nome = 'ALFASOFT INFOMÁTICA' WHERE id = '43bad7ec-9e63-4068-9833-f7316af85dd3';
UPDATE public.revendas SET nome = 'PRIMEGUIA SOLUÇÕES TECNOLOGICAS' WHERE id = 'c3642e45-9e18-4f91-a467-e87ae0af5819';
UPDATE public.revendas SET nome = 'PRIME AUTOMAÇÃO COMERCIAL' WHERE id = 'a60b2060-5a09-4207-8647-38a37c1bf549';

-- Verificação:
SELECT 'tarefas' AS tabela, titulo FROM public.tarefas WHERE titulo LIKE '%INSTALA%' OR titulo LIKE '%SERVI%' OR titulo LIKE '%BALC%';

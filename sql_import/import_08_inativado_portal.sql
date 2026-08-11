-- ══════════════════════════════════════════════════════
-- IMPORT 08 — Restaurar inativado_portal = true (71 revendas)
-- Execute no SQL Editor do projeto xuymxedyuywahcfcdcah
-- ══════════════════════════════════════════════════════

-- Passo 1: adicionar coluna que faltou no schema do novo projeto
ALTER TABLE public.revendas
  ADD COLUMN IF NOT EXISTS inativado_portal boolean DEFAULT false;

-- Passo 2: marcar as 71 revendas que tinham o botão ativado
UPDATE public.revendas
SET inativado_portal = true
WHERE id IN (
  '63d3648d-aa29-4113-a5df-7e4dad4bc1f1',
  'a3c32af6-2c83-425c-b4f3-fbe84f267592',
  '265ed43e-c770-48f2-b76c-62e9a39acf01',
  '09534e33-8884-45e1-9822-7c1247b88734',
  'ec7d251c-a9fc-4e34-ac95-0e9fc3f345c8',
  '081cd505-5cef-4a39-aa0a-44611729cbe2',
  '8145e31d-26d3-4f66-8da9-70ece3868a5b',
  '224cdc51-177a-4784-8388-9999553b7e1d',
  'bb3793bd-fd79-423c-87f1-bfbcca614a3d',
  '7952953c-f5ab-48e0-9c10-0cde6861d3c9',
  'b854c225-3e3e-4c6a-8069-35be6ecca837',
  'cb7ba499-6b9f-4e4b-94bb-141dfeb7b376',
  '53dfcaac-9056-473b-84f5-0b5660a52424',
  '786b5f7c-7d10-49c9-a441-d5df9e476939',
  'bf2d0970-5f7c-41f4-bb4b-183b744c390f',
  'fdeb3b83-8d5e-4746-9f4f-d24f342a9539',
  'ee85dd31-f70e-416c-ad35-477a6dd9f6f7',
  'a2c14eb7-ea4b-4bd8-adf1-32dcbb33693b',
  '1d17fd3c-a650-45d0-bb9f-4129a65c524b',
  '581b153e-40a4-43c6-97a6-9160250ce762',
  '9795bbd0-c46f-4024-8df8-e7a22259c028',
  'e5812ca7-a247-4950-81d7-de5cf40cc3b1',
  'd3fd1ed7-4d4e-4ec4-b0cc-a4d852d5dfce',
  '0f3852dc-8fb8-4beb-8cf9-3ede7aad7184',
  '3c6094d4-0d49-4a2c-83d5-787b4daea25a',
  '162904da-bc8c-4fe4-ad93-123317f21bea',
  '63fde73b-8ef0-4373-8c5d-7176591fdf77',
  'b8a2f73b-5b90-494b-8f13-c6d4fed5fee8',
  '04364819-8d46-4e0a-a978-74c5d4d0660e',
  'c88aaffb-e69a-4965-b8a3-4fe97af86a05',
  '296d66b4-b254-4c8f-b801-1c64116b9eb8',
  'b227ba2c-6e5e-4993-b3fc-88e8e23dba25',
  '10654bd8-5303-4d0e-92fb-38dfb0f0a955',
  '9ec3b59d-0acc-430c-959e-c55c8be25e07',
  '5b8ceb89-de88-45c2-ac11-b89cea9b34de',
  'f65ce127-7c70-4a0a-84d2-772d8204ef2e',
  '8e9fe2cf-db88-41c6-b961-2faefd1f7fa7',
  '899ab07f-514b-4ca9-a339-b46f37a51c93',
  '01ca8627-327d-4b6e-bf94-3294e1ae6d92',
  '5ec5e3c3-3897-49b9-88d3-bbc62b22482b',
  '16de93fd-cdb4-4636-bbce-249feb28822b',
  '5964dc30-e544-4170-92cd-0525ebd02f10',
  '85cbce65-a6e4-480f-866a-b9ba0ba59a66',
  'bcba1df2-df47-4613-a3df-5398b48ea551',
  '482ce508-22ce-4f70-9053-246e19ed1b24',
  'f6239f11-f3c8-426b-8c26-3ede92598817',
  'e5bbbb98-6f3a-41f2-b8ac-9baf51519d6a',
  '119a04d2-1bd9-4126-a456-460bb05605ac',
  '750665ef-a7e3-44ad-afe3-e5c8e15c5a36',
  '16045be4-40ed-4e83-af65-742f13f356e0',
  'd79440a0-f28f-4a0a-9e50-39eba7e634ab',
  '5c4e05b2-db0d-46ca-97c9-1ed64eba9793',
  'd1dc2ac3-a0b4-4161-b6f8-625dd7be28e6',
  '8bbfabcd-eb84-4a88-a44f-612fd60462df',
  'cb8ddde1-9fd0-4dad-88de-70c2bedbd0ab',
  '2804552e-78aa-4aba-a420-64785bea9a90',
  '2570aedb-b7f9-43d8-a3f9-77fb384ca41f',
  'f633b0b1-aeae-46c3-8494-3bd8e63ce30d',
  'd080d1e8-f578-4866-9050-bf35c70fb020',
  '755d58e4-6a78-4687-94c8-ec9c8c86d5bf',
  '4012fe9e-6236-4126-8679-ab383567442e',
  '7c0ef02f-f349-4cdd-84c0-10df65259c7c',
  '187f668a-62e7-4de3-ae81-6ca9d4bd2443',
  '23c41ded-90eb-4c9d-ae03-6bfd5756964f',
  '261c910a-71ac-4a1b-991e-927fc7e22056',
  'f3afa087-3c90-4877-ba80-2aa40deb5668',
  '21872c2c-c017-40e8-bc25-8876d07e52e3',
  '9053fbb5-aabf-4e39-86fb-41f6a277f2b4',
  '333184bd-686f-4561-a5a1-ffb303131e8f',
  '88bf13e1-0760-4313-b42a-0f1f3c1f98f2',
  'bb178a40-ee6e-4e36-bd92-5e85997b37c5'
);

-- Verificação: deve retornar 71
SELECT count(*) AS inativadas_no_portal FROM public.revendas WHERE inativado_portal = true;

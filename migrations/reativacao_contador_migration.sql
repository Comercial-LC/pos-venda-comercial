-- ── Migração: contador de Reativação de revenda (30 dias) ──────────────
-- Execute no Supabase SQL Editor (apenas uma vez).
--
-- Fluxo:
--   1. No card da revenda, o botão "Iniciar reativação" grava a data de
--      início em revendas.reativacao_inicio.
--   2. Passados 30 dias sem ativar cliente, o Dashboard mostra um alerta
--      de "limite de ativação de cliente".
--   3. Quando a revenda ativa um cliente (histórico com tag CLIENTE_SUBIDO,
--      seja pelo card, lançamento em lote ou importação JSON), o trigger
--      abaixo encerra o contador automaticamente e a revenda volta ao
--      fluxo normal.
-- ─────────────────────────────────────────────────────────────────────

alter table public.revendas
  add column if not exists reativacao_inicio timestamptz;

-- Encerra o contador de reativação quando um cliente é ativado
create or replace function public.encerrar_reativacao_cliente_subido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.tag = 'CLIENTE_SUBIDO' then
    update public.revendas
       set reativacao_inicio = null,
           atualizado_em     = now()
     where id = new.revenda_id
       and reativacao_inicio is not null;

    -- Registra no histórico apenas se havia contador ativo
    if found then
      insert into public.historico_cards (revenda_id, tipo, descricao, manual, usuario_nome)
      values (new.revenda_id,
              '✅ Reativação concluída',
              'Cliente ativado — contador de reativação encerrado, revenda segue o fluxo normal',
              false,
              'Sistema');
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_encerrar_reativacao on public.historico_cards;
create trigger trg_encerrar_reativacao
  after insert on public.historico_cards
  for each row
  when (new.tag = 'CLIENTE_SUBIDO')
  execute function public.encerrar_reativacao_cliente_subido();

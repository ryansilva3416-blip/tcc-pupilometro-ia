-- Testes das regras do CRM e da segurança (RLS).
-- Rodar com: supabase/tests/rodar_testes.sh  (Postgres local)
\set ON_ERROR_STOP on
set client_min_messages = notice;
\o /dev/null

create or replace function pg_temp.verificar(cond boolean, msg text) returns void language plpgsql as $$
begin
  if not cond then raise exception 'FALHOU: %', msg; end if;
  raise notice 'ok: %', msg;
end $$;

-- Dados base
insert into auth.users values ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1');
insert into public.otica (id, nome) values
  ('10000000-0000-0000-0000-000000000001', 'Ótica A'),
  ('20000000-0000-0000-0000-000000000002', 'Ótica B');
insert into public.perfil (id, otica_id, nome, papel) values
  ('00000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-000000000001', 'Atendente A', 'admin'),
  ('00000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-000000000002', 'Atendente B', 'admin');

insert into public.cliente (id, otica_id, nome, email) values
  ('c0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Maria', 'maria@exemplo.com'),
  ('c0000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'João', 'joao@exemplo.com'),
  ('c0000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'Sem e-mail', null),
  ('c0000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002', 'Cliente B', 'b@exemplo.com');

-- 1) Com consentimento: exame agenda lembrete para +12 meses
insert into public.consentimento (cliente_id, tipo, concedido) values
  ('c0000000-0000-0000-0000-000000000001', 'lembrete_email', true);
insert into public.exame (id, otica_id, cliente_id, data_exame) values
  ('e0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
   'c0000000-0000-0000-0000-000000000001', '2025-11-20');
select pg_temp.verificar(
  (select data_prevista from public.lembrete where exame_id = 'e0000000-0000-0000-0000-000000000001') = '2026-11-20',
  'lembrete agendado para data do exame + 12 meses');

-- 2) Sem consentimento: nenhum lembrete
insert into public.exame (id, otica_id, cliente_id, data_exame) values
  ('e0000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
   'c0000000-0000-0000-0000-000000000002', '2025-11-10');
select pg_temp.verificar(
  not exists (select 1 from public.lembrete where cliente_id = 'c0000000-0000-0000-0000-000000000002'),
  'sem consentimento não agenda');

-- 3) Consentimento dado depois do exame agenda a partir do exame
insert into public.consentimento (cliente_id, tipo, concedido) values
  ('c0000000-0000-0000-0000-000000000002', 'lembrete_email', true);
select pg_temp.verificar(
  (select data_prevista from public.lembrete where cliente_id = 'c0000000-0000-0000-0000-000000000002') = '2026-11-10',
  'consentimento posterior agenda pelo exame mais recente');

-- 4) Sem e-mail: não agenda, mesmo com consentimento
insert into public.consentimento (cliente_id, tipo, concedido) values
  ('c0000000-0000-0000-0000-000000000003', 'lembrete_email', true);
insert into public.exame (otica_id, cliente_id, data_exame) values
  ('10000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', '2025-11-10');
select pg_temp.verificar(
  not exists (select 1 from public.lembrete where cliente_id = 'c0000000-0000-0000-0000-000000000003'),
  'cliente sem e-mail não recebe lembrete');

-- 5) Lembretes do dia: João (vence 10/11/2026) sim, Maria (20/11/2026) ainda não
select pg_temp.verificar(
  (select count(*) from public.lembretes_a_enviar('2026-11-10')) = 1
  and (select cliente_nome from public.lembretes_a_enviar('2026-11-10')) = 'João',
  'lembretes_a_enviar respeita a data');

-- 6) Exame novo cancela o lembrete pendente anterior e agenda o novo
insert into public.exame (id, otica_id, cliente_id, data_exame) values
  ('e0000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001',
   'c0000000-0000-0000-0000-000000000001', '2026-03-01');
select pg_temp.verificar(
  (select status from public.lembrete where exame_id = 'e0000000-0000-0000-0000-000000000001') = 'cancelado'
  and (select data_prevista from public.lembrete where exame_id = 'e0000000-0000-0000-0000-000000000003') = '2027-03-01',
  'exame novo reinicia o ciclo');

-- 7) Segundo lembrete: 15 dias após envio sem clique
update public.lembrete set status = 'entregue', enviado_em = '2026-11-10 12:00-03'
 where cliente_id = 'c0000000-0000-0000-0000-000000000002';
select pg_temp.verificar(public.agendar_segundos_lembretes('2026-11-24') = 0, 'antes de 15 dias não cria 2º lembrete');
select pg_temp.verificar(public.agendar_segundos_lembretes('2026-11-25') = 1, 'no 15º dia cria 2º lembrete');
select pg_temp.verificar(public.agendar_segundos_lembretes('2026-11-26') = 0, '2º lembrete não é duplicado');

-- 8) Quem clicou não recebe 2º lembrete
update public.lembrete set status = 'clicado', enviado_em = '2026-03-01 12:00-03'
 where exame_id = 'e0000000-0000-0000-0000-000000000003';
select pg_temp.verificar(public.agendar_segundos_lembretes('2027-12-31') = 0, 'quem clicou não recebe 2º lembrete');

-- 9) Descadastro pelo token cancela pendências e bloqueia envio
select pg_temp.verificar(
  public.descadastrar((select token_descadastro from public.cliente where id = 'c0000000-0000-0000-0000-000000000002')),
  'descadastro com token válido');
select pg_temp.verificar(
  not exists (select 1 from public.lembrete where cliente_id = 'c0000000-0000-0000-0000-000000000002' and status = 'agendado'),
  'descadastro cancela lembretes pendentes');
select pg_temp.verificar(not public.descadastrar(gen_random_uuid()), 'token inválido retorna false');
select pg_temp.verificar(
  (select count(*) from public.consentimento where cliente_id = 'c0000000-0000-0000-0000-000000000002') = 2,
  'consentimento mantém histórico');

-- 10) RLS: atendente da Ótica A não vê nem altera dados da Ótica B
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select pg_temp.verificar((select count(*) from public.cliente) = 3, 'RLS: Ótica A vê só os 3 clientes dela');
select pg_temp.verificar(
  not exists (select 1 from public.cliente where nome = 'Cliente B'), 'RLS: Ótica A não vê cliente da Ótica B');
do $$ begin
  begin
    insert into public.cliente (otica_id, nome) values ('20000000-0000-0000-0000-000000000002', 'Intruso');
    raise exception 'FALHOU: inseriu cliente em outra ótica';
  exception when insufficient_privilege then
    raise notice 'ok: RLS bloqueia inserir cliente em outra ótica';
  end;
end $$;
do $$ begin
  begin
    insert into public.exame (otica_id, cliente_id, data_exame)
    values ('10000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004', '2026-01-01');
    raise exception 'FALHOU: exame da ótica A para cliente da ótica B';
  exception when insufficient_privilege then
    raise notice 'ok: RLS bloqueia exame com cliente de outra ótica';
  end;
end $$;
do $$ begin
  begin
    perform public.lembretes_a_enviar(current_date);
    raise exception 'FALHOU: atendente executou função da rotina';
  exception when insufficient_privilege then
    raise notice 'ok: atendente não executa funções da rotina diária';
  end;
end $$;
select pg_temp.verificar(
  (select count(*) from public.lembrete) = (select count(*) from public.lembrete l where l.otica_id = '10000000-0000-0000-0000-000000000001'),
  'RLS: lembretes só da própria ótica');
reset role;

\o
\echo 'TODOS OS TESTES PASSARAM'

-- Modelo de dados inicial da plataforma (TCC Pupilômetro IA)
-- Óticas, equipe, clientes, consentimentos, exames, medições, atendimentos e lembretes do CRM.
--
-- Regras do CRM implementadas no banco (para não depender do app):
--  * Ao cadastrar um exame, se o cliente autorizou lembretes e tem e-mail, agenda um lembrete
--    para data_exame + intervalo da ótica (padrão 12 meses).
--  * Um exame novo cancela os lembretes ainda pendentes dos exames anteriores do mesmo cliente.
--  * Revogar o consentimento (ou descadastrar pelo link do e-mail) cancela os lembretes pendentes.
--  * Segundo lembrete: N dias (padrão 15) após o primeiro, se o cliente não clicou.

-- ---------------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------------

create table public.otica (
  id                     uuid primary key default gen_random_uuid(),
  nome                   text not null,
  email_contato          text,
  telefone               text,
  endereco               text,
  intervalo_lembrete_meses smallint not null default 12 check (intervalo_lembrete_meses between 1 and 36),
  dias_segundo_lembrete  smallint not null default 15 check (dias_segundo_lembrete between 1 and 90),
  criado_em              timestamptz not null default now()
);

create table public.perfil (
  id         uuid primary key references auth.users (id) on delete cascade,
  otica_id   uuid not null references public.otica (id) on delete cascade,
  nome       text not null,
  papel      text not null default 'atendente' check (papel in ('admin', 'atendente')),
  criado_em  timestamptz not null default now()
);

create table public.cliente (
  id                 uuid primary key default gen_random_uuid(),
  otica_id           uuid not null references public.otica (id) on delete cascade,
  nome               text not null,
  email              text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  telefone           text,
  token_descadastro  uuid not null unique default gen_random_uuid(),
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);
create index on public.cliente (otica_id);

create table public.consentimento (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.cliente (id) on delete cascade,
  tipo          text not null check (tipo in ('lembrete_email', 'pesquisa')),
  concedido     boolean not null,
  origem        text not null default 'app' check (origem in ('app', 'link_email', 'sistema')),
  registrado_em timestamptz not null default now(),
  registrado_por uuid references auth.users (id)
);
-- Histórico completo: o consentimento vigente é o registro mais recente de cada tipo.
create index on public.consentimento (cliente_id, tipo, registrado_em desc);

create table public.exame (
  id             uuid primary key default gen_random_uuid(),
  otica_id       uuid not null references public.otica (id) on delete cascade,
  cliente_id     uuid not null references public.cliente (id) on delete cascade,
  data_exame     date not null,
  profissional   text,
  arquivo_path   text,          -- caminho no Storage privado (bucket "exames")
  criado_por     uuid references auth.users (id),
  criado_em      timestamptz not null default now()
);
create index on public.exame (cliente_id, data_exame desc);

create table public.medicao (
  id                   uuid primary key default gen_random_uuid(),
  otica_id             uuid not null references public.otica (id) on delete cascade,
  cliente_id           uuid references public.cliente (id) on delete set null,
  codigo_participante  text,    -- experimento: identificação por código, sem nome
  dp_app_mm            numeric(5, 2),
  dp_iris_mm           numeric(5, 2),
  dp_pupilometro_mm    numeric(5, 2),
  aprovada             boolean not null,
  avisos               text[] not null default '{}',
  versao_algoritmo     text not null,
  dados                jsonb not null default '{}'::jsonb,  -- métricas brutas da análise
  criado_por           uuid references auth.users (id),
  criado_em            timestamptz not null default now(),
  check (cliente_id is not null or codigo_participante is not null)
);

create table public.atendimento (
  id                      uuid primary key default gen_random_uuid(),
  otica_id                uuid not null references public.otica (id) on delete cascade,
  cliente_id              uuid not null references public.cliente (id) on delete cascade,
  exame_id                uuid references public.exame (id) on delete set null,
  medicao_id              uuid references public.medicao (id) on delete set null,
  tratamentos_simulados   text[] not null default '{}',
  tratamentos_escolhidos  text[] not null default '{}',
  atendente_id            uuid references auth.users (id),
  criado_em               timestamptz not null default now()
);

create table public.lembrete (
  id                   uuid primary key default gen_random_uuid(),
  otica_id             uuid not null references public.otica (id) on delete cascade,
  cliente_id           uuid not null references public.cliente (id) on delete cascade,
  exame_id             uuid not null references public.exame (id) on delete cascade,
  tentativa            smallint not null default 1 check (tentativa in (1, 2)),
  data_prevista        date not null,
  status               text not null default 'agendado'
                       check (status in ('agendado', 'enviado', 'entregue', 'aberto', 'clicado',
                                         'falhou', 'cancelado')),
  enviado_em           timestamptz,
  id_mensagem_provedor text,
  erro                 text,
  atualizado_em        timestamptz not null default now(),
  criado_em            timestamptz not null default now(),
  unique (exame_id, tentativa)
);
create index on public.lembrete (status, data_prevista);

-- ---------------------------------------------------------------------------
-- Funções auxiliares
-- ---------------------------------------------------------------------------

create or replace function public.otica_do_usuario()
returns uuid language sql stable security definer set search_path = public as $$
  select otica_id from public.perfil where id = auth.uid()
$$;

create or replace function public.consentimento_vigente(p_cliente uuid, p_tipo text)
returns boolean language sql stable set search_path = public as $$
  select coalesce((
    select concedido from public.consentimento
     where cliente_id = p_cliente and tipo = p_tipo
     order by registrado_em desc, id desc
     limit 1), false)
$$;

-- ---------------------------------------------------------------------------
-- Gatilhos do CRM
-- ---------------------------------------------------------------------------

create or replace function public.tg_exame_agendar_lembrete()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_meses smallint;
  v_email text;
begin
  -- Exame novo reinicia o ciclo: cancela pendências de exames anteriores.
  update public.lembrete
     set status = 'cancelado', erro = 'substituído por exame mais recente', atualizado_em = now()
   where cliente_id = new.cliente_id and exame_id <> new.id and status = 'agendado';

  select c.email, o.intervalo_lembrete_meses into v_email, v_meses
    from public.cliente c join public.otica o on o.id = c.otica_id
   where c.id = new.cliente_id;

  if v_email is not null and public.consentimento_vigente(new.cliente_id, 'lembrete_email') then
    insert into public.lembrete (otica_id, cliente_id, exame_id, tentativa, data_prevista)
    values (new.otica_id, new.cliente_id, new.id, 1,
            (new.data_exame + make_interval(months => v_meses))::date)
    on conflict (exame_id, tentativa) do nothing;
  end if;
  return new;
end $$;

create trigger exame_agendar_lembrete
after insert on public.exame
for each row execute function public.tg_exame_agendar_lembrete();

create or replace function public.tg_consentimento_lembrete()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_exame record;
begin
  if new.tipo <> 'lembrete_email' then
    return new;
  end if;

  if not new.concedido then
    update public.lembrete
       set status = 'cancelado', erro = 'consentimento revogado', atualizado_em = now()
     where cliente_id = new.cliente_id and status = 'agendado';
  else
    -- Consentimento dado depois do exame: agenda a partir do exame mais recente.
    select e.* into v_exame from public.exame e
     where e.cliente_id = new.cliente_id order by e.data_exame desc, e.criado_em desc limit 1;
    if found and exists (select 1 from public.cliente where id = new.cliente_id and email is not null) then
      insert into public.lembrete (otica_id, cliente_id, exame_id, tentativa, data_prevista)
      select v_exame.otica_id, v_exame.cliente_id, v_exame.id, 1,
             (v_exame.data_exame + make_interval(months => o.intervalo_lembrete_meses))::date
        from public.otica o where o.id = v_exame.otica_id
      on conflict (exame_id, tentativa) do nothing;
    end if;
  end if;
  return new;
end $$;

create trigger consentimento_lembrete
after insert on public.consentimento
for each row execute function public.tg_consentimento_lembrete();

create or replace function public.tg_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  return new;
end $$;

create trigger cliente_atualizado_em before update on public.cliente
for each row execute function public.tg_atualizado_em();
create trigger lembrete_atualizado_em before update on public.lembrete
for each row execute function public.tg_atualizado_em();

-- ---------------------------------------------------------------------------
-- Funções chamadas pela rotina diária (Edge Function com service_role)
-- ---------------------------------------------------------------------------

-- Cria os segundos lembretes devidos na data informada. Retorna quantos foram criados.
create or replace function public.agendar_segundos_lembretes(p_data date default current_date)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_qtd integer;
begin
  insert into public.lembrete (otica_id, cliente_id, exame_id, tentativa, data_prevista)
  select l.otica_id, l.cliente_id, l.exame_id, 2, p_data
    from public.lembrete l
    join public.otica o on o.id = l.otica_id
    join public.cliente c on c.id = l.cliente_id
   where l.tentativa = 1
     and l.status in ('enviado', 'entregue', 'aberto')       -- não clicou
     and l.enviado_em is not null
     and l.enviado_em::date + o.dias_segundo_lembrete <= p_data
     and c.email is not null
     and public.consentimento_vigente(l.cliente_id, 'lembrete_email')
     -- só para o ciclo vigente (nenhum exame mais novo)
     and not exists (select 1 from public.exame e2
                      where e2.cliente_id = l.cliente_id
                        and e2.data_exame > (select data_exame from public.exame where id = l.exame_id))
  on conflict (exame_id, tentativa) do nothing;
  get diagnostics v_qtd = row_count;
  return v_qtd;
end $$;

-- Lembretes a enviar hoje, com os dados necessários para montar o e-mail.
create or replace function public.lembretes_a_enviar(p_data date default current_date)
returns table (
  lembrete_id uuid, tentativa smallint, cliente_nome text, cliente_email text,
  token_descadastro uuid, otica_nome text, otica_telefone text, data_exame date
) language sql stable security definer set search_path = public as $$
  select l.id, l.tentativa, c.nome, c.email, c.token_descadastro, o.nome, o.telefone, e.data_exame
    from public.lembrete l
    join public.cliente c on c.id = l.cliente_id
    join public.otica o on o.id = l.otica_id
    join public.exame e on e.id = l.exame_id
   where l.status = 'agendado'
     and l.data_prevista <= p_data
     and c.email is not null
     and public.consentimento_vigente(l.cliente_id, 'lembrete_email')
   order by l.data_prevista, l.id
$$;

-- Descadastro pelo link do e-mail (sem login). Retorna true se o token existia.
create or replace function public.descadastrar(p_token uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid;
begin
  select id into v_cliente from public.cliente where token_descadastro = p_token;
  if v_cliente is null then
    return false;
  end if;
  insert into public.consentimento (cliente_id, tipo, concedido, origem)
  values (v_cliente, 'lembrete_email', false, 'link_email');
  return true;
end $$;

-- ---------------------------------------------------------------------------
-- Segurança (RLS): cada usuário só enxerga os dados da própria ótica.
-- ---------------------------------------------------------------------------

alter table public.otica          enable row level security;
alter table public.perfil         enable row level security;
alter table public.cliente        enable row level security;
alter table public.consentimento  enable row level security;
alter table public.exame          enable row level security;
alter table public.medicao        enable row level security;
alter table public.atendimento    enable row level security;
alter table public.lembrete       enable row level security;

create policy otica_leitura on public.otica for select to authenticated
  using (id = public.otica_do_usuario());
create policy otica_admin on public.otica for update to authenticated
  using (id = public.otica_do_usuario()
         and exists (select 1 from public.perfil where id = auth.uid() and papel = 'admin'));

create policy perfil_leitura on public.perfil for select to authenticated
  using (otica_id = public.otica_do_usuario());

create policy cliente_tudo on public.cliente for all to authenticated
  using (otica_id = public.otica_do_usuario())
  with check (otica_id = public.otica_do_usuario());

create policy consentimento_leitura on public.consentimento for select to authenticated
  using (exists (select 1 from public.cliente c where c.id = cliente_id and c.otica_id = public.otica_do_usuario()));
-- Consentimento é histórico: pode inserir, não pode alterar nem apagar.
create policy consentimento_insercao on public.consentimento for insert to authenticated
  with check (exists (select 1 from public.cliente c where c.id = cliente_id and c.otica_id = public.otica_do_usuario()));

create policy exame_tudo on public.exame for all to authenticated
  using (otica_id = public.otica_do_usuario())
  with check (otica_id = public.otica_do_usuario()
              and exists (select 1 from public.cliente c
                           where c.id = exame.cliente_id and c.otica_id = exame.otica_id));

create policy medicao_tudo on public.medicao for all to authenticated
  using (otica_id = public.otica_do_usuario())
  with check (otica_id = public.otica_do_usuario());

create policy atendimento_tudo on public.atendimento for all to authenticated
  using (otica_id = public.otica_do_usuario())
  with check (otica_id = public.otica_do_usuario());

-- Lembretes: equipe só lê; quem cria/atualiza são os gatilhos e a rotina diária.
create policy lembrete_leitura on public.lembrete for select to authenticated
  using (otica_id = public.otica_do_usuario());

revoke all on function public.agendar_segundos_lembretes(date) from public, anon, authenticated;
revoke all on function public.lembretes_a_enviar(date) from public, anon, authenticated;
revoke all on function public.descadastrar(uuid) from public, anon, authenticated;
grant execute on function public.agendar_segundos_lembretes(date) to service_role;
grant execute on function public.lembretes_a_enviar(date) to service_role;
grant execute on function public.descadastrar(uuid) to service_role;

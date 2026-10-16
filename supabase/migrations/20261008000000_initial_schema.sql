-- =====================================================================
-- PORTFY · Esquema do banco de dados (Supabase / PostgreSQL)
--
-- COMO USAR
--   1. Supabase Dashboard > SQL Editor > New query
--   2. Cole este arquivo inteiro e clique em Run
--   3. O script é idempotente: pode ser executado de novo sem erro.
--
-- MAPA EM RELAÇÃO AO DOCUMENTO DE ARQUITETURA (seção 12)
--   Usuário  -> auth.users (gerenciada pelo Supabase) + public.perfis
--   Perfil   -> public.perfis
--   Configuração -> public.configuracoes_usuario
--   Agente_IA -> ia_conversas, ia_mensagens, ia_uso_diario
--   Evento / Calendário -> public.eventos (o calendário é uma visão dos eventos)
--   Nota     -> public.notas
--   Plano de Pagamento -> planos, assinaturas, pagamentos
--   Publicação / Projeto / Templates -> documentos, projetos, modelos
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. TIPOS
-- ---------------------------------------------------------------------
do $$ begin create type public.tipo_documento   as enum ('curriculo', 'portfolio', 'projeto');            exception when duplicate_object then null; end $$;
do $$ begin create type public.status_assinatura as enum ('ativo', 'cancelado', 'atrasado');              exception when duplicate_object then null; end $$;
do $$ begin create type public.status_pagamento  as enum ('pendente', 'pago', 'falhou', 'reembolsado');    exception when duplicate_object then null; end $$;
do $$ begin create type public.papel_ia          as enum ('usuario', 'assistente');                        exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 2. PLANOS E ASSINATURAS (Planos A, B e C do documento)
-- ---------------------------------------------------------------------
create table if not exists public.planos (
  codigo           text primary key,                    -- 'A', 'B', 'C'
  nome             text    not null,
  preco_centavos   integer not null default 0 check (preco_centavos >= 0),
  limite_diario_ia integer not null default 10 check (limite_diario_ia >= 0),
  recursos         jsonb   not null default '[]'::jsonb,
  criado_em        timestamptz not null default now()
);

insert into public.planos (codigo, nome, preco_centavos, limite_diario_ia, recursos) values
  ('A', 'Gratuito', 0,    10,  '["Modelos gratuitos","Agenda e tarefas","Notas e projetos"]'),
  ('B', 'Pro',      2900, 100, '["Tudo do plano Gratuito","Modelos Pro","Agente de IA ampliado"]'),
  ('C', 'Premium',  5900, 500, '["Tudo do plano Pro","Suporte prioritário","Exportação sem marca"]')
on conflict (codigo) do update
  set nome = excluded.nome, preco_centavos = excluded.preco_centavos,
      limite_diario_ia = excluded.limite_diario_ia, recursos = excluded.recursos;

-- ---------------------------------------------------------------------
-- 3. PERFIL, CONFIGURAÇÕES E DIAGNÓSTICO (1 linha por usuário)
-- ---------------------------------------------------------------------
create table if not exists public.perfis (
  id               uuid primary key references auth.users (id) on delete cascade,
  nome_completo    text not null default '',
  email            text,
  url_avatar       text,
  profissao        text,
  telefone         text,
  url_portfolio    text,
  biografia        text check (char_length(biografia) <= 500),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);

create table if not exists public.configuracoes_usuario (
  usuario_id           uuid primary key references auth.users (id) on delete cascade,
  tema                 text not null default 'system' check (tema in ('system', 'light', 'dark')),
  idioma               text not null default 'pt-BR'  check (idioma in ('pt-BR', 'en', 'es')),
  privacidade          text not null default 'public' check (privacidade in ('public', 'link', 'private')),
  notificacoes_email   boolean not null default true,
  autenticacao_dois_fatores boolean not null default false,   -- espelho informativo; o MFA real fica em auth.mfa
  atualizado_em        timestamptz not null default now()
);

create table if not exists public.diagnosticos (
  usuario_id      uuid primary key references auth.users (id) on delete cascade,
  horas_estudo    text,
  fase_academica  text,
  mercado_alvo    text,
  criado_em       timestamptz not null default now()
);

create table if not exists public.assinaturas (
  id                   uuid primary key default gen_random_uuid(),
  usuario_id           uuid not null unique references auth.users (id) on delete cascade,
  codigo_plano         text not null default 'A' references public.planos (codigo),
  status               public.status_assinatura not null default 'ativo',
  fim_periodo_atual    timestamptz,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);

create table if not exists public.pagamentos (
  id               uuid primary key default gen_random_uuid(),
  usuario_id       uuid not null references auth.users (id) on delete cascade,
  assinatura_id    uuid references public.assinaturas (id) on delete set null,
  codigo_plano     text not null references public.planos (codigo),
  valor_centavos   integer not null check (valor_centavos >= 0),
  moeda            text not null default 'BRL',
  status           public.status_pagamento not null default 'pendente',
  provedor         text,                 -- 'stripe', 'mercadopago'...
  ref_provedor     text,                 -- id da cobrança no provedor
  criado_em        timestamptz not null default now()
);
create index if not exists pagamentos_usuario_idx on public.pagamentos (usuario_id, criado_em desc);

-- ---------------------------------------------------------------------
-- 4. MODELOS (templates gratuitos e pagos)
--    O layout visual é gerado pelo front-end a partir de tipo + destaque.
--    O campo layout (jsonb) fica livre para modelos personalizados no futuro.
-- ---------------------------------------------------------------------
create table if not exists public.modelos (
  id           uuid primary key default gen_random_uuid(),
  identificador text not null unique,
  nome         text not null,
  descricao    text,
  categoria    text not null check (categoria in ('curriculo', 'portfolio', 'linkedin', 'projeto')),
  tipo         public.tipo_documento not null,
  plano_minimo text not null default 'A' references public.planos (codigo),   -- 'A' = gratuito
  destaque     text not null default '#0A1A3F',
  layout       jsonb,
  esta_ativo   boolean not null default true,
  ordem        integer not null default 0
);

insert into public.modelos (identificador, nome, descricao, categoria, tipo, plano_minimo, destaque, ordem) values
  ('curriculo-profissional', 'Currículo Profissional', 'Limpo e objetivo para o mercado tradicional',   'curriculo', 'curriculo', 'A', '#0A1A3F', 1),
  ('portfolio-criativo',     'Portfólio Criativo',     'Destaque seus projetos com visual impactante',  'portfolio', 'portfolio', 'A', '#2F5BEA', 2),
  ('perfil-linkedin',        'Perfil LinkedIn',        'Otimize seu perfil para recrutadores',          'linkedin',  'portfolio', 'A', '#1F44C9', 3),
  ('case-de-projeto',        'Case de Projeto',        'Documente um projeto de ponta a ponta',         'projeto',   'projeto',   'B', '#0A1A3F', 4),
  ('curriculo-moderno',      'Currículo Moderno',      'Design contemporâneo para áreas criativas',     'curriculo', 'curriculo', 'B', '#3A5BD9', 5),
  ('portfolio-tech',         'Portfólio Tech',         'Ideal para desenvolvedores e engenheiros',      'portfolio', 'portfolio', 'B', '#101B3D', 6)
on conflict (identificador) do update
  set nome = excluded.nome, descricao = excluded.descricao, categoria = excluded.categoria,
      tipo = excluded.tipo, plano_minimo = excluded.plano_minimo, destaque = excluded.destaque, ordem = excluded.ordem;

-- ---------------------------------------------------------------------
-- 5. ARQUIVOS DO EDITOR (currículos, portfólios e cases de projeto)
--    elementos = lista de elementos do canvas: texto, formas e imagens.
--    Imagens ficam no Storage; aqui só guardamos a URL.
-- ---------------------------------------------------------------------
create table if not exists public.documentos (
  id            uuid primary key default gen_random_uuid(),
  usuario_id    uuid not null references auth.users (id) on delete cascade,
  tipo          public.tipo_documento not null,
  titulo        text not null default 'Sem título' check (char_length(titulo) between 1 and 120),
  largura       integer not null default 1280 check (largura between 200 and 4000),
  altura        integer not null default 720  check (altura between 200 and 4000),
  cor_fundo     text not null default '#ffffff',
  elementos     jsonb not null default '[]'::jsonb check (jsonb_typeof(elementos) = 'array'),
  modelo_id     uuid references public.modelos (id) on delete set null,
  url_capa      text,
  esta_publicado boolean not null default false,
  identificador text unique check (identificador ~ '^[a-z0-9][a-z0-9-]{2,60}$'),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists documentos_usuario_idx on public.documentos (usuario_id, atualizado_em desc);

-- ---------------------------------------------------------------------
-- 6. PRODUTIVIDADE: projetos, tarefas, eventos e notas
-- ---------------------------------------------------------------------
create table if not exists public.projetos (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references auth.users (id) on delete cascade,
  titulo       text not null check (char_length(titulo) between 1 and 120),
  descricao    text,
  progresso    integer not null default 0 check (progresso between 0 and 100),
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists projetos_usuario_idx on public.projetos (usuario_id, criado_em desc);

create table if not exists public.tarefas (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references auth.users (id) on delete cascade,
  titulo       text not null check (char_length(titulo) between 1 and 200),
  data_vencimento date not null default current_date,
  concluida    boolean not null default false,
  concluida_em timestamptz,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists tarefas_usuario_idx on public.tarefas (usuario_id, concluida, data_vencimento);

create table if not exists public.eventos (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references auth.users (id) on delete cascade,
  titulo       text not null check (char_length(titulo) between 1 and 200),
  data_evento  date not null,
  hora_evento  time not null default '09:00',
  descricao    text,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists eventos_usuario_idx on public.eventos (usuario_id, data_evento);

create table if not exists public.notas (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references auth.users (id) on delete cascade,
  titulo       text not null check (char_length(titulo) between 1 and 200),
  conteudo     text not null default '' check (char_length(conteudo) <= 20000),
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists notas_usuario_idx on public.notas (usuario_id, atualizado_em desc);

create table if not exists public.registro_atividades (
  id           bigint generated always as identity primary key,
  usuario_id   uuid not null references auth.users (id) on delete cascade,
  mensagem     text not null check (char_length(mensagem) <= 300),
  criado_em    timestamptz not null default now()
);
create index if not exists atividades_usuario_idx on public.registro_atividades (usuario_id, criado_em desc);

-- ---------------------------------------------------------------------
-- 7. AGENTE DE IA
--    Mensagens e uso são gravados SOMENTE pela Edge Function (service role).
--    O cliente só lê. Assim ninguém burla a cota apagando ou forjando linhas.
-- ---------------------------------------------------------------------
create table if not exists public.ia_conversas (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references auth.users (id) on delete cascade,
  titulo       text not null default 'Nova conversa',
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists ia_conv_usuario_idx on public.ia_conversas (usuario_id, atualizado_em desc);

create table if not exists public.ia_mensagens (
  id               uuid primary key default gen_random_uuid(),
  conversa_id      uuid not null references public.ia_conversas (id) on delete cascade,
  usuario_id       uuid not null references auth.users (id) on delete cascade,
  papel            public.papel_ia not null,
  conteudo         text not null check (char_length(conteudo) <= 8000),
  tokens_entrada   integer,
  tokens_saida     integer,
  criado_em        timestamptz not null default now()
);
create index if not exists ia_msg_conv_idx on public.ia_mensagens (conversa_id, criado_em);

create table if not exists public.ia_uso_diario (
  usuario_id  uuid not null references auth.users (id) on delete cascade,
  dia         date not null,
  mensagens   integer not null default 0,
  tokens      bigint  not null default 0,
  primary key (usuario_id, dia)
);

-- ---------------------------------------------------------------------
-- 8. FUNÇÕES E GATILHOS
-- ---------------------------------------------------------------------

-- 8.1 Mantém atualizado_em sempre correto
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.atualizado_em = now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['perfis','configuracoes_usuario','assinaturas','documentos','projetos','tarefas','eventos','notas','ia_conversas']
  loop
    execute format('drop trigger if exists trg_touch on public.%I', t);
    execute format('create trigger trg_touch before update on public.%I for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

-- 8.2 Preenche concluida_em ao concluir uma tarefa
create or replace function public.set_task_done_at()
returns trigger language plpgsql as $$
begin
  if new.concluida and not coalesce(old.concluida, false) then new.concluida_em = now();
  elsif not new.concluida then new.concluida_em = null;
  end if;
  return new;
end $$;
drop trigger if exists trg_task_done on public.tarefas;
create trigger trg_task_done before update on public.tarefas for each row execute function public.set_task_done_at();

-- 8.3 Ao criar a conta no Supabase Auth, cria perfil, configurações e plano gratuito
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis (id, nome_completo, email)
    values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), new.email)
    on conflict (id) do nothing;
  insert into public.configuracoes_usuario (usuario_id) values (new.id) on conflict do nothing;
  insert into public.assinaturas (usuario_id, codigo_plano) values (new.id, 'A') on conflict do nothing;
  insert into public.registro_atividades (usuario_id, mensagem) values (new.id, 'Conta criada no Portfy');
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 8.4 Cota diária da IA conforme o plano do usuário (fuso de Brasília)
create or replace function public.ai_quota()
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'used',  coalesce((select u.mensagens from public.ia_uso_diario u
                       where u.usuario_id = auth.uid()
                         and u.dia = (now() at time zone 'America/Sao_Paulo')::date), 0),
    'limit', coalesce((select p.limite_diario_ia from public.assinaturas s
                       join public.planos p on p.codigo = s.codigo_plano
                       where s.usuario_id = auth.uid() and s.status = 'ativo'), 10)
  );
$$;

-- 8.5 Registra o uso da IA (chamada só pelo servidor)
create or replace function public.ai_register_usage(p_user uuid, p_tokens integer)
returns void language sql security definer set search_path = public as $$
  insert into public.ia_uso_diario (usuario_id, dia, mensagens, tokens)
  values (p_user, (now() at time zone 'America/Sao_Paulo')::date, 1, greatest(p_tokens, 0))
  on conflict (usuario_id, dia) do update
    set mensagens = public.ia_uso_diario.mensagens + 1,
        tokens    = public.ia_uso_diario.tokens + greatest(p_tokens, 0);
$$;
revoke all on function public.ai_register_usage(uuid, integer) from public, anon, authenticated;
grant execute on function public.ai_register_usage(uuid, integer) to service_role;

-- 8.6 Números do dashboard em uma só chamada
create or replace function public.dashboard_stats()
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'projects_in_progress', (select count(*) from public.projetos  where usuario_id = auth.uid() and progresso < 100),
    'published_portfolios', (select count(*) from public.documentos where usuario_id = auth.uid() and tipo = 'portfolio'),
    'tasks_due',            (select count(*) from public.tarefas   where usuario_id = auth.uid() and not concluida and data_vencimento <= current_date),
    'achievements',
        (exists (select 1 from public.tarefas     where usuario_id = auth.uid() and concluida))::int
      + (exists (select 1 from public.documentos  where usuario_id = auth.uid()))::int
      + (exists (select 1 from public.notas       where usuario_id = auth.uid()))::int
      + (exists (select 1 from public.projetos    where usuario_id = auth.uid()))::int
      + (exists (select 1 from public.eventos     where usuario_id = auth.uid()))::int
      + (exists (select 1 from public.perfis      where id = auth.uid() and coalesce(biografia, '') <> ''))::int
      + (exists (select 1 from public.assinaturas where usuario_id = auth.uid() and codigo_plano <> 'A'))::int
      + (exists (select 1 from public.diagnosticos where usuario_id = auth.uid()))::int
  );
$$;

-- ---------------------------------------------------------------------
-- 9. SEGURANÇA: ROW LEVEL SECURITY (cada usuário só enxerga o que é dele)
-- ---------------------------------------------------------------------

-- 9.1 Tabelas em que o usuário tem controle total sobre as próprias linhas
do $$
declare t text;
begin
  foreach t in array array['tarefas','eventos','notas','projetos','documentos']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists owner_all on public.%I', t);
    execute format($p$create policy owner_all on public.%I for all to authenticated
                      using (usuario_id = (select auth.uid()))
                      with check (usuario_id = (select auth.uid()))$p$, t);
  end loop;
end $$;

-- 9.2 Perfil: lê e edita o próprio (a criação é feita pelo gatilho)
alter table public.perfis enable row level security;
drop policy if exists own_select on public.perfis;
drop policy if exists own_update on public.perfis;
create policy own_select on public.perfis for select to authenticated using (id = (select auth.uid()));
create policy own_update on public.perfis for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- 9.3 Configurações e diagnóstico
alter table public.configuracoes_usuario enable row level security;
drop policy if exists owner_all on public.configuracoes_usuario;
create policy owner_all on public.configuracoes_usuario for all to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));

alter table public.diagnosticos enable row level security;
drop policy if exists owner_all on public.diagnosticos;
create policy owner_all on public.diagnosticos for all to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));

-- 9.4 Histórico de atividades: o usuário lê e cria o próprio
alter table public.registro_atividades enable row level security;
drop policy if exists own_select on public.registro_atividades;
drop policy if exists own_insert on public.registro_atividades;
create policy own_select on public.registro_atividades for select to authenticated using (usuario_id = (select auth.uid()));
create policy own_insert on public.registro_atividades for insert to authenticated with check (usuario_id = (select auth.uid()));

-- 9.5 Planos e modelos: catálogo público (somente leitura)
alter table public.planos enable row level security;
drop policy if exists catalog_read on public.planos;
create policy catalog_read on public.planos for select to anon, authenticated using (true);

alter table public.modelos enable row level security;
drop policy if exists catalog_read on public.modelos;
create policy catalog_read on public.modelos for select to anon, authenticated using (esta_ativo);

-- 9.6 Assinaturas, pagamentos, IA: o usuário só LÊ. Escrita apenas pelo servidor (service role).
do $$
declare t text;
begin
  foreach t in array array['assinaturas','pagamentos','ia_uso_diario']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists own_select on public.%I', t);
    execute format('create policy own_select on public.%I for select to authenticated using (usuario_id = (select auth.uid()))', t);
  end loop;
end $$;

alter table public.ia_conversas enable row level security;
drop policy if exists own_select on public.ia_conversas;
drop policy if exists own_delete on public.ia_conversas;
create policy own_select on public.ia_conversas for select to authenticated using (usuario_id = (select auth.uid()));
create policy own_delete on public.ia_conversas for delete to authenticated using (usuario_id = (select auth.uid()));

alter table public.ia_mensagens enable row level security;
drop policy if exists own_select on public.ia_mensagens;
create policy own_select on public.ia_mensagens for select to authenticated using (usuario_id = (select auth.uid()));

-- 9.7 Arquivos publicados podem ser vistos por qualquer visitante (página pública do portfólio)
drop policy if exists published_read on public.documentos;
create policy published_read on public.documentos for select to anon, authenticated using (esta_publicado);

-- ---------------------------------------------------------------------
-- 10. PERMISSÕES DA API (o RLS acima continua valendo sobre elas)
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select on public.planos, public.modelos to anon, authenticated;
grant select on public.documentos to anon;
grant select, insert, update, delete on
  public.tarefas, public.eventos, public.notas, public.projetos, public.documentos,
  public.configuracoes_usuario, public.diagnosticos to authenticated;
grant select, update on public.perfis to authenticated;
grant select, insert on public.registro_atividades to authenticated;
grant select on public.assinaturas, public.pagamentos, public.ia_uso_diario, public.ia_mensagens to authenticated;
grant select, delete on public.ia_conversas to authenticated;
grant execute on function public.ai_quota(), public.dashboard_stats() to authenticated;

-- ---------------------------------------------------------------------
-- 11. STORAGE: fotos de perfil e imagens usadas nos arquivos do editor
--     Convenção de caminho: <id-do-usuário>/<nome-do-arquivo>
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',    'avatars',    true, 2097152, array['image/png', 'image/jpeg', 'image/webp']),
  ('doc-images', 'doc-images', true, 5242880, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

do $$
declare b text;
begin
  foreach b in array array['avatars', 'doc-images']
  loop
    execute format('drop policy if exists "%s_read"   on storage.objects', b);
    execute format('drop policy if exists "%s_insert" on storage.objects', b);
    execute format('drop policy if exists "%s_update" on storage.objects', b);
    execute format('drop policy if exists "%s_delete" on storage.objects', b);
    execute format($p$create policy "%s_read" on storage.objects for select using (bucket_id = %L)$p$, b, b);
    execute format($p$create policy "%s_insert" on storage.objects for insert to authenticated
                      with check (bucket_id = %L and (storage.foldername(name))[1] = (select auth.uid())::text)$p$, b, b);
    execute format($p$create policy "%s_update" on storage.objects for update to authenticated
                      using (bucket_id = %L and (storage.foldername(name))[1] = (select auth.uid())::text)$p$, b, b);
    execute format($p$create policy "%s_delete" on storage.objects for delete to authenticated
                      using (bucket_id = %L and (storage.foldername(name))[1] = (select auth.uid())::text)$p$, b, b);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 12. (OPCIONAL, SÓ PARA TESTES) trocar de plano sem pagamento
--     Rode no SQL Editor, trocando o e-mail. Em produção o plano só muda
--     pelo webhook de pagamento (service role).
-- ---------------------------------------------------------------------
-- update public.assinaturas set codigo_plano = 'B'
--   where usuario_id = (select id from auth.users where email = 'voce@exemplo.com');

-- ---------------------------------------------------------------------
-- 13. CORREÇÕES (seguro rodar de novo)
--     13.1 usuario_id passa a ser preenchido sozinho com o usuário logado
--     13.2 ensure_user_rows(): cria perfil, configurações e plano que faltarem
--          (contas criadas à mão no painel ou antes do gatilho existir)
-- ---------------------------------------------------------------------
alter table public.tarefas            alter column usuario_id set default auth.uid();
alter table public.eventos           alter column usuario_id set default auth.uid();
alter table public.notas             alter column usuario_id set default auth.uid();
alter table public.projetos          alter column usuario_id set default auth.uid();
alter table public.documentos        alter column usuario_id set default auth.uid();
alter table public.registro_atividades alter column usuario_id set default auth.uid();

create or replace function public.ensure_user_rows()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  u record;
begin
  if uid is null then return; end if;
  select id, email, raw_user_meta_data into u from auth.users where id = uid;
  insert into public.perfis (id, nome_completo, email)
    values (uid, coalesce(u.raw_user_meta_data ->> 'full_name', ''), u.email)
    on conflict (id) do nothing;
  insert into public.configuracoes_usuario (usuario_id) values (uid) on conflict do nothing;
  insert into public.assinaturas (usuario_id, codigo_plano) values (uid, 'A') on conflict do nothing;
end $$;
revoke all on function public.ensure_user_rows() from public, anon;
grant execute on function public.ensure_user_rows() to authenticated;

-- ---------------------------------------------------------------------
-- 14. EXCLUIR A PRÓPRIA CONTA (botão Excluir conta, em Configurações)
--     Apaga o usuário em Authentication; as tabelas do Portfy apagam em cascata.
--     Obs.: arquivos já enviados ao Storage não são apagados por SQL.
-- ---------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------
-- 15. CONTAS QUE JÁ EXISTEM (seguro rodar de novo)
--     Se você apagou o banco antigo, os usuários continuam em Authentication,
--     mas ficaram sem perfil, configurações e plano. Isto cria o que falta
--     para todos de uma vez (o site também faz isso no login, via ensure_user_rows).
-- ---------------------------------------------------------------------
insert into public.perfis (id, nome_completo, email)
  select u.id, coalesce(u.raw_user_meta_data ->> 'full_name', ''), u.email from auth.users u where true
  on conflict (id) do nothing;
insert into public.configuracoes_usuario (usuario_id)
  select u.id from auth.users u where true
  on conflict do nothing;
insert into public.assinaturas (usuario_id, codigo_plano)
  select u.id, 'A' from auth.users u where true
  on conflict do nothing;

-- Faz a API do Supabase enxergar as tabelas novas na hora
notify pgrst, 'reload schema';

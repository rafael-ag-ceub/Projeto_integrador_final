-- =====================================================================
-- PORTFY · Apagar o banco ANTIGO (tabelas em inglês)
--
-- ATENÇÃO: este script APAGA as tabelas antigas e todos os dados que
-- estão nelas (tasks, events, notes, projects, documents, profiles...).
-- Os USUÁRIOS (Authentication) NÃO são apagados: eles continuam podendo
-- entrar, e o site recria perfil/configurações/plano no próximo login
-- (função ensure_user_rows).
--
-- Use SÓ se os dados atuais são de teste. Se quiser guardar algo,
-- exporte antes: Table Editor > tabela > "Export" > CSV.
--
-- ORDEM DE USO
--   1. Rode a PARTE 1 sozinha e confira a lista.
--   2. Rode a PARTE 2 (apaga).
--   3. Rode migrations/20261008000000_initial_schema.sql
--   4. Rode migrations/20261008000100_email_reminders.sql
--   5. Rode tools/verificar_banco.sql (tudo deve estar OK)
-- =====================================================================


-- ---------------------------------------------------------------------
-- PARTE 1 · Só olhar. O que existe hoje no schema public?
-- ---------------------------------------------------------------------
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;


-- ---------------------------------------------------------------------
-- PARTE 2 · Apagar o que é antigo (rode somente depois de conferir a parte 1)
-- ---------------------------------------------------------------------

-- 2.1 Gatilho que cria o perfil ao cadastrar (o esquema novo recria o gatilho)
drop trigger if exists on_auth_user_created on auth.users;

-- 2.2 Tabelas antigas (cascade remove índices, políticas e gatilhos delas)
drop table if exists
  public.ai_messages,
  public.ai_usage_daily,
  public.ai_conversations,
  public.email_log,
  public.activity_log,
  public.notes,
  public.events,
  public.tasks,
  public.projects,
  public.documents,
  public.templates,
  public.payments,
  public.subscriptions,
  public.diagnostics,
  public.user_settings,
  public.profiles,
  public.plans
cascade;

-- 2.3 Tipos (enums) antigos
drop type if exists public.doc_kind   cascade;
drop type if exists public.sub_status cascade;
drop type if exists public.pay_status cascade;
drop type if exists public.ai_role    cascade;

-- 2.4 Função cujo formato de retorno mudou (o "create or replace" não consegue trocar)
drop function if exists public.due_task_reminders(date);

-- 2.5 Conferência: não deve sobrar nenhuma tabela em inglês
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;

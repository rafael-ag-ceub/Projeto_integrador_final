-- =====================================================================
-- PORTFY · Verificação do banco
-- Rode no SQL Editor do Supabase. Mostra uma tabela: tudo deve estar OK.
-- Se algo estiver em ATENÇÃO, rode de novo o arquivo
-- supabase/migrations/20261008000000_initial_schema.sql
-- =====================================================================
with checks (verificacao, esperado, encontrado) as (
  select 'Tabelas do Portfy (16 obrigatórias)', 16::bigint,
         (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('planos','perfis','configuracoes_usuario','diagnosticos','assinaturas','pagamentos','modelos','documentos','projetos','tarefas','eventos','notas','registro_atividades','ia_conversas','ia_mensagens','ia_uso_diario'))
  union all
  select 'Dessas tabelas, com RLS ligado', 16,
         (select count(*) from pg_tables where schemaname = 'public' and rowsecurity and tablename in ('planos','perfis','configuracoes_usuario','diagnosticos','assinaturas','pagamentos','modelos','documentos','projetos','tarefas','eventos','notas','registro_atividades','ia_conversas','ia_mensagens','ia_uso_diario'))
  union all
  select 'Políticas de segurança (RLS)', 20,
         (select count(*) from pg_policies where schemaname = 'public')
  union all
  select 'Gatilho on_auth_user_created', 1,
         (select count(*) from pg_trigger t
            join pg_class c on c.oid = t.tgrelid
            join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'auth' and c.relname = 'users' and t.tgname = 'on_auth_user_created' and not t.tgisinternal)
  union all
  select 'Funções do Portfy', 6,
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('ensure_user_rows','ai_quota','ai_register_usage','dashboard_stats','handle_new_user','delete_my_account'))
  union all
  select 'Colunas usuario_id com preenchimento automático', 6,
         (select count(*) from information_schema.columns
           where table_schema = 'public' and column_name = 'usuario_id' and column_default like '%auth.uid()%')
  union all
  select 'Buckets de imagens (avatars, doc-images)', 2,
         (select count(*) from storage.buckets where id in ('avatars', 'doc-images'))
  union all
  select 'Planos cadastrados (A, B, C)', 3, (select count(*) from public.planos)
  union all
  select 'Modelos cadastrados', 6, (select count(*) from public.modelos)
  union all
  select 'Usuários sem perfil (o site conserta no próximo login)', 0,
         (select count(*) from auth.users u left join public.perfis p on p.id = u.id where p.id is null)
)
select verificacao, esperado, encontrado,
       case when encontrado = esperado then 'OK' else 'ATENÇÃO' end as status
from checks;

-- Usuários que existem hoje em Authentication (inclui os apagados com "soft delete", se houver):
-- select id, email, email_confirmed_at, created_at, deleted_at from auth.users order by created_at desc;
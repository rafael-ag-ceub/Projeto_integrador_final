-- =====================================================================
-- PORTFY · Lembretes de tarefas por e-mail
-- Rode DEPOIS da migração inicial. É idempotente.
--   registro_emails      evita enviar o mesmo lembrete duas vezes no dia
--   due_task_reminders() lista quem deve receber e quais tarefas vencem
-- Ambos são usados SOMENTE pela Edge Function send-reminders (service role).
-- =====================================================================
create table if not exists public.registro_emails (
  usuario_id uuid not null references auth.users (id) on delete cascade,
  tipo       text not null,
  dia        date not null,
  enviado_em timestamptz not null default now(),
  primary key (usuario_id, tipo, dia)
);
alter table public.registro_emails enable row level security;   -- sem policies: o navegador não acessa
revoke all on public.registro_emails from anon, authenticated;

-- O nome das colunas devolvidas mudou (user_id -> usuario_id etc.). O Postgres NÃO deixa
-- trocar isso com "create or replace", então apagamos a versão antiga antes de recriar.
drop function if exists public.due_task_reminders(date);

create or replace function public.due_task_reminders(p_day date)
returns table (usuario_id uuid, email text, nome_completo text, titulos text[])
language sql stable security definer set search_path = public as $$
  select p.id, p.email, p.nome_completo, array_agg(t.titulo order by t.criado_em)
  from public.perfis p
  join public.configuracoes_usuario s on s.usuario_id = p.id and s.notificacoes_email
  join public.tarefas t on t.usuario_id = p.id and not t.concluida and t.data_vencimento <= p_day
  where p.email is not null
    and not exists (select 1 from public.registro_emails l
                    where l.usuario_id = p.id and l.tipo = 'task_reminder' and l.dia = p_day)
  group by p.id, p.email, p.nome_completo;
$$;
revoke all on function public.due_task_reminders(date) from public, anon, authenticated;
grant execute on function public.due_task_reminders(date) to service_role;

notify pgrst, 'reload schema';

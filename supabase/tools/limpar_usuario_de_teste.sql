-- =====================================================================
-- PORTFY · Ferramenta de testes: limpar um usuário de teste
-- Rode no SQL Editor do Supabase, uma parte por vez.
-- Apagar linhas das tabelas NÃO apaga o usuário: ele mora em Authentication.
-- =====================================================================

-- 1. Ver se o e-mail ainda existe no Authentication (troque o trecho do e-mail)
select id, email, email_confirmed_at, created_at
from auth.users
where email ilike '%rafael%';

-- 2. Apagar o usuário e TODOS os dados dele (perfil, tarefas, arquivos...), em cascata
-- delete from auth.users where email = 'seu-email@exemplo.com';

-- 3. Ver usuários sem perfil (o site cria o perfil sozinho no próximo login)
select u.id, u.email
from auth.users u
left join public.perfis p on p.id = u.id
where p.id is null;

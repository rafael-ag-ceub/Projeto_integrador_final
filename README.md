# Portfy

Plataforma para organizar a carreira: currículos, portfólios, agenda, notas e Agente de IA.

## Estrutura (MVC)

```
portfy-mvc/
├── index.html                 View: esqueleto das telas
├── css/                       View: estilos (base, landing, auth, app)
├── js/
│   ├── config.js              Configuração (chaves públicas do Supabase)
│   ├── utils.js               Funções utilitárias
│   ├── models/                Model: estado, catálogos e regras dos arquivos
│   ├── services/              Persistência e serviços (localStorage, Supabase, IA)
│   ├── views/                 View: desenho das páginas, modais e editor
│   ├── controllers/           Controller: ações do usuário
│   └── main.js                Inicialização
├── supabase/
│   ├── migrations/            Persistence: tabelas, segurança (RLS), funções
│   ├── tools/                 Apagar banco antigo, verificar o banco, limpar usuário de teste
│   ├── templates/             E-mails de login em português (colar no painel)
│   └── functions/
│       ├── _shared/           Serviços e repositórios compartilhados (IA, e-mail, prompt)
│       ├── ai-chat/           Controller da API de IA
│       └── send-reminders/    Controller dos lembretes de tarefas por e-mail
└── docs/                      Documentação
```

## Rodar no computador

Abra a pasta no VS Code e use a extensão Live Server (botão Go Live). Não abra o index.html com duplo clique, porque alguns recursos exigem um servidor local.
Alternativa: `npx serve .` dentro da pasta.

## Modo local x Supabase

Com `js/config.js` vazio, o site funciona com localStorage (demonstração).
Preencha `SUPABASE_URL` e `SUPABASE_ANON_KEY` para conectar ao banco real. Veja o guia de integração.

## Segurança

Nunca versione chaves secretas (service_role, chave da IA). Elas ficam somente nos secrets do Supabase.

## Modo Supabase (banco em português)

As tabelas e colunas do banco têm nomes em português (tarefas, eventos, notas, projetos, documentos, perfis...).
O front-end continua usando seus nomes curtos (t, d, done...). O único arquivo que conhece os dois lados é
`js/services/portfy-api.js` (veja MAP e TABELA). As Edge Functions usam os nomes em português direto.

O `js/config.js` já traz a URL e a chave pública do projeto. Para a integração completa, no SQL Editor do Supabase:
1. (Só se o banco ainda tem as tabelas antigas em inglês) rode `supabase/tools/00_apagar_banco_antigo.sql`.
2. Rode `supabase/migrations/20261008000000_initial_schema.sql`.
3. Rode `supabase/migrations/20261008000100_email_reminders.sql`.
4. Rode `supabase/tools/verificar_banco.sql`: todas as linhas devem dizer OK.
5. Configure o SMTP e cole os modelos de `supabase/templates/` em Authentication, Emails.
6. Publique as funções (depois de `npx supabase login` e `npx supabase link --project-ref SEU-REF`):
   `npx supabase functions deploy ai-chat` e `npx supabase functions deploy send-reminders --no-verify-jwt`.

Segredos (chave da IA, e-mail) ficam só em `npx supabase secrets set --env-file .env`. Nunca no código.

### Regra de ouro ao mudar um nome no banco
Mudou uma tabela ou coluna? Atualize os 3 lugares: o SQL, o `portfy-api.js` (MAP/TABELA) e as Edge Functions
(`_shared/chat.repository.ts`, `_shared/prompt.ts`, `send-reminders/index.ts`).

## Se algo não salvar

1. Olhe a faixa no rodapé do formulário de acesso: ela diz se o site está conectado ao Supabase ou em modo local.
2. Abra o console (F12) e rode `await portfyDiag()`: ele testa banco, login, gravação, Storage e a função de IA.
3. Para conferir o banco inteiro, rode `supabase/tools/verificar_banco.sql`.
4. Para apagar um usuário de teste de verdade, use `supabase/tools/limpar_usuario_de_teste.sql`.

/* =====================================================================
   PORTFY · portfy-api.js
   Camada única de acesso ao Supabase. O front-end chama estas funções
   no lugar do localStorage. Os dados voltam no MESMO formato que o
   objeto D já usa (tasks, events, notes, projs, docs, prof...).

   BANCO EM PORTUGUÊS: as tabelas e colunas do Supabase têm nomes em português
   (tarefas, eventos, notas, projetos, documentos, perfis...). Os nomes do
   FRONT-END (t, d, done, desc, pr, w, h, els...) continuam iguais: o único
   lugar que conhece os dois lados é este arquivo (MAP e TABELA abaixo).

   Antes deste arquivo, carregue a biblioteca do Supabase:
   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
   <script src="portfy-api.js"></script>
   ===================================================================== */
const PortfyAPI = (() => {
  let sb = null;

  const db = () => {
    if (!sb) throw new Error('Chame PortfyAPI.init(url, chave) antes de usar a API.');
    return sb;
  };
  const ok = ({ data, error }) => { if (error) throw error; return data; };
  /** Id do usuário logado. Lê a sessão local (rápido), sem ir ao servidor a cada chamada. */
  const uid = async () => {
    const { data } = await db().auth.getSession();
    if (!data.session) throw new Error('Sessão expirada. Entre novamente.');
    return data.session.user.id;
  };

  /* Tradução entre o que o banco guarda e o que o front mostra */
  const LANG = { 'pt-BR': 'Português (Brasil)', en: 'English', es: 'Español' };
  const PRIV = { public: 'Público', link: 'Somente com link', private: 'Privado' };
  const invert = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [v, k]));

  /* Nome da tabela real no banco para cada "chave" usada pelo front-end */
  const TABELA = { tasks: 'tarefas', events: 'eventos', notes: 'notas', projects: 'projetos', documents: 'documentos' };

  /* Conversores: formato do front <-> colunas do banco */
  const MAP = {
    tasks: {
      to:   (t) => ({ titulo: t.t, data_vencimento: t.d, concluida: !!t.done }),
      from: (r) => ({ id: r.id, t: r.titulo, d: r.data_vencimento, done: r.concluida ? 1 : 0 }),
    },
    events: {
      to:   (e) => ({ titulo: e.t, data_evento: e.d, hora_evento: e.h }),
      from: (r) => ({ id: r.id, t: r.titulo, d: r.data_evento, h: String(r.hora_evento).slice(0, 5) }),
    },
    notes: {
      to:   (n) => ({ titulo: n.t, conteudo: n.c }),
      from: (r) => ({ id: r.id, t: r.titulo, c: r.conteudo }),
    },
    projects: {
      to:   (p) => ({ titulo: p.t, descricao: p.desc, progresso: p.pr }),
      from: (r) => ({ id: r.id, t: r.titulo, desc: r.descricao, pr: r.progresso }),
    },
    documents: {
      to:   (d) => ({ tipo: d.kind, titulo: d.title, largura: d.w, altura: d.h, cor_fundo: d.bg, elementos: d.els }),
      from: (r) => ({ id: r.id, kind: r.tipo, title: r.titulo, w: r.largura, h: r.altura, bg: r.cor_fundo, els: r.elementos, upd: Date.parse(r.atualizado_em) }),
    },
  };

  /* CRUD genérico: add / update / remove. "chave" é a do front (tasks, events...); a tabela real vem de TABELA */
  const crud = (chave) => {
    const tabela = TABELA[chave];
    return {
      async add(item) {
        // usuario_id é obrigatório no banco e o RLS confere se é o do usuário logado
        const row = { ...MAP[chave].to(item), usuario_id: await uid() };
        return MAP[chave].from(ok(await db().from(tabela).insert(row).select().single()));
      },
      async update(id, item) { return MAP[chave].from(ok(await db().from(tabela).update(MAP[chave].to(item)).eq('id', id).select().single())); },
      async remove(id)      { ok(await db().from(tabela).delete().eq('id', id)); },
    };
  };

  /* Mensagens de erro em português */
  const friendly = (err) => {
    const m = String(err?.message || err);
    if (/Invalid login credentials/i.test(m)) return 'E-mail ou senha incorretos.';
    if (/Email not confirmed/i.test(m)) return 'Confirme seu e-mail antes de entrar. Veja sua caixa de entrada.';
    if (/already registered|already been registered/i.test(m)) return 'Este e-mail já tem conta. Entre ou recupere a senha.';
    if (/Password should be|weak/i.test(m)) return 'A senha precisa ter 8 ou mais caracteres, uma letra maiúscula e um número.';
    if (/rate limit|too many/i.test(m)) return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
    if (/Failed to fetch|NetworkError/i.test(m)) return 'Sem conexão com o servidor. Verifique sua internet.';
    return m;
  };

  /** Teste rápido na abertura do site: o banco foi criado? */
  const ping = async () => {
    try {
      const { error } = await db().from('planos').select('codigo').limit(1);
      if (error) return { ok: false, message: 'Banco não configurado: rode o SQL do Passo B no Supabase. (' + error.message + ')' };
      return { ok: true };
    } catch (e) {
      return { ok: false, message: 'Sem conexão com o Supabase: ' + (e.message || e) };
    }
  };

  /** Checklist completo. No console do navegador (F12): await portfyDiag() */
  const diagnose = async () => {
    const out = [];
    const check = async (teste, fn) => {
      try { out.push({ teste, resultado: 'OK', detalhe: (await fn()) ?? '' }); }
      catch (e) { out.push({ teste, resultado: 'FALHOU', detalhe: e.message || String(e) }); }
    };
    let id = null;
    await check('Tabelas criadas (SQL do Passo B)', async () => `${ok(await db().from('planos').select('codigo')).length} planos`);
    await check('Login ativo', async () => { id = await uid(); return id; });
    await check('Perfil existe', async () => { await db().rpc('ensure_user_rows'); ok(await db().from('perfis').select('id').eq('id', id).single()); });
    await check('Gravar e apagar uma tarefa de teste', async () => {
      const row = ok(await db().from('tarefas').insert({ titulo: 'teste', usuario_id: id }).select().single());
      ok(await db().from('tarefas').delete().eq('id', row.id));
    });
    await check('Storage (bucket doc-images)', async () => { ok(await db().storage.from('doc-images').list(id)); });
    await check('Função de IA publicada', async () => {
      const { error } = await db().functions.invoke('ai-chat', { body: { message: '' } });
      const st = error && error.context && error.context.status;
      if (error && (st === 404 || !st)) throw new Error('não encontrada: faça o Passo G');
      return 'respondeu (status ' + (st || 200) + ')';
    });
    return out;
  };

  return {
    friendly, ping, diagnose,

    /** Inicia o cliente. Use a URL do projeto e a chave pública (anon / publishable). */
    init(url, publicKey) {
      sb = window.supabase.createClient(url, publicKey);
      return sb;
    },
    get client() { return db(); },

    /* ------------------------- Autenticação ------------------------- */
    async signUp(name, email, password) {
      const { data, error } = await db().auth.signUp({
        email, password,
        // o link de confirmação volta para a página onde a pessoa se cadastrou
        options: { data: { full_name: name }, emailRedirectTo: location.origin + location.pathname },
      });
      if (error) throw error;
      return data;                       // data.session = null se a confirmação por e-mail estiver ligada
    },
    async signIn(email, password) {
      return ok(await db().auth.signInWithPassword({ email, password }));
    },
    async signOut() { ok(await db().auth.signOut()); },
    async session() { return (await db().auth.getSession()).data.session; },
    onAuth(callback) { return db().auth.onAuthStateChange((event, session) => callback(event, session)); },
    async requestReset(email, redirectTo) {
      ok(await db().auth.resetPasswordForEmail(email, { redirectTo }));
    },
    async setNewPassword(password) { ok(await db().auth.updateUser({ password })); },

    /* ------------------- Carregar tudo ao entrar --------------------- */
    /** Devolve um objeto no formato do D atual do front-end. */
    async load() {
      const id = await uid();
      await db().rpc('ensure_user_rows');   // cria perfil/configurações que faltarem (contas antigas ou criadas à mão)
      const [prof, set, sub, diag, tasks, events, notes, projs, docs, log, msgs] = await Promise.all([
        db().from('perfis').select('*').eq('id', id).single(),
        db().from('configuracoes_usuario').select('*').eq('usuario_id', id).single(),
        db().from('assinaturas').select('codigo_plano').eq('usuario_id', id).single(),
        db().from('diagnosticos').select('*').eq('usuario_id', id).maybeSingle(),
        db().from('tarefas').select('*').order('data_vencimento'),
        db().from('eventos').select('*').order('data_evento').order('hora_evento'),
        db().from('notas').select('*').order('atualizado_em', { ascending: false }),
        db().from('projetos').select('*').order('criado_em', { ascending: false }),
        db().from('documentos').select('*').order('atualizado_em', { ascending: false }),
        db().from('registro_atividades').select('mensagem, criado_em').order('criado_em', { ascending: false }).limit(20),
        db().from('ia_mensagens').select('conversa_id, papel, conteudo').order('criado_em', { ascending: false }).limit(40),
      ]);
      const p = ok(prof), s = ok(set), d = ok(diag), chatRows = ok(msgs).reverse();
      return {
        name: p.nome_completo || String(p.email || '').split('@')[0], email: p.email,
        prof: { role: p.profissao || '', phone: p.telefone || '', link: p.url_portfolio || '', bio: p.biografia || '' },
        lang: LANG[s.idioma], priv: PRIV[s.privacidade], notif: s.notificacoes_email ? 1 : 0, fa: s.autenticacao_dois_fatores ? 1 : 0,
        plan: ok(sub).codigo_plano,
        diag: d ? [d.horas_estudo, d.fase_academica, d.mercado_alvo] : null,
        tasks: ok(tasks).map(MAP.tasks.from), events: ok(events).map(MAP.events.from),
        notes: ok(notes).map(MAP.notes.from), projs: ok(projs).map(MAP.projects.from),
        docs: ok(docs).map(MAP.documents.from),
        log: ok(log).map((r) => ({ t: r.mensagem, ts: Date.parse(r.criado_em) })),
        chat: chatRows.length ? chatRows.map((r) => [r.papel === 'usuario' ? 'me' : 'ai', r.conteudo])
                              : [['ai', 'Oi! Sou o Agente Portfy. Posso ajudar com currículo, portfólio, entrevistas e rotina de estudos. Por onde começamos?']],
        conv: chatRows.length ? chatRows[chatRows.length - 1].conversa_id : null,
        seeded: 1,
      };
    },

    /* ----------------------- Dados do usuário ------------------------ */
    tasks: crud('tasks'),
    events: crud('events'),
    notes: crud('notes'),
    projects: crud('projects'),
    documents: crud('documents'),

    async saveProfile(name, prof) {
      ok(await db().from('perfis').update({
        nome_completo: name, profissao: prof.role, telefone: prof.phone, url_portfolio: prof.link, biografia: prof.bio,
      }).eq('id', await uid()));
    },
    async saveSettings({ lang, priv, notif, fa }) {
      ok(await db().from('configuracoes_usuario').update({
        idioma: invert(LANG)[lang], privacidade: invert(PRIV)[priv],
        notificacoes_email: !!notif, autenticacao_dois_fatores: !!fa,
      }).eq('usuario_id', await uid()));
    },
    async saveDiagnostic([hours, phase, market]) {
      ok(await db().from('diagnosticos').upsert({
        usuario_id: await uid(), horas_estudo: hours, fase_academica: phase, mercado_alvo: market,
      }));
    },
    async log(message) {
      ok(await db().from('registro_atividades').insert({ usuario_id: await uid(), mensagem: message }));
    },
    async stats() { return ok(await db().rpc('dashboard_stats')); },

    /* ----------------- Imagens (Storage) para o editor ---------------- */
    /** Envia a imagem e devolve a URL pública para guardar no elemento. */
    async uploadImage(file, bucket = 'doc-images') {
      const ext = (file.name.split('.').pop() || 'png').toLowerCase();
      const path = `${await uid()}/${crypto.randomUUID()}.${ext}`;
      ok(await db().storage.from(bucket).upload(path, file, { contentType: file.type, upsert: false }));
      return db().storage.from(bucket).getPublicUrl(path).data.publicUrl;
    },

    /* --------------------------- Agente de IA ------------------------- */
    async quota() { return ok(await db().rpc('ai_quota')); },
    /** Devolve { reply, conversation_id, quota }. Em caso de erro, lança Error com mensagem amigável. */
    async askAI(message, conversationId) {
      const { data, error } = await db().functions.invoke('ai-chat', {
        body: { message, conversation_id: conversationId },
      });
      if (error) {
        let detail = null;
        try { detail = await error.context.json(); } catch (_) { /* resposta sem corpo */ }
        const st = error.context && error.context.status;
        const e = new Error(detail?.message || (st === 404 ? 'A função de IA ainda não foi publicada (Passo G do guia).' : 'A IA não respondeu. Tente de novo.'));
        e.quota = detail?.quota;
        throw e;
      }
      return data;
    },
  };
})();

/* =====================================================================
   COMO LIGAR NO FRONT-END (exemplos que o guia explica passo a passo)

   // Início do script do index.html
   PortfyAPI.init('https://SEU-PROJETO.supabase.co', 'SUA_CHAVE_PUBLICA');

   // Login
   await PortfyAPI.signIn(email, senha);
   D = await PortfyAPI.load();

   // Cadastro (depois do diagnóstico)
   await PortfyAPI.signUp(nome, email, senha);
   await PortfyAPI.saveDiagnostic([horas, fase, mercado]);

   // Tarefa criada / concluída / excluída
   const t = await PortfyAPI.tasks.add({ t: 'Estudar', d: '2026-10-10', done: 0 });
   await PortfyAPI.tasks.update(t.id, { ...t, done: 1 });
   await PortfyAPI.tasks.remove(t.id);

   // Salvar o arquivo aberto no editor
   await PortfyAPI.documents.update(Ed.doc.id, Ed.doc);

   // Chat com IA
   const r = await PortfyAPI.askAI(texto, D.conv); D.conv = r.conversation_id;
   ===================================================================== */

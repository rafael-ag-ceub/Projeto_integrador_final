/* =====================================================================
   PORTFY · js/main.js
   Camada: Inicialização
   Liga o Supabase (se o config.js estiver preenchido) e abre o site.
   ===================================================================== */

// 1. Detecta, antes de o Supabase limpar o endereço, se a pessoa chegou pelo link de "esqueci a senha"
const RECOVERY = /type=recovery/.test(location.hash);

const LINK_ERROR = (location.hash.match(/error_description=([^&]+)/) || [])[1];   // link vencido ou já usado

// 2. Conecta ao Supabase quando o config.js estiver preenchido; senão usa o localStorage
if (USE_SUPABASE) PortfyAPI.init(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);

document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeM(); });

(async function init() {
  const theme = ls.get('pf_theme', null);
  if (theme) document.documentElement.dataset.theme = theme;

  // Faixa que mostra em qual modo o site está (ajuda a saber se os dados vão para o banco)
  $('#mode-badge').textContent = USE_SUPABASE
    ? 'Conectado ao Supabase · ' + new URL(CONFIG.SUPABASE_URL).hostname.split('.')[0]
    : 'Modo local (demonstração): os dados ficam só neste navegador';

  // Modo local: reabre a sessão guardada no navegador
  if (!USE_SUPABASE) {
    if (ls.get('pf_session', null)) enter();
    return;
  }

  // Modo Supabase: "esqueci a senha" só pede o e-mail (o resto vai por link)
  $('#f-pw-wrap').style.display = 'none';
  $('#a-forgot p').textContent = 'Informe seu e-mail e enviaremos um link para redefinir a senha.';
  $('#a-forgot button[type="submit"]').textContent = 'Enviar link';

  // Aviso se o banco ainda não foi criado e atalho de diagnóstico: await portfyDiag()
  PortfyAPI.ping().then((r) => { if (!r.ok) { console.error(r.message); toast(r.message); } });
  globalThis.portfyDiag = async () => { const r = await PortfyAPI.diagnose(); console.table(r); return r; };

  if (LINK_ERROR) {
    auth('login');
    toast('O link expirou ou já foi usado. Peça um novo em Esqueci a senha.');
    history.replaceState(null, '', location.pathname);
    return;
  }
  if (RECOVERY) { auth('newpass'); return; }
  try {
    if (await PortfyAPI.session()) await bootRemote();
  } catch (ex) {
    console.error(ex);
  }
})();

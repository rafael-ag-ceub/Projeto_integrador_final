/* =====================================================================
   PORTFY · js/config.js
   Camada: Configuração
   Dados PÚBLICOS de conexão com o Supabase.
   A URL e a chave "anon" podem ficar aqui: a proteção dos dados vem do RLS.
   NUNCA coloque neste arquivo a chave service_role nem a chave da IA.
   Para voltar ao modo local (localStorage), deixe os dois campos vazios.
   ===================================================================== */
const CONFIG = {
  SUPABASE_URL: 'https://viybfblkpnlrsirjoctv.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZpeWJmYmxrcG5scnNpcmpvY3R2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE0NTk3NjAsImV4cCI6MjEwNzAzNTc2MH0.EuXjg8lMn1_8tvMfku0RtK89D2o29GerHMZUaWNjm0c',
};
const USE_SUPABASE = Boolean(CONFIG.SUPABASE_URL && CONFIG.SUPABASE_ANON_KEY);

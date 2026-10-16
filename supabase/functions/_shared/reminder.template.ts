// =====================================================================
// PORTFY · supabase/functions/_shared/reminder.template.ts
// Camada: View do e-mail de lembrete (texto e HTML).
// =====================================================================
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))

export function reminderEmail(name: string, titles: string[], siteUrl: string) {
  const first = esc((name || '').split(' ')[0] || 'tudo bem')
  const items = titles.map((t) => `<li style="margin:6px 0">${esc(t)}</li>`).join('')
  const subject = titles.length === 1 ? 'Você tem 1 tarefa para hoje no Portfy' : `Você tem ${titles.length} tarefas para hoje no Portfy`
  const html = `<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#0A1A3F">
  <div style="background:#0A1A3F;color:#fff;padding:20px 28px;border-radius:14px 14px 0 0;font-size:20px;font-weight:bold">Portfy</div>
  <div style="border:1px solid #DCE3F2;border-top:0;border-radius:0 0 14px 14px;padding:28px">
    <h2 style="margin:0 0 12px">Olá, ${first}!</h2>
    <p style="color:#33415f">Estas tarefas vencem hoje ou estão atrasadas:</p>
    <ul style="color:#0A1A3F;padding-left:20px">${items}</ul>
    <p><a href="${esc(siteUrl)}" style="display:inline-block;background:#1F44C9;color:#fff;text-decoration:none;font-weight:bold;padding:12px 24px;border-radius:10px">Abrir o Portfy</a></p>
    <p style="font-size:12px;color:#6b7893">Para parar de receber, desligue Notificações por e-mail em Configurações.</p>
  </div></div>`
  return { subject, html }
}

// =====================================================================
// PORTFY · supabase/functions/_shared/mail.service.ts
// Camada: Service. Único arquivo que conhece o provedor de e-mail (Resend, via API HTTPS).
// Para trocar de provedor, altere somente este arquivo.
// Os e-mails de LOGIN (confirmar conta, recuperar senha) NÃO passam por aqui:
// eles saem direto do Supabase Auth, pelo SMTP configurado no painel.
// =====================================================================
export async function sendMail(p: { to: string; subject: string; html: string }) {
  const key = Deno.env.get('RESEND_API_KEY')
  if (!key) throw new Error('RESEND_API_KEY não configurada.')
  const from = Deno.env.get('MAIL_FROM') ?? 'Portfy <onboarding@resend.dev>'

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from, to: [p.to], subject: p.subject, html: p.html }),
  })
  if (!res.ok) throw new Error(`Falha ao enviar e-mail (${res.status}): ${await res.text()}`)
}

// Tells the moderator a report is waiting. Says nothing about the report, so no personal data leaves Supabase.
export async function reportAlert(request, env, send = fetch) {
  if (request.method !== 'POST') return new Response(null, { status: 405 });
  if (!env.REPORT_ALERT_WEBHOOK_URL || !env.SUPABASE_URL) return new Response(null, { status: 503 });
  const message = 'Chalkbook has a new report waiting for review.';
  try {
    // Ping only for a report the caller just filed, once per report, so this can't be used to spam the moderator.
    const claim = await send(`${env.SUPABASE_URL}/rest/v1/rpc/claim_report_alert`, {
      method: 'POST', body: '{}', headers: {
        'Content-Type': 'application/json', apikey: request.headers.get('apikey') ?? env.SUPABASE_ANON_KEY ?? '',
        Authorization: request.headers.get('Authorization') ?? '',
      },
    });
    if (!claim.ok || (await claim.json()) !== true) return new Response(null, { status: 204 });
    // Discord reads "content" and Slack reads "text".
    const sent = await send(env.REPORT_ALERT_WEBHOOK_URL, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content: message, text: message }),
    });
    return new Response(null, { status: sent.ok ? 204 : 502 });
  } catch {
    return new Response(null, { status: 502 });
  }
}

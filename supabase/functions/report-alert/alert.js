// Tells the moderator a report is waiting. Says nothing about the report, so no personal data leaves Supabase.
// shortcut: any signed-in climber can trigger this ping, add a rate limit if it is ever abused.
export async function reportAlert(request, env, send = fetch) {
  if (request.method !== 'POST') return new Response(null, { status: 405 });
  if (!env.REPORT_ALERT_WEBHOOK_URL) return new Response(null, { status: 503 });
  const message = 'Chalkbook has a new report waiting for review.';
  try {
    // Discord reads "content" and Slack reads "text".
    const sent = await send(env.REPORT_ALERT_WEBHOOK_URL, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content: message, text: message }),
    });
    return new Response(null, { status: sent.ok ? 204 : 502 });
  } catch {
    return new Response(null, { status: 502 });
  }
}

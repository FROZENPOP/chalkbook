// Revokes a Sign in with Apple grant when an account is deleted, as App Store rules require.
// Plain JS with its dependencies passed in, so supabase/tests/functions.mjs can run it under Node.
const encode = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
const encodeJSON = (value) => encode(new TextEncoder().encode(JSON.stringify(value)));

async function clientSecret(env, now) {
  const der = Uint8Array.from(atob(env.APPLE_PRIVATE_KEY.replace(/-----[^-]+-----|\s/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const unsigned = `${encodeJSON({ alg: 'ES256', kid: env.APPLE_KEY_ID })}.${encodeJSON({
    iss: env.APPLE_TEAM_ID, iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: env.APPLE_CLIENT_ID,
  })}`;
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${encode(signature)}`;
}

export async function revokeApple(request, env, send = fetch) {
  if (request.method !== 'POST') return new Response(null, { status: 405 });
  const code = (await request.json().catch(() => ({}))).authorization_code;
  if (typeof code !== 'string' || !code || code.length > 1024) return new Response(null, { status: 400 });
  if (!env.APPLE_PRIVATE_KEY || !env.APPLE_KEY_ID || !env.APPLE_TEAM_ID || !env.APPLE_CLIENT_ID) return new Response(null, { status: 503 });
  try {
    const secret = await clientSecret(env, Math.floor(Date.now() / 1000));
    const post = (path, values) => send(`https://appleid.apple.com/auth/${path}`, {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: env.APPLE_CLIENT_ID, client_secret: secret, ...values }),
    });
    const exchanged = await post('token', { code, grant_type: 'authorization_code' });
    const token = exchanged.ok ? (await exchanged.json()).refresh_token : null;
    if (!token) return new Response(null, { status: 502 });
    const revoked = await post('revoke', { token, token_type_hint: 'refresh_token' });
    return new Response(null, { status: revoked.ok ? 204 : 502 });
  } catch {
    return new Response(null, { status: 502 }); // Never log here: errors could carry the code or the key.
  }
}

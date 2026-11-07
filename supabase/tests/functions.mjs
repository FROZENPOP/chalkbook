// Edge function test with Apple and the webhook faked. Run with Node.
import assert from 'node:assert/strict';
import { revokeApple } from '../functions/revoke-apple/revoke.js';
import { reportAlert } from '../functions/report-alert/alert.js';

const { publicKey, privateKey } = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', privateKey)).toString('base64');
const env = { APPLE_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----\n`, APPLE_KEY_ID: 'KEY', APPLE_TEAM_ID: 'TEAM', APPLE_CLIENT_ID: 'com.frozenpop.ClimbingApp', SUPABASE_URL: 'https://db.invalid' };
const call = (body, method = 'POST') => new Request('https://test.invalid', { method, headers: { apikey: 'sb_publishable_x', Authorization: 'Bearer user' }, ...(method === 'POST' ? { body: JSON.stringify(body) } : {}) });
const decode = (part) => JSON.parse(Buffer.from(part, 'base64url'));

const idToken = (sub) => `e30.${Buffer.from(JSON.stringify({ sub })).toString('base64url')}.sig`;
function apple(token = { ok: true, refresh_token: 'refresh', id_token: idToken('apple-a') }, revoke = true, identities = [{ provider: 'apple', identity_data: { sub: 'apple-a' } }]) {
 const seen = [];
 return { seen, send: async (url, init) => {
  if (url === 'https://db.invalid/auth/v1/user') { seen.user = init.headers; return Response.json({ identities }); }
  seen.push({ url, form: Object.fromEntries(init.body) });
  if (url.endsWith('/auth/token')) return new Response(JSON.stringify(token), { status: token.ok ? 200 : 400 });
  return new Response(null, { status: revoke ? 200 : 400 });
 } };
}

// Exchanges the code, then revokes the refresh token, with a client secret Apple can verify.
let fake = apple();
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, fake.send)).status, 204);
assert.deepEqual(fake.seen.map((x) => x.url), ['https://appleid.apple.com/auth/token', 'https://appleid.apple.com/auth/revoke']);
assert.equal(fake.seen[0].form.code, 'code'); assert.equal(fake.seen[0].form.grant_type, 'authorization_code');
assert.equal(fake.seen[1].form.token, 'refresh'); assert.equal(fake.seen[1].form.token_type_hint, 'refresh_token');
const [head, claims, signature] = fake.seen[0].form.client_secret.split('.');
assert.deepEqual(decode(head), { alg: 'ES256', kid: 'KEY' });
const payload = decode(claims);
assert.equal(payload.iss, 'TEAM'); assert.equal(payload.sub, env.APPLE_CLIENT_ID); assert.equal(payload.aud, 'https://appleid.apple.com');
assert.ok(payload.exp > payload.iat);
assert.ok(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, publicKey, Buffer.from(signature, 'base64url'), new TextEncoder().encode(`${head}.${claims}`)));

assert.equal(fake.seen.user.Authorization, 'Bearer user', 'the caller is looked up with their own token');

// Only an Apple account may call Apple, and only to revoke its own grant.
fake = apple(undefined, true, [{ provider: 'google', identity_data: { sub: 'g' } }]);
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, fake.send)).status, 403);
assert.equal(fake.seen.length, 0, 'non-Apple callers never reach Apple');
fake = apple({ ok: true, refresh_token: 'refresh', id_token: idToken('apple-b') });
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, fake.send)).status, 403);
assert.deepEqual(fake.seen.map((x) => x.url), ['https://appleid.apple.com/auth/token'], 'someone else\'s code is never revoked');

// Failures are reported, not hidden, and never echo anything.
fake = apple({ ok: false });
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, fake.send)).status, 502);
assert.equal(fake.seen.length, 1);
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, apple(undefined, false).send)).status, 502);
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, async () => { throw new Error('offline'); })).status, 502);
assert.equal((await revokeApple(call({}), env, apple().send)).status, 400);
assert.equal((await revokeApple(call({ authorization_code: 'code' }), {}, apple().send)).status, 503);
assert.equal((await revokeApple(call({}, 'GET'), env, apple().send)).status, 405);

// The alert carries a fixed message and nothing from the report, and only fires for a report the caller just filed.
const alertEnv = { REPORT_ALERT_WEBHOOK_URL: 'https://hook.invalid', SUPABASE_URL: 'https://db.invalid' };
const alerting = (claimed) => { const sent = []; return { sent, send: async (url, init) => { sent.push({ url, init });
  return url.startsWith('https://db.invalid') ? Response.json(claimed) : new Response(null, { status: 204 }); } }; };
const signed = body => new Request('https://test.invalid', { method: 'POST', body: JSON.stringify(body), headers: { apikey: 'sb_publishable_x', Authorization: 'Bearer user' } });
let hook = alerting(true);
assert.equal((await reportAlert(signed({ reason: 'secret' }), alertEnv, hook.send)).status, 204);
assert.equal(hook.sent[0].url, 'https://db.invalid/rest/v1/rpc/claim_report_alert'); assert.equal(hook.sent[0].init.headers.Authorization, 'Bearer user');
assert.equal(hook.sent[1].url, 'https://hook.invalid'); assert.ok(!hook.sent[1].init.body.includes('secret'));
hook = alerting(false);
assert.equal((await reportAlert(signed({}), alertEnv, hook.send)).status, 204);
assert.equal(hook.sent.length, 1, 'no report to claim, no ping');
assert.equal((await reportAlert(call({}), {}, async () => new Response())).status, 503);
assert.equal((await reportAlert(call({}), alertEnv, async () => { throw new Error('offline'); })).status, 502);

console.log('Edge function checks passed.');

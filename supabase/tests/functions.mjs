// Edge function test with Apple and the webhook faked. Run with Node.
import assert from 'node:assert/strict';
import { revokeApple } from '../functions/revoke-apple/revoke.js';
import { reportAlert } from '../functions/report-alert/alert.js';

const { publicKey, privateKey } = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', privateKey)).toString('base64');
const env = { APPLE_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----\n`, APPLE_KEY_ID: 'KEY', APPLE_TEAM_ID: 'TEAM', APPLE_CLIENT_ID: 'com.frozenpop.ClimbingApp' };
const call = (body, method = 'POST') => new Request('https://test.invalid', { method, ...(method === 'POST' ? { body: JSON.stringify(body) } : {}) });
const decode = (part) => JSON.parse(Buffer.from(part, 'base64url'));

function apple(token = { ok: true, refresh_token: 'refresh' }, revoke = true) {
 const seen = [];
 return { seen, send: async (url, init) => {
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

// Failures are reported, not hidden, and never echo anything.
fake = apple({ ok: false });
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, fake.send)).status, 502);
assert.equal(fake.seen.length, 1);
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, apple(undefined, false).send)).status, 502);
assert.equal((await revokeApple(call({ authorization_code: 'code' }), env, async () => { throw new Error('offline'); })).status, 502);
assert.equal((await revokeApple(call({}), env, apple().send)).status, 400);
assert.equal((await revokeApple(call({ authorization_code: 'code' }), {}, apple().send)).status, 503);
assert.equal((await revokeApple(call({}, 'GET'), env, apple().send)).status, 405);

// The alert carries a fixed message and nothing from the report.
const sent = [];
assert.equal((await reportAlert(call({ reason: 'secret' }), { REPORT_ALERT_WEBHOOK_URL: 'https://hook.invalid' }, async (url, init) => { sent.push({ url, body: init.body }); return new Response(null, { status: 204 }); })).status, 204);
assert.equal(sent[0].url, 'https://hook.invalid'); assert.ok(!sent[0].body.includes('secret'));
assert.equal((await reportAlert(call({}), {}, async () => new Response())).status, 503);
assert.equal((await reportAlert(call({}), { REPORT_ALERT_WEBHOOK_URL: 'https://hook.invalid' }, async () => { throw new Error('offline'); })).status, 502);

console.log('Edge function checks passed.');

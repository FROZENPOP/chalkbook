// Local PostgreSQL policy test; the exact same SQL is runnable on hosted AFTER supervisor apply.
// PGlite is an external dev-only harness, not an app dependency.
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`create role anon; create role authenticated;
create schema auth; create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;`);
for (const file of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')).sort()) {
 await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
}
const results=await db.exec(await readFile(new URL('../../scripts/audit_suggested_friends.sql',import.meta.url),'utf8'));
assert.equal(results.at(-1).rows[0].suggested_friends_audit,'passed');
assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
await db.close();
console.log('Suggested-friends PostgreSQL policy audit passed; all fixtures rolled back.');

// Friend search with every migration applied. Run with Node and @electric-sql/pglite (0.5.11).
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
for (const file of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql') && !x.includes('journal_and_places')).sort()) {
 await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
}
const [a,b,c] = [1,2,3].map(i => `00000000-0000-0000-0000-00000000000${i}`);
for (const id of [a,b,c]) await db.query('insert into auth.users values($1)',[id]);
async function as(id) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); }
const names = async q => (await db.query('select username from public.search_climbers($1)',[q])).rows.map(r => r.username);
for (const [id,username,display] of [[a,'alice','Alice'],[b,'shreyas','Hello'],[c,'carol','Carol']]) {
 await as(id); await db.query('select public.save_social_profile_v2($1,$2,true,$3,null)',[username,display,'']);
}
// A brand-new private climber, with no friends or posts yet, is found by username and display name.
await as(a);
assert.deepEqual(await names('shreyas'), ['shreyas']);
assert.deepEqual(await names('hell'), ['shreyas']);
// The table itself still doesn't list strangers.
assert.equal((await db.query('select * from public.climber_profiles')).rows.length, 1);
// Never yourself, never too short, wildcards are literal, blocked climbers are hidden both ways.
assert.deepEqual(await names('alice'), []);
assert.deepEqual(await names('s'), []);
assert.deepEqual(await names('%'), []);
await db.query("select public.block_climber($1)",[c]);
assert.deepEqual(await names('carol'), []);
await as(c); assert.deepEqual(await names('alice'), []);
// Signed-out callers can't search.
await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub','',false)"); await db.exec('set role anon');
await assert.rejects(db.query("select * from public.search_climbers('shreyas')"));
console.log('Search checks passed.');

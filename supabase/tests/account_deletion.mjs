// Account deletion policy test. Run with Node and @electric-sql/pglite (0.5.11).
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
const [a,b] = [1,2].map(i => `00000000-0000-0000-0000-00000000000${i}`);
for (const id of [a,b]) await db.query('insert into auth.users values($1)',[id]);
async function as(id) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); }
async function rows(sql) { await db.exec('reset role'); return (await db.query(sql)).rows.length; }
for (const [id,name] of [[a,'alice'],[b,'bob']]) { await as(id); await db.query('select public.save_social_profile($1,$2,false)',[name,name]); }
await as(a);
await db.query("select public.save_shared_session('10000000-0000-0000-0000-000000000001','friends','Caption','2026-10-24',3,1,null,'Recalled activity')");
await db.query("select public.friend_action($1,'request')",[b]);
await as(b); await db.query("select public.friend_action($1,'accept')",[a]);
await db.query("select public.report_climber($1,'test')",[a]);
await as(a); await db.query("select public.report_climber($1,'test')",[b]);

// Anonymous callers cannot delete anything.
await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub','',false)"); await db.exec('set role anon');
await assert.rejects(db.exec('select public.delete_account()'));
await db.exec('set role authenticated');
await assert.rejects(db.exec('select public.delete_account()'), /Sign in required/);

await as(a); await db.exec('select public.delete_account()');
assert.equal(await rows(`select * from auth.users where id='${a}'`), 0);
assert.equal(await rows(`select * from public.climber_profiles where id='${a}'`), 0);
assert.equal(await rows('select * from public.shared_sessions'), 0);
assert.equal(await rows('select * from public.friendships'), 0);
assert.equal(await rows(`select * from public.social_reports where reporter='${a}'`), 0);
// The other climber is untouched, and calling again is a harmless no-op.
assert.equal(await rows(`select * from public.climber_profiles where id='${b}'`), 1);
await as(a); await db.exec('select public.delete_account()');
await db.close();
console.log('Account deletion checks passed.');

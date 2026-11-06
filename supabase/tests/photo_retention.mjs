// Route photo retention: 30 days, and only each climber's 10 newest photo posts. Run with Node and @electric-sql/pglite (0.5.11).
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
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
const [a,b] = [1,2].map(i => `00000000-0000-0000-0000-00000000000${i}`);
for (const id of [a,b]) await db.query('insert into auth.users values($1)',[id]);
async function as(id) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); }
async function admin(sql) { await db.exec('reset role'); return (await db.query(sql)).rows; }
for (const [id,name] of [[a,'alice'],[b,'bob']]) { await as(id); await db.query('select public.save_social_profile($1,$2,false)',[name,name]); }
const jpeg = Buffer.from('ffd8ffe000104a464946','hex').toString('base64');
async function post(owner, source = randomUUID()) {
  await as(owner);
  await db.query("select public.save_shared_session_with_photos($1,'friends','','2026-11-05',null,1,null,'Sends only',$2::jsonb)",
    [source, JSON.stringify([{ id: randomUUID(), original_base64: jpeg }])]);
  return source;
}
const photoPosts = async owner => (await admin(`select s.source_session_id from public.shared_sessions s
  where s.owner_id='${owner}' and s.route_photo_count>0 and exists(select 1 from public.shared_route_photos p where p.entry_id=s.id)`)).map(r=>r.source_session_id);

// Photos older than 30 days go, the post itself stays.
const old = await post(b);
await admin(`update public.shared_route_photos set created_at=now()-interval '31 days'`);
await post(a);
assert.deepEqual(await photoPosts(b), []);
assert.equal((await admin(`select * from public.shared_sessions where source_session_id='${old}'`)).length, 1);

// Each climber keeps photos on their 10 newest photo posts, and the one just saved always stays.
await admin('delete from public.shared_sessions');
const sources = [];
for (let i = 0; i < 12; i++) {
  sources.push(await post(a));
  await admin(`update public.shared_route_photos set created_at=created_at-interval '1 minute'`);
}
const kept = await photoPosts(a);
assert.equal(kept.length, 10);
assert.ok(kept.includes(sources.at(-1)));
assert.ok(!kept.includes(sources[0]) && !kept.includes(sources[1]));
assert.equal((await admin(`select * from public.shared_sessions where owner_id='${a}'`)).length, 12);
// Another climber's photos are untouched by alice's cap.
await post(b);
assert.equal((await photoPosts(b)).length, 1);
assert.equal((await photoPosts(a)).length, 10);
console.log('photo retention checks passed');

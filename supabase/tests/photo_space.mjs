// Friends photo space budget: trim the poster's own oldest photos, else post without photos. Run with Node and @electric-sql/pglite (0.5.11).
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
const jpeg = Buffer.from('ffd8ffe000104a464946','hex').toString('base64'); // 16 bytes as text
// Room for exactly three photos.
await admin(`create or replace function social_private.photo_space_budget() returns bigint language sql stable set search_path='' as $$ select ${3 * jpeg.length}::bigint $$`);

async function post(owner, count = 1, source = randomUUID()) {
  await as(owner);
  const photos = Array.from({ length: count }, () => ({ id: randomUUID(), original_base64: jpeg }));
  const outcome = (await db.query("select public.save_shared_session_with_photos($1,'friends','','2026-11-05',null,1,null,'Sends only',$2::jsonb) as r",
    [source, JSON.stringify(photos)])).rows[0].r;
  await admin(`update public.shared_route_photos set created_at=created_at-interval '1 minute'`);
  return { source, outcome };
}
const photosOn = async source => (await admin(`select s.route_photo_count n, (select count(*)::int from public.shared_route_photos p where p.entry_id=s.id) c
  from public.shared_sessions s where s.source_session_id='${source}'`))[0];

// Room left: saved as usual.
const [p1, p2, p3] = [await post(a), await post(a), await post(a)];
assert.deepEqual([p1, p2, p3].map(p => p.outcome), ['saved', 'saved', 'saved']);

// Full: alice's oldest post loses its photos to make room, and keeps the post.
const p4 = await post(a);
assert.equal(p4.outcome, 'trimmed');
assert.deepEqual(await photosOn(p1.source), { n: 0, c: 0 });
assert.deepEqual(await photosOn(p4.source), { n: 1, c: 1 });

// Full and bob has nothing of his own to remove: the post saves without photos, alice's stay.
const bob = await post(b);
assert.equal(bob.outcome, 'no_space');
assert.deepEqual(await photosOn(bob.source), { n: 0, c: 0 });
assert.equal((await admin('select count(*)::int c from public.shared_route_photos'))[0].c, 3);

// Re-saving a post reuses its own space; a post without photos is never blocked.
assert.equal((await post(a, 1, p4.source)).outcome, 'saved');
assert.equal((await post(b, 0)).outcome, 'saved');

// A bigger post removes as many of alice's older posts as it needs.
const big = await post(a, 3);
assert.equal(big.outcome, 'trimmed');
assert.deepEqual(await photosOn(big.source), { n: 3, c: 3 });
for (const p of [p2, p3, p4]) assert.deepEqual(await photosOn(p.source), { n: 0, c: 0 });

// Climbers can't read or change the budget.
await as(a);
await assert.rejects(db.query('select social_private.photo_space_budget()'), /permission denied/);
console.log('photo space checks passed');

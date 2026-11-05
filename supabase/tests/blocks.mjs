// Unfriending and block lifecycle test. Run with Node and @electric-sql/pglite (0.5.11).
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
// The journal migration is not live yet, so test the schema that is.
for (const file of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql') && !x.includes('journal_and_places')).sort()) {
 await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
}
const [a,b,c] = [1,2,3].map(i => `00000000-0000-0000-0000-00000000000${i}`);
for (const id of [a,b,c]) await db.query('insert into auth.users values($1)',[id]);
async function as(id) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); }
async function rows(sql) { await db.exec('reset role'); return (await db.query(sql)).rows.length; }
for (const [id,name] of [[a,'alice'],[b,'bob'],[c,'cara']]) { await as(id); await db.query('select public.save_social_profile($1,$2,false)',[name,name]); }
async function befriend(requester, recipient) {
  await as(requester); await db.query("select public.friend_action($1,'request')",[recipient]);
  await as(recipient); await db.query("select public.friend_action($1,'accept')",[requester]);
  assert.equal(await rows("select * from public.friendships where status='accepted'"), 1);
}

// Either friend can unfriend the other, and it removes the friendship for both.
await befriend(a,b);
await as(a); await db.query("select public.friend_action($1,'remove')",[b]);
assert.equal(await rows('select * from public.friendships'), 0);
await befriend(a,b);
await as(b); await db.query("select public.friend_action($1,'remove')",[a]);
assert.equal(await rows('select * from public.friendships'), 0);
// After unfriending, either one can send a new request.
await befriend(b,a);
await as(a); await db.query("select public.friend_action($1,'remove')",[b]);

// A block survives the blocked climber deleting and recreating their profile.
await as(a); await db.query('select public.block_climber($1)',[b]);
await db.query('select public.dismiss_friend_suggestion($1)',[c]);
await as(b); await db.exec('select public.delete_social_profile()');
assert.equal(await rows(`select * from public.climber_blocks where owner_id='${a}' and target_id='${b}'`), 1);
await db.query("select public.save_social_profile('bob','bob',false)");
assert.equal(await rows(`select * from public.climber_blocks where owner_id='${a}' and target_id='${b}'`), 1);
await as(b); await assert.rejects(db.query("select public.friend_action($1,'request')",[a]), /Unavailable/);
await as(b); assert.equal((await db.query(`select * from public.climber_profiles where id='${a}'`)).rows.length, 0);
await as(c); await db.exec('select public.delete_social_profile()');
await db.query("select public.save_social_profile('cara','cara',false)");
assert.equal(await rows(`select * from public.friend_suggestion_dismissals where owner_id='${a}' and target_id='${c}'`), 1);

// A climber with no social profile can still be blocked.
await as(c); await db.exec('select public.delete_social_profile()');
await as(a); await db.query('select public.block_climber($1)',[c]);
assert.equal(await rows(`select * from public.climber_blocks where owner_id='${a}' and target_id='${c}'`), 1);

// Blocks still go away with the whole account, on either side.
await as(b); await db.exec('select public.delete_account()');
assert.equal(await rows(`select * from public.climber_blocks where target_id='${b}'`), 0);
await as(a); await db.exec('select public.delete_account()');
assert.equal(await rows('select * from public.climber_blocks'), 0);
assert.equal(await rows('select * from public.friend_suggestion_dismissals'), 0);
console.log('Block lifecycle checks passed');

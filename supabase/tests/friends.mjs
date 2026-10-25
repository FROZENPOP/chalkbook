// Run with Node and an installed @electric-sql/pglite (0.5.11).
// PGlite executes PostgreSQL, including roles, RLS and SECURITY DEFINER functions.
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`create role anon; create role authenticated;
create schema auth; create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;`);
await db.exec(await readFile(new URL('../migrations/202610240001_friends.sql', import.meta.url), 'utf8'));
const [a,b,c] = [1,2,3].map(i => `00000000-0000-0000-0000-00000000000${i}`);
const source = '10000000-0000-0000-0000-000000000001';
for (const id of [a,b,c]) await db.query('insert into auth.users values($1)',[id]);
async function as(id) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); }
async function count(sql) { return (await db.query(sql)).rows.length; }
async function denied(sql) { await assert.rejects(db.exec(sql)); }
let checks = 0;
function equal(actual, expected) { assert.equal(actual,expected); checks++; }
for (const [id,username] of [[a,'alice'],[b,'bob'],[c,'carol']]) {
 await as(id); await db.query('select public.save_social_profile($1,$2,true)',[username,username]);
}
await as(a);
await db.query("select public.save_shared_session($1,'friends','Reviewed caption','2026-10-24',12,4,null,'Recalled activity')",[source]);
await denied(`insert into public.friendships values('${a}','${b}','accepted',now())`); checks++;
await db.query("select public.friend_action($1,'request')",[b]);
await db.query("select public.friend_action($1,'accept')",[b]); // Requester cannot approve it.
equal((await db.query('select status from public.friendships')).rows[0].status,'pending');
await as(b); equal(await count('select * from public.shared_sessions'),0);
await db.query("select public.friend_action($1,'accept')",[a]);
equal(await count('select * from public.shared_sessions'),1);
await as(c); equal(await count('select * from public.shared_sessions'),0);
await as(a);
await db.query("select public.save_shared_session($1,'public','','2026-10-24',null,4,null,'Sends only')",[source]);
equal(await count('select * from public.shared_sessions'),1); // Same source updates, never duplicates.
await as(c); equal(await count('select * from public.shared_sessions'),0); // Private account caps public entries.
await as(a); await db.exec("select public.save_social_profile('alice','Alice',false)");
await as(c); equal(await count('select * from public.shared_sessions'),1);
equal((await db.query('select attempts from public.shared_sessions')).rows[0].attempts,null);
await as(a); await db.exec("select public.save_social_profile('alice','Alice',true)");
await as(c); equal(await count('select * from public.shared_sessions'),0); // Account privacy revokes previously public access.
await as(a); await db.exec("select public.save_social_profile('alice','Alice',false)");
await denied(`select public.save_shared_session('${source}','public','','2026-10-24',3,4,null,'Invalid totals')`); checks++;
await as(c);
await denied("update public.shared_sessions set caption='Forged'"); checks++;
await db.query('select public.remove_shared_session($1)',[source]);
equal(await count('select * from public.shared_sessions'),1); // Cannot remove another owner's entry.
await as(a); await db.query("select public.save_shared_session($1,'private','','2026-10-24',12,4,null,'Recorded')",[source]);
await as(b); equal(await count('select * from public.shared_sessions'),0);
await as(a); await db.query("select public.save_shared_session($1,'friends','','2026-10-24',12,4,null,'Recorded')",[source]);
await as(b); equal(await count('select * from public.shared_sessions'),1);
await db.query("select public.friend_action($1,'remove')",[a]);
equal(await count('select * from public.shared_sessions'),0);
await db.query("select public.friend_action($1,'request')",[a]);
await as(a); await db.query("select public.friend_action($1,'accept')",[b]);
await db.query('select public.block_climber($1)',[b]);
await as(b); equal(await count('select * from public.shared_sessions'),0);
equal(await count(`select * from public.climber_profiles where id='${a}'`),0);
await denied(`select public.friend_action('${a}','request')`); checks++;
await as(a); await db.query('select public.unblock_climber($1)',[b]);
equal(await count('select * from public.friendships'),0); // Unblocking never recreates friendship.
await as(b); await db.query('select public.report_climber($1,$2)',[a,'Spam']);
await denied('select * from public.social_reports'); checks++;
await db.exec('reset role'); equal(await count('select * from public.social_reports'),1);
equal((await db.query(`select count(*)::int as n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('public','social_private') and p.prosecdef and not ('search_path=""'=any(p.proconfig))`)).rows[0].n,0);
await db.exec('set role anon');
await denied('select * from public.shared_sessions'); checks++;
await denied("select public.save_social_profile('fake','Fake',false)"); checks++;
await as(a); await db.exec('select public.delete_social_profile()');
equal(await count('select * from public.shared_sessions'),0);
await db.close();
console.log(`${checks} PostgreSQL permission and privacy checks passed.`);

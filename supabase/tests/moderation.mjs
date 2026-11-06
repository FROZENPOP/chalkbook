// Word filter and report policy test. Run with Node and @electric-sql/pglite (0.5.11).
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
const [a,b,c] = [1,2,3].map(i => `00000000-0000-0000-0000-00000000000${i}`);
for (const id of [a,b,c]) await db.query('insert into auth.users values($1)',[id]);
async function as(id) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); }
async function admin(sql,args) { await db.exec('reset role'); return (await db.query(sql,args)).rows; }
const blocked = (promise) => assert.rejects(promise, (e) => e.code === 'SN001');
for (const [id,name,priv] of [[a,'alice',false],[b,'bob',false],[c,'cara',true]]) { await as(id); await db.query('select public.save_social_profile($1,$2,$3)',[name,name,priv]); }

// a posts publicly; b can see it, c's post stays friends-only.
await as(a);
await db.query("select public.save_shared_session('10000000-0000-0000-0000-000000000001','public','Good day','2026-10-24',3,1,null,'Recalled activity')");
const entry = (await admin("select id from public.shared_sessions where owner_id=$1",[a]))[0].id;
await as(c);
await db.query("select public.save_shared_session('10000000-0000-0000-0000-000000000002','friends','Hidden','2026-10-24',3,1,null,'Recalled activity')");
const hidden = (await admin("select id from public.shared_sessions where owner_id=$1",[c]))[0].id;

// The filter stops listed words wherever people write, including simple letter swaps.
await as(b);
await blocked(db.query("select public.add_session_comment($1,'kill yourself')",[entry]));
await blocked(db.query("select public.add_session_comment($1,'you R3TARD')",[entry]));
await blocked(db.query("select public.save_social_profile('bob','porn',false)"));
await blocked(db.query("select public.save_social_profile_v2('bob','Bob',false,'I am a rapist',null)"));
await blocked(db.query("select public.save_shared_session('10000000-0000-0000-0000-000000000003','public','kys','2026-10-24',3,1,null,'Recalled activity')"));
// Climbing talk gets through.
for (const fine of ['Killed it on the crimp, 3 attempts','Crushed the pinch then the sloper','That grape-sized hold, damn','Therapist says rest']) {
 await db.query('select public.add_session_comment($1,$2)',[entry,fine]);
}
assert.equal((await admin('select * from public.session_comments')).length,4);
const comment = (await admin('select id from public.session_comments order by body limit 1'))[0].id;

// A report keeps a copy of the exact comment or caption.
await as(a); await db.query("select public.report_climber($1,'Rude',comment=>$2)",[b,comment]);
await as(b); await db.query("select public.report_climber($1,'Bad post',entry=>$2)",[a,entry]);
await db.query("select public.report_climber($1,'Just the person')",[a]);
const reports = await admin('select * from public.social_reports order by reason');
const [badPost,justPerson,rude] = reports;
assert.equal(rude.comment_id,comment); assert.equal(rude.entry_id,entry); assert.equal(rude.target_username,'bob'); assert.ok(rude.content);
assert.equal(badPost.entry_id,entry); assert.equal(badPost.content,'Good day'); assert.equal(badPost.comment_id,null);
assert.equal(justPerson.content,null);

// Nobody can pin a comment on the wrong climber or read content through a report.
await as(a); await assert.rejects(db.query("select public.report_climber($1,'Wrong person',comment=>$2)",[c,comment]),/Content unavailable/);
await as(b); await assert.rejects(db.query("select public.report_climber($1,'Peek',entry=>$2)",[c,hidden]),/Content unavailable/);
await assert.rejects(db.query('select * from public.social_reports'));
await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub','',false)"); await db.exec('set role anon');
await assert.rejects(db.query("select public.report_climber($1,'Anon')",[a]));
await db.exec('set role authenticated');
await assert.rejects(db.query("select public.report_climber($1,'Anon')",[a]),/Sign in required/);

// Deleting the reported account keeps the report and its copy, but not the live content.
await as(b); await db.exec('select public.delete_account()');
assert.equal((await admin('select * from public.session_comments')).length,0);
const kept = (await admin("select * from public.social_reports where reason='Rude'"))[0];
assert.equal(kept.target_id,null); assert.equal(kept.target_username,'bob'); assert.ok(kept.content);
assert.equal((await admin("select * from public.social_reports where reason='Bad post'"))[0].reporter,null);

// Reports older than 12 months are purged when the next one arrives.
await admin("update public.social_reports set created_at=now()-interval '13 months' where reason='Rude'");
await as(a); await db.query("select public.report_climber($1,'Newer')",[c]);
assert.equal((await admin("select * from public.social_reports where reason='Rude'")).length,0);
assert.equal((await admin("select * from public.social_reports where reason='Newer'")).length,1);

await db.close();
console.log('Moderation checks passed.');

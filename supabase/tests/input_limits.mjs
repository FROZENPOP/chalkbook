// Server-side input checks that hold even when the app is bypassed. Run with Node and @electric-sql/pglite (0.5.11).
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
const a = '00000000-0000-0000-0000-000000000001';
await db.query('insert into auth.users values($1)',[a]);
await db.query("select set_config('request.jwt.claim.sub',$1,false)",[a]); await db.exec('set role authenticated');
const profile = (name, display, avatar = null) => db.query('select public.save_social_profile_v2($1,$2,false,$3,$4)',[name,display,'',avatar]);
const share = day => db.query("select public.save_shared_session($1,'friends','',$2,null,1,null,'Sends only')",[randomUUID(),day]);
// Zero-width joiners and non-joiners build emoji and Persian or Indic words; every other hidden character stays out.
const joined = ['Ana 🧗‍♀️ 👨‍👩‍👧 🏳️‍🌈', 'می‌خواهم'], hidden = ['\u200b', '\u200e', '\u2066', '\ufeff'];

// Names: no invisible, spoofing or staff-looking names.
for (const display of ['\u200b', '\u00a0', 'Bob\u202eevil', 'Line\nbreak', 'Chalkbook Support', ...hidden.map(c => `Bob${c}x`)])
  await assert.rejects(profile('alice', display), /check constraint/, JSON.stringify(display));
for (const name of ['support', 'admin', 'chalkbook_team'])
  await assert.rejects(profile(name, 'Alice'), /check constraint/, name);
await assert.rejects(profile('alice', 'Alice', Buffer.from('not a jpeg').toString('base64')), /avatar_is_jpeg/);
await profile('alice', 'Alicé 🧗', Buffer.from('ffd8ffe0','hex').toString('base64'));
for (const display of joined) await profile('alice', display);

// Bios, captions and comments: no hidden or text-direction characters, but line breaks are fine.
const bio = text => db.query('select public.save_social_profile_v2($1,$2,false,$3,null)',['alice','Alice',text]);
for (const text of ['safe\u202eevil', 'bell\u0007', 'hidden\u200bword', '\ufeffstart', ...hidden.map(c => `a${c}b`)])
  await assert.rejects(bio(text), /bio_plain/, JSON.stringify(text));
await bio('Line one\nLine two\twith a tab');
for (const text of joined) await bio(text);

// Session days must be real dates, not far in the future.
await assert.rejects(share('9999-12-31'), /Invalid session day/);
await assert.rejects(share('2026-99-99'));
await assert.rejects(share('1999-12-31'), /Invalid session day/);
await assert.rejects(db.query("select public.save_shared_session($1,'friends',$2,$3,null,1,null,'Sends only')",
  [randomUUID(),'great\u202esend',new Date().toISOString().slice(0,10)]), /caption_plain/);
const caption = text => db.query("select public.save_shared_session($1,'friends',$2,$3,null,1,null,'Sends only')",
  [randomUUID(),text,new Date().toISOString().slice(0,10)]);
for (const c of hidden) await assert.rejects(caption(`a${c}b`), /caption_plain/, JSON.stringify(c));
for (const text of joined) await caption(text);
await share(new Date().toISOString().slice(0,10));
const entry = (await db.query('select id from public.shared_sessions limit 1')).rows[0].id;

// Comments must have visible text, and at most 10 a minute.
await assert.rejects(db.query('select public.add_session_comment($1,$2)',[entry,'\u00a0\u200b']), /check constraint/);
await assert.rejects(db.query('select public.add_session_comment($1,$2)',[entry,'nice\u202eclimb']), /body_plain/);
for (const c of hidden) await assert.rejects(db.query('select public.add_session_comment($1,$2)',[entry,`a${c}b`]), /body_plain/, JSON.stringify(c));
for (const text of joined) await db.query('select public.add_session_comment($1,$2)',[entry,text]);
for (let i = joined.length; i < 10; i++) await db.query('select public.add_session_comment($1,$2)',[entry,`nice ${i}`]);
await assert.rejects(db.query('select public.add_session_comment($1,$2)',[entry,'one more']), /Too many comments/);
// A report pings the moderator once, nothing else can, and reports are capped per day.
const b = '00000000-0000-0000-0000-000000000002';
const as = async id => { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); };
await db.exec('reset role'); await db.query('insert into auth.users values($1)',[b]);
await as(b); await db.query("select public.save_social_profile('bob','Bob',false)");
await as(a);
const claim = async () => (await db.query('select public.claim_report_alert() as ok')).rows[0].ok;
assert.equal(await claim(), false, 'no report, no alert');
await db.query("select public.report_climber($1,'spam')",[b]);
assert.equal(await claim(), true);
assert.equal(await claim(), false, 'one alert per report');
for (let i = 1; i < 20; i++) await db.query("select public.report_climber($1,'spam')",[b]);
await assert.rejects(db.query("select public.report_climber($1,'spam')",[b]), /Too many reports/);
// Reports from other accounts are claimed but don't ping again within 10 minutes.
await as(b); await db.query("select public.report_climber($1,'spam')",[a]);
assert.equal(await claim(), false, 'one ping per 10 minutes across reporters');
assert.equal(await claim(), false);
// Strangers can't list every climber, but can still open one profile by id.
await as(a);
assert.deepEqual((await db.query('select id from public.climber_profiles')).rows.map(r=>r.id), [a]);
assert.equal((await db.query('select * from public.climber_profile($1)',[b])).rows[0].username, 'bob');
console.log('input limit checks passed');
